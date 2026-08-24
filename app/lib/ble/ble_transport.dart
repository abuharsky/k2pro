import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'protocol.dart';
import 'trace.dart';
import 'transport.dart';

/// Реальный BLE поверх flutter_blue_plus.
class BleTransport implements K2Transport {
  BleTransport();

  final _scanCtl = StreamController<List<DiscoveredDevice>>.broadcast();
  final _linkCtl = StreamController<LinkState>.broadcast();
  final _notifyCtl = StreamController<Uint8List>.broadcast();

  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<BluetoothConnectionState>? _connSub;
  StreamSubscription<List<int>>? _valueSub;

  /// На macOS/iOS remoteId — это UUID, выданный CoreBluetooth.
  /// Пересобрать из строки объект можно, но надёжнее держать тот,
  /// который вернул скан.
  final Map<String, BluetoothDevice> _seen = {};

  /// Чтобы отладочный лог не повторял одно и то же объявление раз в секунду.
  final Set<String> _logged = {};

  BluetoothDevice? _device;
  BluetoothCharacteristic? _writeChar;
  LinkState _link = LinkState.disconnected;

  @override
  Stream<List<DiscoveredDevice>> get scanResults => _scanCtl.stream;

  @override
  Stream<LinkState> get linkState => _linkCtl.stream;

  @override
  Stream<Uint8List> get notifications => _notifyCtl.stream;

  @override
  LinkState get currentLinkState => _link;

  void _setLink(LinkState s) {
    if (_link == s) return;
    _link = s;
    _linkCtl.add(s);
  }

  @override
  Future<void> startScan({
    Duration timeout = const Duration(seconds: 15),
    bool showAll = false,
  }) async {
    if (!await FlutterBluePlus.isSupported) {
      throw StateError('Bluetooth не поддерживается на этом устройстве');
    }

    // Адаптер после старта процесса какое-то время в состоянии unknown;
    // скан, запущенный в этот момент, тихо не даёт результатов.
    final st = await FlutterBluePlus.adapterState
        .where((s) => s != BluetoothAdapterState.unknown)
        .first
        .timeout(
          const Duration(seconds: 5),
          onTimeout: () => BluetoothAdapterState.unknown,
        );
    if (st != BluetoothAdapterState.on) {
      throw StateError(
        'Bluetooth выключен или недоступен (состояние: ${st.name}). '
        'Проверьте, что Bluetooth включён и приложению разрешён доступ '
        'в «Системные настройки → Конфиденциальность → Bluetooth».',
      );
    }

    _logged.clear();
    await _scanSub?.cancel();
    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      final list = <DiscoveredDevice>[];
      for (final r in results) {
        final name = _advName(r);
        _seen[r.device.remoteId.str] = r.device;
        final known = kNamePrefixes.any(name.startsWith);
        if (!known && !showAll) continue;
        list.add(
          DiscoveredDevice(
            id: r.device.remoteId.str,
            advertisedName: name.isEmpty ? '(без имени)' : name,
            rssi: r.rssi,
            known: known,
          ),
        );
      }
      list.sort((a, b) {
        if (a.known != b.known) return a.known ? -1 : 1;
        return (b.rssi ?? -999).compareTo(a.rssi ?? -999);
      });
      if (kDebugMode) {
        for (final r in results) {
          if (!_logged.add(r.device.remoteId.str)) continue;
          debugPrint(
            '[scan] "${_advName(r)}" id=${r.device.remoteId.str} '
            'rssi=${r.rssi} svc=${r.advertisementData.serviceUuids} '
            'mfd=${r.advertisementData.manufacturerData.keys.toList()}',
          );
        }
      }
      _scanCtl.add(list);
    });

    // Фильтр по имени делаем сами: машина не рекламирует сервис FFF0.
    await FlutterBluePlus.startScan(timeout: timeout);
  }

  /// Выложить в трассу всё дерево GATT — не только FFF0.
  ///
  /// Нужно затем, что за пределами рабочего сервиса машина может держать
  /// стандартные атрибуты профиля: имя (0x2A00), модель, версию прошивки.
  /// Свойства покажут, можно ли туда писать; значения — что там лежит.
  /// Читаем только 16-битные `0x2Axx`: это атрибуты самого профиля Bluetooth,
  /// они инертны. Ничего вендорского не трогаем.
  Future<void> _dumpGatt(List<BluetoothService> services) async {
    if (!kDebugMode || Trace.inTest) return;
    for (final s in services) {
      for (final c in s.characteristics) {
        final pr = c.properties;
        final flags = [
          if (pr.read) 'read',
          if (pr.write) 'write',
          if (pr.writeWithoutResponse) 'writeNoResp',
          if (pr.notify) 'notify',
          if (pr.indicate) 'indicate',
        ].join(',');
        var value = '';
        final short = c.uuid.str.toLowerCase();
        if (pr.read && short.length == 4 && short.startsWith('2a')) {
          try {
            final v = await c.read();
            value = ' = ${_printable(v)}';
          } catch (e) {
            value = ' = <не читается: $e>';
          }
        }
        Trace.instance.log(
          'gatt ${s.uuid.str}/${c.uuid.str} [$flags]$value',
        );
      }
    }
  }

  /// Значение атрибута: текстом, если это текст, иначе байтами.
  static String _printable(List<int> v) {
    final text = v.every((b) => b >= 0x20 && b < 0x7F);
    final hex = v.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
    return text && v.isNotEmpty ? '"${String.fromCharCodes(v)}" ($hex)' : hex;
  }

  static String _advName(ScanResult r) {
    final n = r.advertisementData.advName;
    return n.isNotEmpty ? n : r.device.platformName;
  }

  @override
  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
    await _scanSub?.cancel();
    _scanSub = null;
  }

  @override
  Future<void> connect(String deviceId) async {
    await stopScan();
    _setLink(LinkState.connecting);

    final device = _seen[deviceId] ?? BluetoothDevice.fromId(deviceId);
    _device = device;

    await _connSub?.cancel();
    _connSub = device.connectionState.listen((s) {
      if (s == BluetoothConnectionState.disconnected) {
        _writeChar = null;
        _setLink(LinkState.disconnected);
      }
    });

    // Оригинал делает до шести попыток с паузой в секунду.
    Object? lastError;
    for (var attempt = 0; attempt < 6; attempt++) {
      try {
        await device.connect(timeout: const Duration(seconds: 15));
        lastError = null;
        break;
      } catch (e) {
        lastError = e;
        if (kDebugMode) debugPrint('[connect] попытка $attempt: $e');
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }
    if (lastError != null) {
      _setLink(LinkState.disconnected);
      throw StateError('Не удалось подключиться: $lastError');
    }

    final services = await device.discoverServices();
    await _dumpGatt(services);
    final svc = services.firstWhere(
      (s) => s.uuid.str128.toLowerCase() == kServiceUuid,
      orElse: () => throw StateError('Сервис FFF0 не найден'),
    );

    BluetoothCharacteristic charFor(String uuid) =>
        svc.characteristics.firstWhere(
          (c) => c.uuid.str128.toLowerCase() == uuid,
          orElse: () => throw StateError('Характеристика $uuid не найдена'),
        );

    final notifyChar = charFor(kNotifyUuid);
    _writeChar = charFor(kWriteUuid);

    await _valueSub?.cancel();
    _valueSub = notifyChar.onValueReceived.listen((v) {
      _notifyCtl.add(Uint8List.fromList(v));
    });
    await notifyChar.setNotifyValue(true);

    // На iOS/macOS MTU не запрашивается вручную — вызов там не поддерживается.
    try {
      await device.requestMtu(kRequestMtu);
    } catch (_) {
      // не критично
    }

    _setLink(LinkState.connected);
  }

  @override
  Future<void> disconnect() async {
    await _valueSub?.cancel();
    _valueSub = null;
    _writeChar = null;
    await _device?.disconnect();
    _setLink(LinkState.disconnected);
  }

  @override
  Future<void> write(Uint8List frame) async {
    final c = _writeChar;
    if (c == null) throw StateError('Нет подключения');
    // Пишем С подтверждением, если характеристика умеет. Запись без ответа
    // не имеет никакой доставки на уровне ATT: контроллер вправе выбросить
    // кадр молча, и в живых логах ровно это и происходило — из серии команд
    // рукопожатия один кадр пропадал примерно в двух подключениях из трёх.
    await c.write(frame, withoutResponse: !c.properties.write);
  }

  @override
  Future<void> dispose() async {
    await _scanSub?.cancel();
    await _connSub?.cancel();
    await _valueSub?.cancel();
    await _scanCtl.close();
    await _linkCtl.close();
    await _notifyCtl.close();
  }
}
