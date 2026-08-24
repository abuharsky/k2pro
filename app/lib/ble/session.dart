/// Состояние сеанса связи с машиной — одно на всё приложение.
///
/// До этого состояние сеанса было размазано по дюжине независимых полей:
/// `link`, `connectedId`, таймер переподключения с его счётчиком попыток,
/// номер связи, флаг «опрос прошёл», флаг «спит», отметки времени. Ничто не
/// мешало им сложиться в комбинацию, которой в жизни не бывает, и именно из
/// таких комбинаций выросли живые поломки: подключённая машина, для которой
/// опрос не начинался и не был запланирован; обрыв, после которого никто не
/// переподключался; два рукопожатия в одной очереди.
///
/// Здесь состояний шесть, и переход между ними один — [Session.fire].
library;

/// Где сейчас сеанс.
enum SessionState {
  /// Подключаться не к чему и незачем: человек не выбирал машину или отключился
  /// сам.
  idle,

  /// Соединяемся. Линии ещё нет.
  connecting,

  /// Линия есть, идёт опрос. Экран уже показывает машину подключённой:
  /// телеметрию она шлёт сама, не дожидаясь конца опроса.
  handshaking,

  /// Опрос прошёл, машина отвечает и шлёт телеметрию.
  ready,

  /// Линия есть, машина молчит — спит. Кадры она принимает и глотает, так что
  /// опрашивать её бесполезно: ждём, пока заговорит сама.
  dormant,

  /// Связь оборвалась не по нашей воле. Ждём паузу перед следующей попыткой.
  reconnecting;

  /// Линия установлена: команды уйдут, телеметрия может идти.
  bool get isLinked =>
      this == handshaking || this == ready || this == dormant;

  /// Связи нет, но мы её добиваемся.
  bool get isSeeking => this == connecting || this == reconnecting;
}

/// Что случилось.
enum SessionEvent {
  /// Человек выбрал машину.
  connectRequested,

  /// Транспорт не смог соединиться.
  connectFailed,

  /// Человек отключился сам.
  disconnectRequested,

  /// Транспорт сообщил, что линия поднялась.
  linkUp,

  /// Транспорт сообщил, что линия упала.
  linkDown,

  /// Машина не ответила на пробный кадр опроса.
  probeSilent,

  /// Опрос прошёл целиком.
  handshakeDone,

  /// Пришёл кадр телеметрии.
  telemetry,

  /// Телеметрии нет дольше отведённого.
  silenceElapsed,

  /// Пауза перед следующей попыткой вышла.
  reconnectDue,

  /// Попытка переподключиться не удалась.
  reconnectFailed,
}

/// Куда ведёт событие. null — в этом состоянии событие ничего не значит.
///
/// Таблица целиком, без исключений где-либо ещё: если перехода здесь нет, его
/// нет вообще.
SessionState? nextSessionState(SessionState s, SessionEvent e) => switch (e) {
  // Человек главнее всего: отключение и выбор машины проходят из любого места.
  SessionEvent.disconnectRequested =>
    s == SessionState.idle ? null : SessionState.idle,
  SessionEvent.connectRequested => SessionState.connecting,
  SessionEvent.connectFailed =>
    s == SessionState.connecting ? SessionState.idle : null,

  SessionEvent.linkUp => s.isSeeking ? SessionState.handshaking : null,

  // Пока соединяемся, транспорт успевает мигнуть «оборвано»: в живой трассе
  // между `link connecting` и `link disconnected` проходило две миллисекунды,
  // после чего связь поднималась как ни в чём не бывало. Раньше на этот блик
  // заводилось переподключение — и дальше две попытки соединиться шли
  // навстречу друг другу.
  SessionEvent.linkDown =>
    s.isLinked ? SessionState.reconnecting : null,

  SessionEvent.probeSilent =>
    s == SessionState.handshaking ? SessionState.dormant : null,
  SessionEvent.handshakeDone =>
    s == SessionState.handshaking ? SessionState.ready : null,

  // Заговорила — значит, проснулась, и опрос имеет смысл начать заново: пока
  // она спала, у нас не было ни диапазонов, ни версии, ни счётчиков.
  SessionEvent.telemetry =>
    s == SessionState.dormant ? SessionState.handshaking : null,
  SessionEvent.silenceElapsed =>
    s == SessionState.ready ? SessionState.dormant : null,

  SessionEvent.reconnectDue =>
    s == SessionState.reconnecting ? SessionState.connecting : null,

  // Не вышло — обратно в ожидание, следующая пауза будет длиннее. Это не то же
  // самое, что connectFailed: там человек нажал и получил отказ, здесь машину
  // просто ещё не донесли обратно, и бросать её мы не собираемся.
  SessionEvent.reconnectFailed =>
    s == SessionState.connecting ? SessionState.reconnecting : null,
};

/// События, после которых прежняя линия недействительна: заведённые в ней
/// запросы машина уже не помнит, а очередь они держат.
const Set<SessionEvent> _invalidating = {
  SessionEvent.connectRequested,
  SessionEvent.connectFailed,
  SessionEvent.disconnectRequested,
  SessionEvent.linkUp,
  SessionEvent.linkDown,
  SessionEvent.reconnectFailed,
};

/// Сеанс: состояние плюс номер текущей линии.
class Session {
  Session({required this.onEnter, this.log});

  /// Побочные действия перехода. Вызывается уже с новым [state].
  final void Function(SessionState from, SessionState to) onEnter;

  final void Function(String)? log;

  SessionState _state = SessionState.idle;

  /// Меняется только через [fire] — иначе таблица переходов перестаёт быть
  /// единственным местом, где написано, что за чем следует.
  SessionState get state => _state;

  /// Номер текущей линии. Растёт на каждом событии, после которого прежние
  /// запросы теряют смысл.
  int generation = 0;

  /// Провести событие. true — состояние изменилось.
  bool fire(SessionEvent e) {
    final to = nextSessionState(state, e);
    if (_invalidating.contains(e)) generation++;
    if (to == null || to == state) return false;
    final from = _state;
    _state = to;
    log?.call('сеанс ${from.name} --${e.name}--> ${to.name}');
    onEnter(from, to);
    return true;
  }
}
