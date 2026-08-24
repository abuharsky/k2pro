import 'package:flutter_test/flutter_test.dart';
import 'package:k2pro/ble/session.dart';

/// Таблица переходов сеанса — отдельно от устройства.
///
/// Смысл этих тестов в том, чтобы запрещённые переходы были видны как факт, а
/// не как побочный эффект того, что нужный `if` где-то не сработал. Каждый
/// случай ниже был живой поломкой на машине.
void main() {
  /// Прогнать список событий и вернуть, где сеанс оказался.
  Session run(List<SessionEvent> events, {List<String>? trace}) {
    final s = Session(onEnter: (from, to) => trace?.add(to.name));
    for (final e in events) {
      s.fire(e);
    }
    return s;
  }

  test('обычный путь: подключились, поговорили, работаем', () {
    final trace = <String>[];
    final s = run([
      SessionEvent.connectRequested,
      SessionEvent.linkUp,
      SessionEvent.handshakeDone,
    ], trace: trace);
    expect(s.state, SessionState.ready);
    expect(trace, ['connecting', 'handshaking', 'ready']);
  });

  test('машина спит: пробный кадр без ответа уводит в дрёму', () {
    final s = run([
      SessionEvent.connectRequested,
      SessionEvent.linkUp,
      SessionEvent.probeSilent,
    ]);
    expect(s.state, SessionState.dormant);
    expect(s.state.isLinked, isTrue, reason: 'связь-то есть, молчит машина');
  });

  test('проснувшаяся машина сама возвращает опрос', () {
    final s = run([
      SessionEvent.connectRequested,
      SessionEvent.linkUp,
      SessionEvent.probeSilent,
      SessionEvent.telemetry,
    ]);
    expect(s.state, SessionState.handshaking);
  });

  test('молчание в работе — это дрёма, а не обрыв', () {
    final s = run([
      SessionEvent.connectRequested,
      SessionEvent.linkUp,
      SessionEvent.handshakeDone,
      SessionEvent.silenceElapsed,
    ]);
    expect(s.state, SessionState.dormant);
  });

  test('мигание транспорта на подключении не роняет в переподключение', () {
    // В живой трассе `link connecting` и `link disconnected` пришли с разницей
    // в две миллисекунды — и сразу после этого связь встала. Старый код успевал
    // на этом моргании завести таймер переподключения.
    final trace = <String>[];
    final s = run([
      SessionEvent.connectRequested,
      SessionEvent.linkDown,
    ], trace: trace);
    expect(s.state, SessionState.connecting);
    expect(trace, ['connecting'], reason: 'второго перехода не было');
  });

  test('обрыв на связи ведёт в переподключение и по кругу', () {
    final s = run([
      SessionEvent.connectRequested,
      SessionEvent.linkUp,
      SessionEvent.handshakeDone,
      SessionEvent.linkDown,
    ]);
    expect(s.state, SessionState.reconnecting);
    s.fire(SessionEvent.reconnectDue);
    expect(s.state, SessionState.connecting);
    s.fire(SessionEvent.linkUp);
    expect(s.state, SessionState.handshaking);
  });

  test('неудачная попытка переподключиться возвращает в ожидание', () {
    final s = run([
      SessionEvent.connectRequested,
      SessionEvent.linkUp,
      SessionEvent.linkDown,
      SessionEvent.reconnectDue,
      SessionEvent.reconnectFailed,
    ]);
    expect(s.state, SessionState.reconnecting);
  });

  test('отказ при подключении по кнопке — это покой, а не переподключение', () {
    // Разница с reconnectFailed: там машину унесли и мы её ждём, здесь человек
    // нажал и получил отказ — доложить и остановиться.
    final s = run([SessionEvent.connectRequested, SessionEvent.connectFailed]);
    expect(s.state, SessionState.idle);
  });

  test('отключение по нашей воле обрывает любое состояние', () {
    for (final path in [
      [SessionEvent.connectRequested],
      [SessionEvent.connectRequested, SessionEvent.linkUp],
      [
        SessionEvent.connectRequested,
        SessionEvent.linkUp,
        SessionEvent.handshakeDone,
      ],
      [
        SessionEvent.connectRequested,
        SessionEvent.linkUp,
        SessionEvent.probeSilent,
      ],
    ]) {
      final s = run([...path, SessionEvent.disconnectRequested]);
      expect(s.state, SessionState.idle, reason: '$path');
    }
  });

  test('в покое лишние события ничего не делают', () {
    for (final e in SessionEvent.values) {
      if (e == SessionEvent.connectRequested) continue;
      final s = run([e]);
      expect(s.state, SessionState.idle, reason: e.name);
    }
  });

  test('поколение растёт только на событиях, обесценивающих запросы', () {
    // Ответ, пришедший после обрыва, относится к прошлой жизни линии. Поколение
    // — то, чем ждущий запрос это отличает.
    final s = Session(onEnter: (_, _) {});
    final before = s.generation;
    s.fire(SessionEvent.connectRequested);
    s.fire(SessionEvent.linkUp);
    final linked = s.generation;
    expect(linked, greaterThan(before));

    s.fire(SessionEvent.handshakeDone);
    s.fire(SessionEvent.silenceElapsed);
    s.fire(SessionEvent.telemetry);
    expect(
      s.generation,
      linked,
      reason: 'сон и пробуждение линию не рвут — запросы остаются в силе',
    );

    s.fire(SessionEvent.linkDown);
    expect(s.generation, greaterThan(linked));
  });

  test('запрещённое событие поколение всё равно обнуляет доверие', () {
    // linkDown в connecting состояние не меняет, но линия при этом моргнула —
    // всё, что было отправлено до, ответа уже не дождётся.
    final s = Session(onEnter: (_, _) {});
    s.fire(SessionEvent.connectRequested);
    final g = s.generation;
    expect(s.fire(SessionEvent.linkDown), isFalse, reason: 'перехода нет');
    expect(s.generation, greaterThan(g), reason: 'а доверия к ответам — тоже');
  });
}
