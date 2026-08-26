import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'protocol.dart';
import 'scale/mock_scale_transport.dart' show kMockScaleId;
import 'transport.dart';

/// Идентификатор машины-симулятора. Демо-режим подключается прямо к нему,
/// минуя поиск: искать в эфире нечего.
const String kMockMachineId = 'mock-k2pro';

/// Симулятор машины: позволяет гонять приложение на Mac без железа.
///
/// Отвечает настоящими кадрами протокола, поэтому проверяет и кодек, и UI.
class MockTransport implements K2Transport {
  MockTransport({DateTime Function()? now, this.faultCycle = const []})
    : _now = now ?? DateTime.now;

  /// Ошибки, которые симулятор разыгрывает по кругу: одна на прогон.
  ///
  /// Пусто — машина всегда исправна; так собраны тесты, которым ошибки только
  /// мешали бы. Демо задаёт чередование, где каждый второй прогон ломается:
  /// иначе половина того, что приложение умеет — сорванный цикл, запертый пуск,
  /// подсказка «добавьте воду», — на симуляторе никогда не показывается.
  ///
  /// Порядок именно постоянный, а не случайный: демо надо уметь *показывать*,
  /// а для этого знать, что случится на следующем пуске.
  final List<MachineError> faultCycle;

  /// Часы симулятора. Отдельным аргументом, чтобы сквозной тест мог гонять
  /// пролив быстрее реального времени: без этого весь контур останова
  /// проверялся бы только на живом кофе.
  final DateTime Function() _now;

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

  /// Сколько тиков прошло с прошлой убыли заряда.
  ///
  /// Считать нужно именно тики, а не сажать заряд каждый: тик — полсекунды, и
  /// по единице за тик симулятор садил батарею с 78 до нуля за минуту работы.
  /// Ниже 25 это уже деление 1, то есть предупреждение «заряда мало, точно
  /// пускать?» — на живом показе оно вылезало на втором же цикле.
  int _sinceBattery = 0;

  MachineState _state = MachineState.standby;

  /// Когда температура впервые дошла до уставки. От неё симулятор считает
  /// времена пролива — так же, как это делает `BrewPhaseEstimator` в
  /// приложении.
  DateTime? _heatReachedAt;

  /// Ошибка, которую машина положит в следующий кадр телеметрии.
  ///
  /// Ставится снаружи (тестом) или самим симулятором из [faultCycle]. Живая
  /// машина повторяет код пакет-другой и гасит его сама — [_faultLeft] делает
  /// то же самое.
  MachineError fault = MachineError.none;

  /// Сколько кадров ещё повторять [fault]. Ноль — гасим.
  int _faultLeft = 0;

  /// Сколько прогонов симулятор уже отработал. По нему выбирается ошибка из
  /// [faultCycle].
  int _runs = 0;

  /// Что сорвёт текущий прогон, когда он дойдёт до середины экстракции.
  MachineError _pendingFault = MachineError.none;
  Appointment _appointment = const Appointment.disabled();

  /// Всё, что приложение записало. По этому списку видно, сколько кадров ушло
  /// на самом деле, — дёрнуть метод и отправить кадр это разные вещи.
  final List<Uint8List> sent = [];

  /// Сколько раз приложение поднимало линию. По нему видно пересборку.
  int connects = 0;
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
      // Симулятор находит и машину, и весы: экран подключения должен уметь
      // показать оба вида, а без второй строки это никак не проверить.
      _scanCtl.add(const [
        DiscoveredDevice(
          id: kMockMachineId,
          advertisedName: '${kNamePrefix}_SIM',
          rssi: -47,
        ),
        DiscoveredDevice(
          id: kMockScaleId,
          advertisedName: 'DOT_SIM',
          rssi: -61,
          kind: DeviceKind.scale,
        ),
      ]);
    });
  }

  @override
  Future<void> stopScan() async => _scanTimer?.cancel();

  @override
  Future<void> connect(String deviceId) async {
    connects++;
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

  /// Сколько ближайших кадров пуска машина проглотит молча.
  ///
  /// Живой PCM03SMAX так и делает: кадр 0x02 уходит, ответа нет, состояние не
  /// меняется — а точно такой же следующий он подтверждает за 89 мс. Пока пуск
  /// шёл без повторов, такое нажатие пропадало совсем.
  int swallowStarts = 0;

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
        if (payload[1] == 1 && swallowStarts > 0) {
          swallowStarts--;
          return;
        }
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
      _heatReachedAt = null;
      return;
    }
    _phaseStart = _now();
    _heatReachedAt = null;
    // Ошибку прогона выбираем на пуске, а не в момент срыва: так она известна
    // заранее и её видно в трассе с самого начала цикла.
    _pendingFault = faultCycle.isEmpty
        ? MachineError.none
        : faultCycle[_runs % faultCycle.length];
    _runs++;
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

  /// Сколько воды машина льёт прямо сейчас, г/с. Ноль — не льёт.
  ///
  /// Нужно симулятору весов: настоящие весы узнают о проливе по воде, а не по
  /// кадру телеметрии, и весь контур останова держится именно на этом.
  /// Смачивание идёт тонкой струёй, выстаивание — сухая пауза, экстракция —
  /// рабочий поток.
  double get pourFlow {
    if (!_state.isBusy || _state == MachineState.heating) return 0;
    final since =
        _heatReachedAt ?? (_state == MachineState.brewing ? _phaseStart : null);
    if (since == null) return 0;
    final t = _now().difference(since).inMilliseconds / 1000;
    if (t < _pre) return 0.8;
    if (t < _pre + _still) return 0;
    if (t < _pre + _still + _ext) return 2.0;
    return 0;
  }

  void _step() {
    final busy = _state.isBusy;
    if (busy && _breakDown()) return;
    if (busy) {
      if (_state != MachineState.brewing && _temp < _target) {
        _temp = min(_target.toDouble(), _temp + 2.4);
      } else {
        _heatReachedAt ??= _now();
        final started = _phaseStart ?? _now();
        final total = _pre + _still + _ext;
        if (_now().difference(started).inSeconds > total) {
          _state = switch (_state) {
            MachineState.heating => MachineState.heatDone,
            MachineState.brewing => MachineState.brewDone,
            _ => MachineState.heatBrewDone,
          };
          _todayCups++;
        }
      }
      if (++_sinceBattery >= 20 && _battery > 0) {
        _sinceBattery = 0;
        _battery--;
      }
    } else if (_temp > 24) {
      _temp -= 0.6;
    }
    _sendState();
  }

  /// Сорвать прогон, если его очередь ломаться и он дошёл до середины
  /// экстракции.
  ///
  /// Ошибка на пуске показала бы только баннер; интересно другое — как
  /// обрывается уже идущий пролив: рушится таймлайн, встаёт вес, запирается
  /// пуск до «Проверить».
  bool _breakDown() {
    if (_pendingFault == MachineError.none) return false;
    final since =
        _heatReachedAt ?? (_state == MachineState.brewing ? _phaseStart : null);
    if (since == null) return false;
    final t = _now().difference(since).inMilliseconds / 1000;
    if (t < _pre + _still + _ext * 0.4) return false;

    fault = _pendingFault;
    _faultLeft = 2;
    _pendingFault = MachineError.none;
    // Машина встаёт сама — она не доливает после аварии.
    _state = MachineState.standby;
    _phaseStart = null;
    _heatReachedAt = null;
    _sendState();
    return true;
  }

  void _sendState() {
    _reply(Cmd.deviceState, [
      0,
      _battery & 0x7F,
      0,
      _temp.round(),
      _state.code,
      fault.code,
    ]);
    // Код держится пакет-другой и гаснет — как на живой машине. В приложении
    // он при этом остаётся в `lastFault`, пока человек не нажмёт «Проверить».
    if (_faultLeft > 0 && --_faultLeft == 0) fault = MachineError.none;
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
