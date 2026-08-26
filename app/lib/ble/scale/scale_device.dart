/// Весы как устройство: связь, отсчёты, поток, команды.
///
/// Живут отдельно от машины и ничего о ней не знают. Общего у них только
/// сканер: радиоканал один, а сервис FFF0 у обоих — различаются они именем.
///
/// Сеанс ведёт та же [Session], что и у машины, и состояния ложатся один в
/// один: `connecting` → `handshaking` (граммы и обычный режим) → `ready`;
/// весы, которые уснули по своему таймауту, — это `dormant`, ровно как
/// дежурный режим машины.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../model/flow_tracker.dart';
import '../protocol.dart' show reconnectDelay;
import '../session.dart';
import '../trace.dart';
import '../transport.dart';
import 'timemore_dot.dart';

class ScaleDevice extends ChangeNotifier {
  ScaleDevice(this._transport, {DateTime Function()? now})
    : _now = now ?? DateTime.now {
    _linkSub = _transport.linkState.listen(_onLink);
    _notifySub = _transport.notifications.listen(_onNotify);
  }

  final K2Transport _transport;

  /// Часы, по которым помечаются отсчёты. От них считается поток, а значит и
  /// упреждение останова, — поэтому они и вынесены наружу: сквозной тест
  /// должен уметь прогнать пролив быстрее живого.
  final DateTime Function() _now;

  late final StreamSubscription<LinkState> _linkSub;
  late final StreamSubscription<Uint8List> _notifySub;

  final _samples = StreamController<WeightSample>.broadcast();
  final FlowTracker _flow = FlowTracker();

  /// Отсчёты как они приходят. На них подписан тот, кто ведёт пролив; экрану
  /// хватает [notifyListeners].
  Stream<WeightSample> get samples => _samples.stream;

  String? connectedId;

  /// Заряд в процентах. Весы отдают его сами, время от времени; пока не
  /// прислали — null, и рисовать нечего.
  int? batteryPercent;

  String? lastError;

  /// Сколько кадров пришло с несошедшейся контрольной суммой.
  ///
  /// Драйвер, из которого взят протокол, на этой модели её не проверяет, так
  /// что до живых весов уверенности нет. Если счётчик пойдёт вровень с
  /// общим — значит железо считает сумму иначе, и это будет видно сразу, а не
  /// как загадочное молчание.
  int badCrc = 0;
  int framesSeen = 0;

  // ---- то, что показывают ------------------------------------------------

  double get grams => _flow.grams;
  double get flow => _flow.flow;
  bool get isSettled => _flow.isSettled;
  bool get isPouring => _flow.isPouring;
  FlowTracker get tracker => _flow;

  bool get isConnected => _session.state.isLinked;
  bool get isSeeking => _session.state.isSeeking;
  bool get isAsleep => _session.state == SessionState.dormant;

  /// Весы на связи и шлют отсчёты — только в этом состоянии их числу можно
  /// верить. Именно оно решает, показывать ли карточку веса и можно ли
  /// включать автостоп.
  bool get isLive => _session.state == SessionState.ready;

  SessionState get sessionState => _session.state;

  // ---- сеанс --------------------------------------------------------------

  late final Session _session = Session(onEnter: _onSession, log: _log);

  DateTime? _lastFrameAt;
  Timer? _silence;
  Timer? _reconnect;
  int _reconnectAttempt = 0;

  void _log(String s) => Trace.instance.log('весы: $s');

  void _onSession(SessionState from, SessionState to) {
    if (from.isLinked && !to.isLinked) _dropLinkState();
    switch (to) {
      case SessionState.handshaking:
        _reconnectAttempt = 0;
        unawaited(_handshake());
      case SessionState.ready:
        _reconnectAttempt = 0;
      case SessionState.reconnecting:
        _armReconnect();
      case SessionState.idle:
        _cancelReconnect();
        connectedId = null;
      case SessionState.connecting:
      case SessionState.dormant:
        break;
    }
    notifyListeners();
  }

  void _dropLinkState() {
    _flow.reset();
    _lastFrameAt = null;
    _silence?.cancel();
    _silence = null;
  }

  // ---- подключение --------------------------------------------------------

  Future<void> connect(String id) async {
    _cancelReconnect();
    lastError = null;
    connectedId = id;
    _session.fire(SessionEvent.connectRequested);
    try {
      await _transport.connect(id);
    } catch (e) {
      lastError = '$e';
      _session.fire(SessionEvent.connectFailed);
      notifyListeners();
      rethrow;
    }
  }

  Future<void> disconnect() async {
    // Сначала снять намерение, потом рвать: иначе обрыв, который мы же и
    // устроили, поднимет переподключение.
    _session.fire(SessionEvent.disconnectRequested);
    await _transport.disconnect();
  }

  void _armReconnect() {
    final id = connectedId;
    if (id == null || _reconnect != null) return;
    final wait = reconnectDelay(_reconnectAttempt);
    _log(
      'переподключение через ${wait.inSeconds} с '
      '(попытка ${_reconnectAttempt + 1})',
    );
    _reconnect = Timer(wait, () async {
      _reconnect = null;
      if (_session.state != SessionState.reconnecting) return;
      _reconnectAttempt++;
      _session.fire(SessionEvent.reconnectDue);
      try {
        await _transport.connect(id);
      } catch (e) {
        _log('переподключение не вышло: $e');
        _session.fire(SessionEvent.reconnectFailed);
      }
    });
  }

  void _cancelReconnect() {
    _reconnect?.cancel();
    _reconnect = null;
    _reconnectAttempt = 0;
  }

  void _onLink(LinkState s) {
    switch (s) {
      case LinkState.connected:
        _session.fire(SessionEvent.linkUp);
      case LinkState.disconnected:
        _session.fire(SessionEvent.linkDown);
      case LinkState.connecting:
        break;
    }
  }

  // ---- рукопожатие --------------------------------------------------------

  /// Две уставки, и обе обязательные.
  ///
  /// Единицы — потому что весы помнят их с прошлого раза: оставленные в
  /// унциях, они молча отдадут число втрое меньше, и весь счёт поедет.
  /// Режим — потому что в «рецепте» и «потоке» весы живут своей жизнью:
  /// сами тарируют, сами считают, и наш контур гоняется за чужим сценарием.
  Future<void> _handshake() async {
    final gen = _session.generation;
    await Future<void>.delayed(kScaleHandshakeDelay);
    if (gen != _session.generation) return;
    await _write(cmdScaleUnitGram());
    await Future<void>.delayed(kScaleWriteInterval);
    if (gen != _session.generation) return;
    await _write(cmdScaleStandardMode());
    _session.fire(SessionEvent.handshakeDone);
  }

  Future<void> _write(Uint8List frame) async {
    try {
      await _transport.write(frame);
    } catch (e) {
      _log('запись не прошла: $e');
    }
  }

  // ---- команды ------------------------------------------------------------

  Future<void> tare() async {
    // Обнуляем и у себя, не дожидаясь ответа: весы подтверждения не шлют, а
    // следующий отсчёт всё равно перезапишет. Зато крупная цифра на экране не
    // висит старым числом те доли секунды, пока кадр летит.
    _flow.reset();
    notifyListeners();
    await _write(cmdScaleTare());
  }

  Future<void> timer(ScaleTimerCommand c) => _write(cmdScaleTimer(c));

  // ---- приём --------------------------------------------------------------

  void _onNotify(Uint8List chunk) {
    final at = _now();
    final p = parseScaleFrame(chunk);
    if (p == null) {
      _log('чужой кадр: ${chunk.length} байт');
      return;
    }

    framesSeen++;
    if (!p.crcOk) {
      badCrc++;
      // Один битый кадр из потока в десять в секунду не стоит ни строчки в
      // трассе; систематическая беда видна по счётчику.
      if (badCrc == 1 || badCrc % 50 == 0) {
        _log('сумма не сошлась ($badCrc из $framesSeen)');
      }
      return;
    }

    _lastFrameAt = at;
    _armSilence();
    _session.fire(SessionEvent.telemetry);

    switch (p.frame) {
      case ScaleMeasurement(:final grams, :final extra):
        final s = WeightSample(at: at, grams: grams);
        _flow.add(s);
        _samples.add(s);
        _traceExtra(extra);
      case ScaleBattery(:final percent):
        batteryPercent = percent;
      case ScaleUnknown(:final opcode, :final cmdId):
        _log('непонятый кадр $opcode/$cmdId');
    }
    notifyListeners();
  }

  /// Хвост кадра измерения — те самые четыре байта, которые в драйвере-
  /// источнике названы «поток и время» и не разобраны. В трассу они попадают
  /// не каждый раз, а только когда меняются: иначе десять строк в секунду.
  String? _lastExtra;
  void _traceExtra(Uint8List extra) {
    if (extra.isEmpty) return;
    final hex = extra.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
    if (hex == _lastExtra) return;
    _lastExtra = hex;
    _log('хвост измерения: $hex');
  }

  /// Весы шлют отсчёты сами и часто. Замолчали — значит уснули по своему
  /// таймауту: линия при этом остаётся, и будить их бесполезно, только ждать.
  void _armSilence() {
    _silence?.cancel();
    _silence = Timer(kScaleSilence, () {
      _session.fire(SessionEvent.silenceElapsed);
    });
  }

  /// Когда пришёл последний кадр. Нужно тому, кто решает, можно ли доверять
  /// весу прямо сейчас.
  DateTime? get lastFrameAt => _lastFrameAt;

  @override
  void dispose() {
    _silence?.cancel();
    _reconnect?.cancel();
    unawaited(_linkSub.cancel());
    unawaited(_notifySub.cancel());
    unawaited(_samples.close());
    unawaited(_transport.dispose());
    super.dispose();
  }
}
