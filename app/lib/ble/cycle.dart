/// Состояние цикла заваривания — одно на телефон и на часы.
///
/// До этого цикл жил в двух местах сразу и в обоих одинаково: `_awaitingBusy` с
/// восьмисекундным таймаутом и `_doneBadge`/`_doneSeen` с трёхсекундным — в
/// [_HomePageState], и ровно они же, отдельной копией, в мосту к часам. Экран и
/// часы могли разойтись, а третий зритель — трасса — не видел ни того, ни
/// другого: в логе оставались кадры, но не то, чем приложение их считало.
///
/// Здесь состояний шесть, и переход между ними один — [Cycle.fire].
library;

import 'dart:async';

/// Где сейчас цикл.
enum CycleState {
  /// Машина в покое, пуск доступен.
  idle,

  /// Кадр пуска ушёл, машина ещё не отчиталась. На кнопке ожидание: иначе тап
  /// выглядит потерянным — между командой и первой «занятой» телеметрией
  /// проходит до секунды.
  starting,

  /// Машина работает. Подробности — какая именно фаза и сколько её прошло —
  /// считает `BrewPhaseEstimator`: состояния машины грубее, чем нужно экрану.
  running,

  /// Кадр останова ушёл, машина ещё не отчиталась.
  stopping,

  /// Машина отчиталась «готово». Это итог цикла, а не состояние покоя: сама
  /// машина держит «готово» до следующей команды, а зелёная кнопка живёт
  /// отведённые ей секунды и уступает место обычному пуску.
  finished,

  /// Цикл оборвала ошибка. Отличать от [idle] нужно затем, что вернуться в
  /// покой молча — значит потерять единственный признак: код ошибки живёт в
  /// телеметрии один пакет.
  faulted;

  /// Команда ушла, подтверждения нет: на кнопке ожидание.
  bool get isPending => this == starting || this == stopping;

  /// Цикл идёт — машина занята или вот-вот будет.
  bool get isActive =>
      this == starting || this == running || this == stopping;
}

/// Что случилось.
enum CycleEvent {
  /// Человек пустил машину.
  startRequested,

  /// Человек остановил машину.
  stopRequested,

  /// Телеметрия сменилась на рабочее состояние.
  machineBusy,

  /// Телеметрия сменилась на состояние покоя.
  machineIdle,

  /// Телеметрия сменилась на «готово».
  machineDone,

  /// В телеметрии пришёл код ошибки.
  machineFault,

  /// Машина не подтвердила команду за отведённое время.
  confirmTimeout,

  /// Зелёное «готово» отвисело своё.
  badgeElapsed,

  /// Человек прочитал ошибку.
  faultCleared,

  /// Связь пропала — про машину мы больше ничего не знаем.
  linkLost,
}

/// Сколько ждать подтверждения команды. Живая машина отзывается за долю
/// секунды; восемь — это уже «кадр потерялся», и вечный спиннер был бы хуже
/// просто неотработавшей кнопки.
const Duration kConfirmTimeout = Duration(seconds: 8);

/// Сколько висит зелёное «готово».
const Duration kDoneBadge = Duration(seconds: 3);

/// Куда ведёт событие. null — в этом состоянии событие ничего не значит.
///
/// Таблица целиком, без исключений где-либо ещё.
CycleState? nextCycleState(CycleState s, CycleEvent e) => switch (e) {
  // Связь главнее всего: без неё про машину не известно ничего.
  CycleEvent.linkLost => s == CycleState.idle ? null : CycleState.idle,

  // Пустить можно только из покоя. Повторный тап по идущему циклу — не запуск.
  CycleEvent.startRequested => s.isActive ? null : CycleState.starting,

  // Остановить — то, что уже идёт или вот-вот пойдёт: команда пуска могла и
  // потеряться, но человек, нажавший стоп, хочет стоп, а не отмену ожидания.
  CycleEvent.stopRequested =>
    s == CycleState.starting || s == CycleState.running
        ? CycleState.stopping
        : null,

  // Машина заработала. Из stopping — нет: она ещё не услышала стоп, ждём.
  CycleEvent.machineBusy =>
    s == CycleState.running || s == CycleState.stopping
        ? null
        : CycleState.running,

  // Машина встала. В starting это не ответ на нашу команду, а прошлое: кадр
  // пуска ещё в пути.
  CycleEvent.machineIdle =>
    s == CycleState.running || s == CycleState.stopping
        ? CycleState.idle
        : null,

  // «Готово» имеет смысл только как итог цикла, который мы вели.
  CycleEvent.machineDone => s.isActive ? CycleState.finished : null,

  // Ошибка обрывает цикл. В покое её показывает баннер, а обрывать нечего.
  CycleEvent.machineFault => s.isActive ? CycleState.faulted : null,

  // Не подтвердила. После пуска считаем, что не запустилась; после
  // останова — что всё ещё работает: это безопаснее в обе стороны.
  CycleEvent.confirmTimeout => switch (s) {
    CycleState.starting => CycleState.idle,
    CycleState.stopping => CycleState.running,
    _ => null,
  },

  CycleEvent.badgeElapsed => s == CycleState.finished ? CycleState.idle : null,
  CycleEvent.faultCleared => s == CycleState.faulted ? CycleState.idle : null,
};

/// Цикл: состояние плюс два таймера, которые из него же и заводятся.
class Cycle {
  Cycle({required this.onEnter, this.log});

  /// Побочные действия перехода. Вызывается уже с новым [state].
  final void Function(CycleState from, CycleState to) onEnter;

  final void Function(String)? log;

  CycleState _state = CycleState.idle;

  /// Меняется только через [fire].
  CycleState get state => _state;

  Timer? _timer;

  /// Провести событие. true — состояние изменилось.
  bool fire(CycleEvent e) {
    final to = nextCycleState(_state, e);
    if (to == null || to == _state) return false;
    final from = _state;
    _state = to;
    log?.call('цикл ${from.name} --${e.name}--> ${to.name}');

    _timer?.cancel();
    _timer = switch (to) {
      CycleState.starting || CycleState.stopping => Timer(
        kConfirmTimeout,
        () => fire(CycleEvent.confirmTimeout),
      ),
      CycleState.finished => Timer(
        kDoneBadge,
        () => fire(CycleEvent.badgeElapsed),
      ),
      _ => null,
    };

    onEnter(from, to);
    return true;
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
