import 'dart:math' as math;

import '../ble/cycle.dart';
import '../ble/k2_device.dart';
import '../ble/protocol.dart';
import '../l10n/app_l10n.dart';
import '../l10n/l10n_ext.dart';
import '../store/prefs.dart';
import 'brew_phase.dart';
import 'recipe.dart';

/// Из чего складывается цикл. Порядок значений = порядок исполнения, на этом
/// держится сравнение фаз в [_markOf].
enum StepId { alarm, mode, heat, wetting, pause, extraction, flow }

/// Где машина относительно шага.
enum StepMark { upcoming, active, passed, error }

/// Цвет шага. Конкретный код цвета выбирает тот, кто рисует: у телефона своя
/// палитра, у часов своя. `mode` — акцент текущего режима.
enum StepTone { heat, water, amber, mode }

/// Каким экраном шаг настраивается.
enum EditorKind {
  /// Настройки нет — шаг только показывает.
  none,

  /// Число с минусом и плюсом.
  stepper,

  /// Часы-минуты будильника с тумблером.
  timer,

  /// Выбор одного режима из трёх.
  mode,
}

/// Шаг цикла в чистом виде: ни виджетов, ни цветов, ни колбэков.
///
/// Такой шаг одинаково пригоден и для таймлайна на телефоне, и для снимка,
/// который уезжает на часы: правило «что входит в цикл при этом режиме» живёт
/// ровно здесь и больше нигде.
class PipelineStep {
  const PipelineStep({
    required this.id,
    required this.label,
    required this.value,
    required this.tone,
    required this.mark,
    required this.editor,
    this.progress,
    this.editValue = 0,
    this.min = 0,
    this.max = 0,
    this.step = 1,
    this.unit = '',
    this.hint = '',
    this.editable = false,
  });

  final StepId id;

  /// Подпись над значением, как её увидит человек.
  final String label;

  /// Готовое к показу значение: «93°», «5 сек», «07:30», «8 / 15».
  final String value;

  final StepTone tone;
  final StepMark mark;

  /// 0..1 — сколько шага пройдено. null — кольцо/полоса ровные.
  final double? progress;

  final EditorKind editor;

  /// Число для редактора и его границы. У [EditorKind.timer] — минуты от
  /// полуночи, у [EditorKind.mode] — код [WorkMode].
  final int editValue;
  final int min;
  final int max;
  final int step;

  /// Приписка к числу в редакторе: «°», «сек», «».
  final String unit;

  /// Строка под большим числом в редакторе: зачем этот шаг нужен.
  final String hint;

  /// Настройку сейчас можно открыть. Во время работы и при взведённом
  /// таймере — нельзя: уставки на ходу машина не принимает.
  final bool editable;
}

/// Что делает единственная кнопка внизу.
enum CtaKind { connect, start, stop, done, cancelAlarm, blocked }

/// Готовый к показу цикл целиком.
class PipelineModel {
  const PipelineModel({
    required this.steps,
    required this.mode,
    required this.armed,
    required this.running,
    required this.cta,
    required this.blockingFault,
  });

  /// Шаги в порядке исполнения. Состав зависит от режима: у «нагрева» нет
  /// пролива, у «пролива» нет нагрева.
  final List<PipelineStep> steps;

  /// Режим, который действительно отработает: при взведённом таймере это
  /// режим будильника, а не тот, что выбран кнопкой.
  final WorkMode mode;

  final bool armed;
  final bool running;
  final CtaKind cta;
  final MachineError blockingFault;

  PipelineStep? byId(StepId id) {
    for (final s in steps) {
      if (s.id == id) return s;
    }
    return null;
  }
}

/// Собрать цикл из состояния машины и текущего рецепта.
///
/// [recipe] — то, что показываем: свежая правка пользователя, иначе уставки
/// самой машины. [mode] — режим, который отработает.
PipelineModel buildPipeline({
  required K2Device d,
  required AppL10n t,
  required Recipe recipe,
  required WorkMode mode,
  required bool fahrenheit,
  required bool editable,
}) {
  final a = d.appointment;
  final phase = d.progress.phase;
  final busy = d.isBusy;
  final params = d.workParams;
  final limits = d.tempLimits;
  final steps = <PipelineStep>[];

  // 1. Таймер. Стоит первым, потому что отложенный запуск случается раньше
  // всего остального; взведённый — светится и делает цикл нередактируемым.
  steps.add(
    PipelineStep(
      id: StepId.alarm,
      label: t.stepAlarm,
      value: a.enabled ? '${_two(a.hour)}:${_two(a.minute)}' : t.timerOff,
      tone: StepTone.amber,
      // Ожидание — это шаг целиком: кольцо замкнуто, полоса полная.
      progress: a.enabled ? 1 : null,
      mark: !a.enabled
          ? StepMark.upcoming
          : busy || phase == BrewPhase.done
          ? StepMark.passed
          : StepMark.active,
      editor: EditorKind.timer,
      editValue: a.hour * 60 + a.minute,
      min: 0,
      max: 24 * 60 - 1,
      step: 15,
      hint: t.scheduleHint,
      editable: editable,
    ),
  );

  // 2. Режим. Он решает состав всего, что ниже, — потому и стоит вторым.
  // Взведённому таймеру режим принадлежит тоже: менять его нужно вместе.
  steps.add(
    PipelineStep(
      id: StepId.mode,
      label: t.capMode,
      value: mode.label(t),
      tone: StepTone.mode,
      mark: StepMark.upcoming,
      editor: EditorKind.mode,
      editValue: mode.code,
      hint: t.runModeHint,
      editable: editable,
    ),
  );

  // 3. Нагрев — всюду, кроме холодного пролива.
  if (mode != WorkMode.brew) {
    // Живой отсчёт показываем всё время, пока машина на связи, а не только на
    // нагреве: сколько сейчас в бойлере — это то, ради чего на карточку и
    // смотрят, и до пуска тоже. Уставку он не заслоняет, а встаёт перед ней:
    // «24 → 92».
    final heating = phase == BrewPhase.heating;
    final status = d.isConnected ? d.status : null;
    final displayCurrent = toDisplayTemp(
      status?.temperatureC ?? recipe.temperatureC,
      fahrenheit,
    );
    final displayTarget = toDisplayTemp(recipe.temperatureC, fahrenheit);
    final fault = _heaterFault(d) ? d.lastFault : MachineError.none;
    steps.add(
      PipelineStep(
        id: StepId.heat,
        label: _heatLabel(t, d),
        value: fault != MachineError.none
            ? fault.action(t)
            : status != null
            ? t.temperatureProgress(
                displayCurrent,
                displayTarget,
                fahrenheit ? '°F' : '°C',
              )
            : '$displayTarget${fahrenheit ? '°F' : '°C'}',
        tone: StepTone.heat,
        mark: _heaterFault(d) ? StepMark.error : _markOf(phase, StepId.heat),
        // Прогрев считаем от комнатных 24°: от нуля шкала почти не двигалась бы.
        progress: heating && status != null
            ? ((status.temperatureC - 24) /
                      math.max(1, recipe.temperatureC - 24))
                  .clamp(0.0, 1.0)
            : null,
        editor: EditorKind.stepper,
        editValue: toDisplayTemp(recipe.temperatureC, fahrenheit),
        min: toDisplayTemp(limits.min, fahrenheit),
        max: toDisplayTemp(limits.max, fahrenheit),
        unit: fahrenheit ? '°F' : '°C',
        hint: t.descTemperature,
        editable: editable,
      ),
    );
  }

  // 4–7. Пролив целиком. У «только нагрева» его нет.
  if (mode != WorkMode.heat) {
    steps.add(
      _timed(
        t: t,
        d: d,
        id: StepId.wetting,
        label: t.stepWetting,
        tone: StepTone.water,
        seconds: recipe.preInfusionSeconds,
        range: params.preInfusion,
        hint: t.descWetting,
        editable: editable,
      ),
    );
    steps.add(
      _timed(
        t: t,
        d: d,
        id: StepId.pause,
        label: t.stepPause,
        tone: StepTone.water,
        seconds: recipe.standstillSeconds,
        range: params.standstill,
        hint: t.descPause,
        editable: editable,
      ),
    );
    steps.add(
      _timed(
        t: t,
        d: d,
        id: StepId.extraction,
        label: t.extraction,
        tone: StepTone.amber,
        seconds: recipe.extractionSeconds,
        range: params.extraction,
        hint: t.descExtraction,
        editable: editable,
        // Экстракция считает время вверх: видно, сколько уже налито.
        countUp: true,
      ),
    );
    final pmax = params.pressure.max;
    steps.add(
      PipelineStep(
        id: StepId.flow,
        label: t.pressure,
        value: t.stepOf(recipe.pressure, pmax),
        tone: StepTone.amber,
        // Ступень подачи — часть экстракции, поэтому и отметку берёт её.
        mark: _markOf(d.progress.phase, StepId.extraction),
        editor: EditorKind.stepper,
        editValue: recipe.pressure,
        min: params.pressure.min,
        max: pmax,
        hint: t.descFlow,
        editable: editable,
      ),
    );
  }

  return PipelineModel(
    steps: steps,
    mode: mode,
    armed: a.enabled,
    running: busy,
    cta: ctaKindOf(d, armed: a.enabled, mode: mode),
    blockingFault: faultBlocksMode(d.lastFault, mode)
        ? d.lastFault
        : MachineError.none,
  );
}

/// Что предложить единственной кнопкой внизу.
///
/// Одна на экран телефона и на часы: раньше их было две, и расходились они
/// именно там, где дороже всего, — в ожидании подтверждения после нажатия.
CtaKind ctaKindOf(K2Device d, {required bool armed, required WorkMode mode}) {
  if (!d.isConnected) return CtaKind.connect;
  switch (d.cycleState) {
    // Идёт цикл: единственное осмысленное действие — остановить.
    case CycleState.running:
    case CycleState.stopping:
      return CtaKind.stop;
    // Итог цикла держится несколько секунд и уступает место пуску.
    case CycleState.finished:
      return CtaKind.done;
    // Кадр пуска в пути: кнопка та же, но с ожиданием.
    case CycleState.starting:
      return CtaKind.start;
    case CycleState.idle:
    case CycleState.faulted:
      break;
  }
  // Машина ждёт своего часа: единственное осмысленное действие — снять
  // ожидание, иначе она всё равно запустится сама.
  if (armed) return CtaKind.cancelAlarm;
  if (faultBlocksMode(d.lastFault, mode)) return CtaKind.blocked;
  return CtaKind.start;
}

bool faultBlocksMode(MachineError fault, WorkMode mode) => switch (fault) {
  MachineError.none => false,
  // Незнакомый код пуск не запрещает: мы не знаем, что он значит, и запереть
  // из-за него машину — хуже, чем показать предупреждение и дать решить самому.
  MachineError.unknown => false,
  MachineError.dryBurning || MachineError.lowBattery => true,
  MachineError.batteryOverheating ||
  MachineError.heaterShortCircuit ||
  MachineError.lowBatteryHot => mode != WorkMode.brew,
};

/// Шаг, который длится заданное число секунд.
PipelineStep _timed({
  required AppL10n t,
  required K2Device d,
  required StepId id,
  required String label,
  required StepTone tone,
  required int seconds,
  required Range range,
  required String hint,
  required bool editable,
  bool countUp = false,
}) {
  final at = _phaseOf(id);
  final active = d.progress.phase == at;
  final left = d.progress.total == null
      ? null
      : d.progress.total! - d.progress.elapsed;
  // В работе направление отсчёта подписано явно: у смачивания и паузы
  // осталось N секунд, у экстракции показано N из всей уставки.
  final live = active
      ? countUp
            ? d.progress.elapsed.inSeconds
            : math.max(0, left?.inSeconds ?? seconds)
      : seconds;
  return PipelineStep(
    id: id,
    label: label,
    value: active
        ? countUp
              ? t.secondsOf(live.clamp(0, seconds), seconds)
              : t.secondsRemaining(live)
        : t.seconds(live),
    tone: tone,
    mark: _markOf(d.progress.phase, id),
    progress: active ? d.progress.fraction : null,
    editor: EditorKind.stepper,
    editValue: seconds,
    min: range.min,
    max: range.max,
    unit: t.secondsUnit,
    hint: hint,
    editable: editable,
  );
}

/// Какой фазе телеметрии соответствует шаг. Шаги-настройки фазы не имеют.
BrewPhase? _phaseOf(StepId id) => switch (id) {
  StepId.heat => BrewPhase.heating,
  StepId.wetting => BrewPhase.preInfusion,
  StepId.pause => BrewPhase.standstill,
  StepId.extraction => BrewPhase.extraction,
  _ => null,
};

/// Где машина относительно этого шага.
StepMark _markOf(BrewPhase phase, StepId id) {
  final at = _phaseOf(id);
  if (at == null) return StepMark.upcoming;
  if (phase == at) return StepMark.active;
  if (phase == BrewPhase.done) return StepMark.passed;
  // Порядок фаз в перечислении совпадает с порядком цикла.
  final now = phase.index;
  if (now == BrewPhase.idle.index || now == BrewPhase.error.index) {
    return StepMark.upcoming;
  }
  return now > at.index ? StepMark.passed : StepMark.upcoming;
}

/// Нагрев сломан или греть нечего.
bool _heaterFault(K2Device d) => switch (d.lastFault) {
  MachineError.dryBurning ||
  MachineError.heaterShortCircuit ||
  MachineError.batteryOverheating ||
  MachineError.lowBatteryHot => true,
  _ => false,
};

String _heatLabel(AppL10n t, K2Device d) => switch (d.lastFault) {
  MachineError.dryBurning => t.stepNoWater,
  MachineError.heaterShortCircuit ||
  MachineError.batteryOverheating ||
  MachineError.lowBatteryHot => t.stepHeatError,
  _ => t.phaseHeating,
};

String _two(int v) => v.toString().padLeft(2, '0');
