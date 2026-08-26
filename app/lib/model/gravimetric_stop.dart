/// Останов пролива по весу.
///
/// У машины ровно один орган управления — «стоп», и уставок на ходу она не
/// принимает. Значит это не регулятор, а один точный выстрел: надо угадать
/// момент, когда дёрнуть, потому что между «весы показали цель» и «в чашке
/// перестало прибывать» стоят четыре задержки.
///
/// Три из них — время: весы → телефон (кадры идут около десяти раз в секунду),
/// телефон → машина (по живой трассе медиана 89 мс, p95 209 мс) и собственно
/// закрытие клапана. Их вклад в массу равен `поток × [kStopLead]`.
///
/// Четвёртая — дотёк: то, что уже в корзине, стечёт независимо ни от чего.
/// От потока он почти не зависит, зато зависит от корзины и помола, поэтому
/// [GravimetricStop.drip] у каждого рецепта свой и учится сам после каждого
/// пролива — ровно так же, как это делает человек: снял, посмотрел, сколько
/// натекло сверх, в следующий раз снял пораньше.
library;

import 'flow_tracker.dart';

/// Суммарное запаздывание контура. Это про технику связи, а не про кофе, так
/// что величина общая для всех рецептов и руками не правится.
const Duration kStopLead = Duration(milliseconds: 400);

/// С чего начинается дотёк, пока не выучен свой.
const double kSeedDrip = 0.6;

/// Насколько сильно новый пролив двигает поправку. Треть — три-четыре пролива
/// до попадания и заметная устойчивость к одному кривому.
const double kDripAlpha = 0.3;

/// Потолок поправки. Больше — это уже не дотёк, а поломка счёта.
const double kDripMax = 5;

/// Столько после спуска ждём, пока вес устоится, прежде чем считать итог.
const Duration kSettleTimeout = Duration(seconds: 12);

/// Пауза после толчка, в которую спуск не взводится: окно потока только что
/// разорвалось, и предсказывать по нему нечего.
const Duration kBumpBlackout = Duration(milliseconds: 600);

/// Чем кончился пролив.
enum StopReason {
  /// Как задумано: спуск дал контур.
  weight,

  /// Раньше веса кончились секунды машины. Это промах, и учиться на нём
  /// нельзя: мы не знаем, где был бы настоящий момент останова.
  timeout,

  /// Остановил человек.
  manual,

  /// Связь с машиной или с весами пропала посреди пролива.
  linkLost,
}

/// Итог пролива — то, из чего учится поправка и то, что показывается человеку.
class ShotResult {
  const ShotResult({
    required this.reason,
    required this.target,
    required this.triggerGrams,
    required this.triggerFlow,
    required this.finalGrams,
    required this.elapsed,
  });

  final StopReason reason;
  final double target;

  /// Вес в момент, когда ушла команда останова.
  final double triggerGrams;

  /// Поток в тот же момент — по нему разделяется временная часть перелёта и
  /// собственно дотёк.
  final double triggerFlow;

  /// Вес после осадки.
  final double finalGrams;

  final Duration elapsed;

  /// Сколько натекло после команды.
  double get overshoot => finalGrams - triggerGrams;

  /// Промах относительно цели: плюс — перелили.
  double get miss => finalGrams - target;
}

/// Новая поправка на дотёк — или null, если на этом проливе учиться нельзя.
///
/// Из перелёта вычитается временная часть (`поток × упреждение`), остаток и
/// есть дотёк. Дальше — экспоненциальное сглаживание: один кривой пролив не
/// должен ломать накопленное.
double? learnedDrip({
  required double drip,
  required ShotResult shot,
  Duration lead = kStopLead,
}) {
  if (shot.reason != StopReason.weight) return null;

  final over = shot.overshoot;
  // Отрицательный перелёт означает, что с весов что-то сняли; десять граммов
  // сверх — что мы смотрим не на тот пролив. И то и другое не дотёк.
  if (over < 0 || over > 10) return null;

  final residual = over - shot.triggerFlow * (lead.inMilliseconds / 1000);
  final next = drip + kDripAlpha * (residual - drip);
  return next.clamp(0.0, kDripMax);
}

/// Контур останова на один пролив. Живёт от пуска до итога, второй раз не
/// взводится.
class GravimetricStop {
  GravimetricStop({
    required this.target,
    required this.drip,
    this.lead = kStopLead,
  });

  /// Цель по весу, граммы.
  final double target;

  /// Выученный дотёк этого рецепта.
  final double drip;

  final Duration lead;

  /// Пролив действительно пошёл — до этого спуск не взводится, иначе задетая
  /// чашка останавливает машину.
  bool _armed = false;

  bool _fired = false;
  double _triggerGrams = 0;
  double _triggerFlow = 0;

  bool get isArmed => _armed;
  bool get hasFired => _fired;
  double get triggerGrams => _triggerGrams;
  double get triggerFlow => _triggerFlow;

  double get _leadSeconds => lead.inMilliseconds / 1000;

  /// На каком весе надо дать стоп при нынешнем потоке. Ровно это число и
  /// показывается человеку, когда он хочет понять, почему машина встала
  /// раньше цели.
  double stopAt(double flow) => target - flow * _leadSeconds - drip;

  /// Провести отсчёт. true — прямо сейчас слать останов.
  ///
  /// Отсчёт должен быть уже добавлен в [f]: контур смотрит на сглаженный
  /// поток, а не на разницу двух соседних чисел.
  bool onSample(WeightSample s, FlowTracker f) {
    if (_fired || target <= 0) return false;

    // Толчок разорвал окно потока: пока оно не набралось заново, предсказывать
    // не по чему, а вес после толчка может оказаться выше цели сам по себе.
    final bump = f.lastBumpAt;
    if (bump != null && s.at.difference(bump) < kBumpBlackout) return false;

    if (!_armed) {
      if (!f.isPouring) return false;
      _armed = true;
    }

    if (f.grams + f.flow * _leadSeconds + drip < target) return false;

    _fired = true;
    _triggerGrams = f.grams;
    _triggerFlow = f.flow;
    return true;
  }

  /// Собрать итог. [finalGrams] — вес после осадки.
  ///
  /// Если спуск не срабатывал (кончилось время, остановил человек, пропала
  /// связь), за момент спуска берётся тот же итог: перелёта не было, учиться
  /// всё равно нечему — [learnedDrip] такой пролив отбросит по причине.
  ShotResult finish({
    required StopReason reason,
    required double finalGrams,
    required Duration elapsed,
  }) => ShotResult(
    reason: reason,
    target: target,
    triggerGrams: _fired ? _triggerGrams : finalGrams,
    triggerFlow: _fired ? _triggerFlow : 0,
    finalGrams: finalGrams,
    elapsed: elapsed,
  );
}
