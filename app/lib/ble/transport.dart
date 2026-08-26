import 'dart:async';
import 'dart:typed_data';

/// Что за устройство нашлось в эфире.
///
/// Различать приходится по имени: сервис у машины и у весов один и тот же —
/// FFF0. BLE-модуль у них одного поставщика, так что по дереву GATT они
/// неотличимы, и единственный признак — как устройство себя называет.
enum DeviceKind { machine, scale, other }

/// Профиль устройства: по чему его узнать в эфире и куда в нём писать.
///
/// Всё, что раньше было прошито в транспорт константами машины, теперь
/// приезжает сюда — иначе второй экземпляр того же транспорта не завести.
class BleProfile {
  const BleProfile({
    required this.kind,
    required this.serviceUuid,
    required this.notifyUuid,
    required this.writeUuid,
    required this.matches,
    this.requestMtu,
  });

  final DeviceKind kind;
  final String serviceUuid;
  final String notifyUuid;
  final String writeUuid;

  /// Наше ли это устройство, судя по имени в эфире.
  final bool Function(String advertisedName) matches;

  /// null — MTU не трогаем.
  final int? requestMtu;
}

/// Найденное устройство.
class DiscoveredDevice {
  const DiscoveredDevice({
    required this.id,
    required this.advertisedName,
    this.rssi,
    this.kind = DeviceKind.machine,
  });

  final String id;
  final String advertisedName;
  final int? rssi;

  /// Чем устройство себя назвало. В режиме «показать все» в список попадает
  /// и посторонняя мелочь — она приезжает как [DeviceKind.other].
  final DeviceKind kind;

  /// Имя совпало с одним из известных профилей.
  bool get known => kind != DeviceKind.other;
}

enum LinkState { disconnected, connecting, connected }

/// Транспорт, спрятанный за интерфейсом: реальный BLE или симулятор.
///
/// Всё, что выше по стеку, о flutter_blue_plus не знает.
abstract class K2Transport {
  Stream<List<DiscoveredDevice>> get scanResults;
  Stream<LinkState> get linkState;
  Stream<Uint8List> get notifications;

  LinkState get currentLinkState;

  /// Поиск общий на все устройства: в эфире один радиоканал, и держать два
  /// независимых скана нельзя — второй просто гасит первый. Поэтому находки
  /// приезжают все сразу, помеченные [DiscoveredDevice.kind], а разбирает их
  /// тот, кто показывает список.
  Future<void> startScan({
    Duration timeout = const Duration(seconds: 15),
    bool showAll = false,
  });
  Future<void> stopScan();

  Future<void> connect(String deviceId);
  Future<void> disconnect();

  /// Запись в характеристику команд. Темп регулирует вызывающий.
  Future<void> write(Uint8List frame);

  Future<void> dispose();
}
