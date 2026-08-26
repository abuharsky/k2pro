/// Симулятор весов: позволяет строить и проверять весь контур на Mac, без
/// железа. Отвечает настоящими кадрами протокола DOT, поэтому проверяет и
/// кодек, и счёт потока, и упреждение останова.
///
/// Главное здесь — не вес, а инерция. Вода, которую машина уже налила, попадает
/// на весы не сразу: она сначала оказывается в корзине и стекает оттуда с
/// задержкой. Ровно из этой задержки и рождается дотёк, ради которого весь
/// контур и затевался, — так что симулятор без неё был бы бесполезен.
library;

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import '../transport.dart';
import 'timemore_dot.dart';

/// Идентификатор весов-симулятора. Демо-режим подключается прямо к нему,
/// минуя поиск.
const String kMockScaleId = 'mock-dot';

class MockScaleTransport implements K2Transport {
  MockScaleTransport({this.pourFlow});

  /// Сколько машина льёт прямо сейчас, г/с. Обычно это `MockTransport.pourFlow`.
  final double Function()? pourFlow;

  final _scanCtl = StreamController<List<DiscoveredDevice>>.broadcast();
  final _linkCtl = StreamController<LinkState>.broadcast();
  final _notifyCtl = StreamController<Uint8List>.broadcast();

  LinkState _link = LinkState.disconnected;
  Timer? _tick;

  final _rnd = Random(42);

  /// Что уже на весах.
  double _grams = 0;

  /// Что налито, но ещё не стекло. Из этого и получается дотёк.
  double _inPuck = 0;

  /// Смещение тары.
  double _zero = 0;

  int _battery = 78;
  int _sinceBattery = 0;

  /// Постоянная стекания. При потоке 2 г/с в корзине висит около грамма —
  /// столько и натечёт после останова.
  static const double _tau = 0.5;

  /// Весы шлют десять кадров в секунду.
  static const Duration _period = Duration(milliseconds: 100);

  /// Всё, что приложение записало в весы.
  final List<Uint8List> sent = [];

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

  /// Поиск ведёт транспорт машины — весы в нём только находятся.
  @override
  Future<void> startScan({
    Duration timeout = const Duration(seconds: 15),
    bool showAll = false,
  }) async {}

  @override
  Future<void> stopScan() async {}

  @override
  Future<void> connect(String deviceId) async {
    _setLink(LinkState.connecting);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    _setLink(LinkState.connected);
    _tick?.cancel();
    _tick = Timer.periodic(_period, (_) => _step());
  }

  @override
  Future<void> disconnect() async {
    _tick?.cancel();
    _tick = null;
    _setLink(LinkState.disconnected);
  }

  /// Положить что-нибудь на весы: зерно, чашку. Для ручных проверок режима
  /// взвешивания.
  void put(double grams) => _grams += grams;

  @override
  Future<void> write(Uint8List frame) async {
    sent.add(Uint8List.fromList(frame));
    final p = parseScaleFrame(frame);
    if (p == null || !p.crcOk) return;
    if (p.frame case ScaleUnknown(:final cmdId)) {
      if (cmdId == ScaleCmd.tare) _zero = _grams;
    }
  }

  void _step() {
    final dt = _period.inMilliseconds / 1000;
    final f = pourFlow?.call() ?? 0;

    // Налитое сначала попадает в корзину, оттуда стекает с задержкой.
    _inPuck += f * dt;
    final drained = _inPuck * (dt / _tau);
    _inPuck -= drained;
    _grams += drained;

    // Шум весов: не больше половины деления, иначе счёт потока становится
    // неправдоподобно чистым.
    final shown = _grams - _zero + (_rnd.nextDouble() - 0.5) * 0.08;
    _send(cmdId: ScaleCmd.measure, data: _measurement(shown));

    if (++_sinceBattery >= 50) {
      _sinceBattery = 0;
      _send(cmdId: ScaleCmd.battery, data: [0x00, _battery]);
      if (_rnd.nextInt(20) == 0 && _battery > 0) _battery--;
    }
  }

  List<int> _measurement(double grams) {
    final raw = (grams * 10).round().toSigned(32) & 0xFFFFFFFF;
    return [
      (raw >> 24) & 0xFF,
      (raw >> 16) & 0xFF,
      (raw >> 8) & 0xFF,
      raw & 0xFF,
      // Хвост, который мы ещё не опознали. Симулятор кладёт туда поток в
      // десятых грамма в секунду — догадку, а не факт: на живых весах его
      // предстоит проверить.
      0x00,
      ((pourFlow?.call() ?? 0) * 10).round().clamp(0, 255),
      0x00,
      0x00,
    ];
  }

  void _send({required int cmdId, required List<int> data}) {
    _notifyCtl.add(buildScaleFrame(ScaleOp.push, cmdId, data));
  }

  @override
  Future<void> dispose() async {
    _tick?.cancel();
    await _scanCtl.close();
    await _linkCtl.close();
    await _notifyCtl.close();
  }
}
