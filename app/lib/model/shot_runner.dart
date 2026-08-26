/// Ведение пролива: от пуска до записи в журнал.
///
/// Единственное место, где сходятся машина, весы и контур останова. Экран
/// сюда только смотрит: решение «пора стоп» принимается по отсчёту весов, а
/// не по кадру интерфейса, и приходить оно должно одинаково — нажали пуск на
/// телефоне или на часах.
///
/// Ведётся каждый пролив, а не только взвешенный: сколько лилось и при какой
/// температуре — это про машину, и в журнал попадает всегда. Весы добавляют к
/// записи вес и промах, но их отсутствие не повод ничего не помнить.
///
/// Порядок такой: пуск → тара весов → ждём, пока пойдёт вода → спуск с
/// упреждением → осадка → итог. Осадка здесь не украшение: пока вес доползает,
/// пролив ещё не кончился, и именно из этих секунд учится поправка на дотёк.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../ble/cycle.dart';
import '../ble/k2_device.dart';
import '../ble/protocol.dart';
import '../ble/scale/scale_device.dart';
import '../ble/scale/timemore_dot.dart';
import '../ble/trace.dart';
import '../store/prefs.dart';
import 'flow_tracker.dart';
import '../store/shot_store.dart';
import 'gravimetric_stop.dart';
import 'gravimetry.dart';
import 'shot_curve.dart';

/// Где сейчас пролив с точки зрения весов.
enum ShotPhase {
  /// Ничего не идёт.
  idle,

  /// Цикл начался, вода ещё не пошла: греется или смачивает.
  waiting,

  /// Вода идёт, вес растёт.
  pouring,

  /// Команда останова ушла, вес доползает. Единственная живая цифра на
  /// экране в этот момент.
  settling,

  /// Итог посчитан и показан.
  done,
}

class ShotRunner extends ChangeNotifier {
  ShotRunner({
    required this.device,
    required this.scale,
    required this.prefs,
    ShotStore? store,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now,
       _store = store ?? ShotStore() {
    device.addListener(_onDevice);
    _samples = scale.samples.listen(_onSample);
    _sawCycle = device.cycleState;
  }

  final K2Device device;
  final ScaleDevice scale;
  final Prefs prefs;
  final ShotStore _store;
  final DateTime Function() _now;

  late final StreamSubscription<WeightSample> _samples;

  ShotPhase phase = ShotPhase.idle;

  /// Итог последнего пролива. Держится до следующего пуска: цифру после
  /// осадки человек читает уже неспешно.
  ShotRecord? lastShot;

  /// Кривая последнего пролива — та самая, что уехала в файл. Держим её и в
  /// памяти: так видно, что собралось, не читая диск.
  ShotCurve? lastCurve;

  GravimetricStop? _stop;
  CycleState _sawCycle = CycleState.idle;
  DateTime? _startedAt;

  /// Когда ушла команда останова. Осадку отмеряем от неё, а не от начала
  /// пролива: сам пролив идёт полминуты, и таймаут осадки сгорел бы ещё до
  /// того, как в чашку упала первая капля дотёка.
  DateTime? _settleFrom;

  Timer? _settleTimer;

  /// Копит кривую по ходу пролива. null — пролив идёт без весов, рисовать
  /// нечего.
  CurveRecorder? _curve;

  /// Почему пролив кончился. Ставится в момент, когда решение принято, а не
  /// когда машина отчиталась: по одному только отчёту «наш стоп» от «своего
  /// таймаута» не отличить.
  StopReason? _reason;

  /// Машина в этом цикле действительно лила. Один нагрев проливом не считаем:
  /// в журнале ему делать нечего.
  bool _sawPour = false;

  /// Уставка температуры на момент пуска. Записываем её, а не текущую: цикл
  /// длинный, и «при какой температуре лилось» — это про заданное.
  int _temperature = 0;

  void _log(String s) => Trace.instance.log('пролив: $s');

  // ---- то, что показывают ------------------------------------------------

  Gravimetry get plan => prefs.gravimetry;

  /// Цель по весу — если она вообще имеет смысл прямо сейчас.
  double get target => plan.targetG;

  double get grams => scale.grams;

  /// Сколько цели набрано, 0..1. Это кольцо и переезжает с карточки пролива
  /// на карточку веса, когда автостоп включён.
  double get fraction => target <= 0 ? 0 : (grams / target).clamp(0.0, 1.0);

  /// Пролив ведётся: весы на связи и цикл идёт.
  bool get isRunning => phase != ShotPhase.idle && phase != ShotPhase.done;

  /// Контур взведён и ждёт своего момента.
  bool get isArmed => _stop?.isArmed ?? false;

  /// Автостоп имеет смысл: весы живые и человек его включил.
  bool get autoStopReady => scale.isLive && plan.stopOnYield;

  // ---- ход цикла ----------------------------------------------------------

  void _onDevice() {
    // Считаем до раннего выхода: машина переходит из нагрева в пролив, не
    // меняя состояния цикла, — тот всё это время просто «идёт». Ниже мы
    // выходим на каждом кадре телеметрии, и признак пролива успел бы
    // обновиться только случайно, на последнем переходе.
    _sawPour |= switch (device.status?.state) {
      MachineState.brewing ||
      MachineState.heatBrewing ||
      MachineState.brewDone ||
      MachineState.heatBrewDone => isRunning,
      _ => false,
    };

    // Температура приходит своим темпом, раз в секунду, и к смене состояния
    // цикла отношения не имеет — забираем её здесь же.
    final t = device.status?.temperatureC;
    if (t != null) _curve?.addTemperature(_now(), t);

    final c = device.cycleState;
    if (c == _sawCycle) return;
    final was = _sawCycle;
    _sawCycle = c;

    // Пуск.
    if (!was.isActive && c.isActive) {
      // Итог прошлого пролива висит, пока его не закрыли, — но ждать этого
      // новый пролив не должен. Пока ждал, не уходила тара, и вес следующей
      // чашки считался от чужого нуля: два пролива подряд давали под триста
      // граммов вместо полутора сотен.
      if (phase == ShotPhase.done) _reset();
      if (phase == ShotPhase.idle) {
        _begin();
        return;
      }
    }

    if (!isRunning) return;

    // Останов пошёл не от нас — значит его дал человек.
    if (c == CycleState.stopping && _reason == null) {
      _reason = StopReason.manual;
      _log('остановил человек');
    }

    // Цикл кончился. Своим таймаутом, если мы не успели дать стоп.
    if (was.isActive && !c.isActive) {
      _reason ??= device.isConnected ? StopReason.timeout : StopReason.linkLost;
      _settle();
    }
  }

  void _begin() {
    _reason = null;
    _sawPour = false;
    _startedAt = _now();
    _temperature = prefs.recipe.temperatureC;
    phase = ShotPhase.waiting;
    lastShot = null;
    lastCurve = null;

    // Контур заводим только с живыми весами. Без них пролив всё равно ведём —
    // ради журнала, — но рубить его нечем.
    if (!scale.isLive) {
      _stop = null;
      _curve = null;
      _log('пуск без весов, пишем только время');
      notifyListeners();
      return;
    }

    _curve = CurveRecorder(startedAt: _startedAt!);
    _stop = GravimetricStop(target: plan.targetG, drip: plan.drip);
    _log(
      'пуск, цель ${plan.targetG} г, поправка ${plan.drip.toStringAsFixed(2)} г',
    );
    // Тарируем сразу: чашка уже стоит, а тарить руками перед каждым проливом —
    // ровно тот шаг, который автоматика и должна убрать.
    unawaited(scale.tare());
    unawaited(scale.timer(ScaleTimerCommand.reset));
    unawaited(scale.timer(ScaleTimerCommand.start));
    notifyListeners();
  }

  void _onSample(WeightSample s) {
    if (!isRunning) return;

    // Весы пропали посреди пролива — контур больше не наш. Цикл при этом
    // продолжается: машина доработает по времени, и это лучше, чем встать
    // посреди чашки.
    if (!scale.isConnected) {
      _reason ??= StopReason.linkLost;
      _log('весы пропали — дорабатываем по времени');
      _settle();
      return;
    }

    _curve?.addWeight(s.at, s.grams);

    if (phase == ShotPhase.waiting && scale.isPouring) {
      phase = ShotPhase.pouring;
      notifyListeners();
    }

    final stop = _stop;
    if (stop != null && plan.stopOnYield && stop.onSample(s, scale.tracker)) {
      _reason = StopReason.weight;
      _curve?.markStop(s.at);
      _log(
        'спуск на ${stop.triggerGrams.toStringAsFixed(1)} г '
        'при потоке ${stop.triggerFlow.toStringAsFixed(2)} г/с',
      );
      unawaited(device.stop());
      _settle();
      return;
    }

    notifyListeners();
  }

  /// Команда ушла — дальше только смотрим, как вес доползает.
  void _settle() {
    if (phase == ShotPhase.settling || phase == ShotPhase.done) return;
    phase = ShotPhase.settling;
    _settleFrom = _now();
    _curve?.markStop(_now());
    notifyListeners();

    // Без весов осадку ждать не по чему: итог уже известен.
    if (!scale.isLive) {
      _finish();
      return;
    }
    unawaited(scale.timer(ScaleTimerCommand.stop));

    _settleTimer?.cancel();
    // Ждём, пока весы встанут, но не вечно: если чашку взяли в руки, устояться
    // им не суждено, а итог показать всё равно надо.
    _settleTimer = Timer.periodic(const Duration(milliseconds: 200), (t) {
      final waited = _now().difference(_settleFrom ?? _now());
      if (scale.isSettled || waited > kSettleTimeout) {
        t.cancel();
        _finish();
      } else {
        notifyListeners();
      }
    });
  }

  void _finish() {
    _settleTimer?.cancel();
    _settleTimer = null;

    final stop = _stop;
    final reason = _reason ?? StopReason.manual;
    final elapsed = _now().difference(_startedAt ?? _now());
    phase = ShotPhase.done;

    // Один нагрев проливом не считаем: в журнале ему делать нечего.
    if (!_sawPour) {
      _reset();
      return;
    }

    // Взвешенным пролив считается, только если весы дожили до конца и в чашке
    // что-то есть. Иначе запись всё равно будет — но про время, не про вес.
    final weighed = stop != null && scale.isLive && scale.grams >= 1;

    if (weighed) {
      final shot = stop.finish(
        reason: reason,
        finalGrams: scale.grams,
        elapsed: elapsed,
      );
      final learned = learnedDrip(drip: plan.drip, shot: shot);
      if (learned != null) {
        _log(
          'перелёт ${shot.overshoot.toStringAsFixed(1)} г, поправка '
          '${plan.drip.toStringAsFixed(2)} → ${learned.toStringAsFixed(2)} г',
        );
        prefs.gravimetry = plan.copyWith(drip: learned);
      } else {
        _log('на этом проливе не учимся: ${reason.name}');
      }
    }

    final record = ShotRecord(
      at: _now(),
      recipeName: prefs.recipe.name,
      temperatureC: _temperature,
      elapsed: elapsed,
      reason: reason,
      doseG: weighed ? plan.doseG : null,
      // Цель попадает в запись, только если по ней и вели: иначе разница с
      // ней — не промах, а совпадение.
      targetG: weighed && plan.stopOnYield ? plan.targetG : null,
      finalG: weighed ? scale.grams : null,
    );
    prefs.addShot(record);
    lastShot = record;
    _stop = null;

    // Кривая — отдельным файлом, и только у взвешенных проливов: без весов
    // рисовать нечего, кроме прямой линии температуры.
    final curve = weighed ? _curve?.build() : null;
    lastCurve = curve != null && !curve.isEmpty ? curve : null;
    if (lastCurve != null) unawaited(_saveCurve(record, lastCurve!));
    _curve = null;
    notifyListeners();
  }

  /// Записать кривую и убрать те, что вышли за срок хранения.
  Future<void> _saveCurve(ShotRecord record, ShotCurve curve) async {
    await _store.save(curveIdOf(record), curve);
    // Итогов помним двести, кривых — полсотни: они в сотни раз тяжелее, а
    // смотрят на них куда реже.
    await _store.prune({
      for (final s in prefs.shots.take(kCurveHistory)) curveIdOf(s),
    });
  }

  void _reset() {
    _stop = null;
    _reason = null;
    _startedAt = null;
    _settleFrom = null;
    _sawPour = false;
    _curve = null;
    phase = ShotPhase.idle;
    notifyListeners();
  }

  /// Убрать итог с экрана.
  ///
  /// Фазы это больше не касается: она про идущий контур, а итог — про
  /// последний прошедший, и живут они врозь. Закрыть итог можно и посреди
  /// следующего пролива.
  void dismiss() {
    if (lastShot == null && phase != ShotPhase.done) return;
    lastShot = null;
    lastCurve = null;
    if (phase == ShotPhase.done) _reset();
    notifyListeners();
  }

  @override
  void dispose() {
    _settleTimer?.cancel();
    device.removeListener(_onDevice);
    unawaited(_samples.cancel());
    super.dispose();
  }
}
