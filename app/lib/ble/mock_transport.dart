import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'protocol.dart';
import 'transport.dart';

/// Симулятор машины: позволяет гонять приложение на Mac без железа.
///
/// Отвечает настоящими кадрами протокола, поэтому проверяет и кодек, и UI.
class MockTransport implements K2Transport {
  MockTransport();

  final _scanCtl = StreamController<List<DiscoveredDevice>>.broadcast();
  final _linkCtl = StreamController<LinkState>.broadcast();
  final _notifyCtl = StreamController<Uint8List>.broadcast();

  LinkState _link = LinkState.disconnected;
  Timer? _tick;
  Timer? _scanTimer;

  // Состояние «машины».
  double _temp = 24;

  /// Внутри мока температура в °C, как и в приложении; наружу, в кадры 0x15 /
  /// 0x16 / 0x20, уходит °F — так же, как это делает живая машина.
  int _target = 92;
  int _flow = 7;
  int _pre = 5;
  int _still = 5;
  int _ext = 70;
  int _battery = 78;
  MachineState _state = MachineState.standby;
  final MachineError _error = MachineError.none;
  Appointment _appointment = const Appointment.disabled();

  /// Всё, что приложение записало. По этому списку видно, сколько кадров ушло
  /// на самом деле, — дёрнуть метод и отправить кадр это разные вещи.
  final List<Uint8List> sent = [];
  int _todayCups = 2;
  DateTime? _phaseStart;

  @override
  Stream<List<DiscoveredDevice>> get scanResults => _scanCtl.stream;

  @override
  Stream<LinkState> get linkState => _linkCtl.stream;

  @override
  Stream<Uint8List> get notifications => _notifyCtl.stream;

  @override
  LinkState get currentLinkState => _link;

  void _setLink(LinkState s) {
    _link = s;
    _linkCtl.add(s);
  }

  @override
  Future<void> startScan({
    Duration timeout = const Duration(seconds: 15),
    bool showAll = false,
  }) async {
    _scanCtl.add(const []);
    _scanTimer?.cancel();
    _scanTimer = Timer(const Duration(milliseconds: 700), () {
      _scanCtl.add(const [
        DiscoveredDevice(
          id: 'mock-k2pro',
          advertisedName: '${kNamePrefix}_SIM',
          rssi: -47,
        ),
      ]);
    });
  }

  @override
  Future<void> stopScan() async => _scanTimer?.cancel();

  @override
  Future<void> connect(String deviceId) async {
    _setLink(LinkState.connecting);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    _setLink(LinkState.connected);
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(milliseconds: 500), (_) => _step());
  }

  @override
  Future<void> disconnect() async {
    _tick?.cancel();
    _tick = null;
    _setLink(LinkState.disconnected);
  }

  /// Оборвать связь так, будто машину унесли, — без ведома приложения.
  ///
  /// Отличается от [disconnect] намерением: там рвём мы, здесь эфир. Проверять
  /// переподключение больше нечем.
  void dropLink() {
    _tick?.cancel();
    _tick = null;
    _setLink(LinkState.disconnected);
  }

  /// Спящая машина: подключение и подписку принимает, кадры глотает молча.
  ///
  /// Ровно то, что PCM03SMAX делает в спящем режиме, — и то, на чём приложение
  /// вставало колом: опрос уходил в пустоту, держа линию по четыре секунды за
  /// запрос, а нажатая кнопка ждала своей очереди за ним.
  bool mute = false;

  @override
  Future<void> write(Uint8List frame) async {
    sent.add(Uint8List.fromList(frame));
    if (mute) return;
    // Разбираем как приходящий кадр, подменив стартовый байт.
    final rx = Uint8List.fromList(frame);
    final cmd = rx[4];
    final payload = rx.sublist(5);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    switch (cmd) {
      case Cmd.setTime:
        _reply(cmd, const []);
      case Cmd.getTempSetting:
        // 100…204 °F — то, что отдаёт живой PCM03SMAX.
        _reply(cmd, [100, 204, celsiusToWire(_target)]);
      case Cmd.setTempSetting:
        _target = celsiusFromWire(payload[0]);
        _reply(cmd, [celsiusToWire(_target)]);
      case Cmd.getWorkParams:
        _reply(cmd, [_flow, _pre, 3, 30, _still, 0, 60, _ext, 20, 120, 1, 15]);
      case Cmd.setWorkParams:
        _flow = payload[0];
        _pre = payload[1];
        _still = payload[2];
        if (payload.length > 3) _ext = payload[3];
        _reply(cmd, [_flow, _pre, _still, _ext]);
      case Cmd.reset:
        _flow = 7;
        _pre = 5;
        _still = 5;
        _ext = 70;
        _target = 92;
        _reply(cmd, [_flow, _pre, _still, celsiusToWire(_target), _ext]);
      case Cmd.setWorkState:
        // Байты идут [режим, пуск] — так же, как их читает живая машина.
        _onWorkState(payload[1] == 1, payload[0]);
        _reply(cmd, [payload[0], payload[1]]);
      case Cmd.getAppointment:
        _replyAppointment(cmd);
      case Cmd.setAppointment:
        _appointment = parseAppointment(Uint8List.fromList(payload));
        // Живая машина на 0x23 отвечает одним байтом «принято», а не эхом
        // будильника: эхо приходит только на запрос 0x24.
        _reply(cmd, const [1]);
      case Cmd.todayCups:
        _reply(cmd, [_todayCups]);
      case Cmd.cups:
        if (payload.isNotEmpty && payload[0] == 1) _todayCups = 0;
        _reply(cmd, [0, 0, _todayCups, 3, 1, 0, 4, 2, 0, 1]);
      case Cmd.deviceInfo:
        _replyDeviceInfo(cmd);
      default:
        _reply(cmd, const []);
    }
  }

  void _onWorkState(bool start, int workModeCode) {
    if (!start) {
      _state = MachineState.standby;
      _phaseStart = null;
      return;
    }
    _phaseStart = DateTime.now();
    _state = switch (workModeCode) {
      0 => MachineState.heating,
      2 => MachineState.brewing,
      _ => MachineState.heatBrewing,
    };
  }

  void _replyAppointment(int cmd) => _reply(cmd, [
    _appointment.mode.code,
    _appointment.hour,
    _appointment.minute,
    _appointment.reminder.code,
    _appointment.beep.code,
    _appointment.enabled ? 1 : 0,
  ]);

  void _replyDeviceInfo(int cmd) {
    const a = 'HW1.0.3';
    const b = 'SW1.6.2';
    const m = 'PCM03SPRO';
    _reply(cmd, [
      0,
      a.length,
      ...a.codeUnits,
      b.length,
      ...b.codeUnits,
      m.length,
      ...m.codeUnits,
    ]);
  }

  void _reply(int cmd, List<int> payload) {
    if (mute) return;
    final total = kHeaderLen + payload.length;
    final lenHi = (total >> 8) & 0x3F;
    final lenLo = total & 0xFF;
    final cs = frameChecksum(kStartRx, lenHi, lenLo, cmd, payload);
    final frame = Uint8List.fromList([
      kStartRx,
      lenHi,
      lenLo,
      cs,
      cmd,
      ...payload,
    ]);
    // Дробим на чанки, как это делает реальный BLE.
    const chunk = 20;
    for (var i = 0; i < frame.length; i += chunk) {
      _notifyCtl.add(
        Uint8List.fromList(frame.sublist(i, min(i + chunk, frame.length))),
      );
    }
  }

  void _step() {
    final busy = _state.isBusy;
    if (busy) {
      if (_state != MachineState.brewing && _temp < _target) {
        _temp = min(_target.toDouble(), _temp + 2.4);
      } else {
        final started = _phaseStart ?? DateTime.now();
        final total = _pre + _still + _ext;
        if (DateTime.now().difference(started).inSeconds > total) {
          _state = switch (_state) {
            MachineState.heating => MachineState.heatDone,
            MachineState.brewing => MachineState.brewDone,
            _ => MachineState.heatBrewDone,
          };
          _todayCups++;
        }
      }
      if (_battery > 0) _battery = max(0, _battery - 1);
    } else if (_temp > 24) {
      _temp -= 0.6;
    }
    _reply(Cmd.deviceState, [
      0,
      _battery & 0x7F,
      0,
      _temp.round(),
      _state.code,
      _error.code,
    ]);
  }

  @override
  Future<void> dispose() async {
    _tick?.cancel();
    _scanTimer?.cancel();
    await _scanCtl.close();
    await _linkCtl.close();
    await _notifyCtl.close();
  }
}
