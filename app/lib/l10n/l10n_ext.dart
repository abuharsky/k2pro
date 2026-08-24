import 'package:flutter/widgets.dart';

import '../ble/protocol.dart';
import '../model/brew_phase.dart';
import '../model/recipe.dart';
import 'app_l10n.dart';

/// Короткий доступ к строкам: `context.t.connect`.
extension L10nContext on BuildContext {
  AppL10n get t => AppL10n.of(this);
}

extension RecipeL10n on Recipe {
  /// Имя для экрана: у встроенных пресетов — перевод, у остальных — как назвали.
  String displayName(AppL10n t) => switch (builtinKey) {
    'mediumDark' => t.recipeMediumDark,
    'dark' => t.recipeDark,
    'light' => t.recipeLight,
    _ => name,
  };
}

extension MachineStateL10n on MachineState {
  String label(AppL10n t) => switch (this) {
    MachineState.standby => t.stateSleep,
    MachineState.heating => t.stateHeating,
    MachineState.heatDone => t.stateWaterReady,
    MachineState.heatBrewing => t.stateHeatBrew,
    MachineState.brewing => t.stateBrewing,
    MachineState.heatBrewDone || MachineState.brewDone => t.stateReady,
  };
}

extension MachineErrorL10n on MachineError {
  String label(AppL10n t) => switch (this) {
    MachineError.none => t.errUnknown,
    MachineError.dryBurning => t.errDryBurning,
    MachineError.batteryOverheating => t.errBatteryOverheating,
    MachineError.heaterShortCircuit => t.errHeaterShortCircuit,
    MachineError.lowBatteryHot => t.errLowBatteryHot,
    MachineError.lowBattery => t.errLowBattery,
  };
}

extension BrewPhaseL10n on BrewPhase {
  String label(AppL10n t) => switch (this) {
    BrewPhase.idle => '',
    BrewPhase.heating => t.phaseHeating,
    BrewPhase.preInfusion => t.phasePreInfusion,
    BrewPhase.standstill => t.phaseStandstill,
    BrewPhase.extraction => t.phaseExtraction,
    BrewPhase.done => t.phaseDone,
    BrewPhase.error => t.stateError,
  };
}

extension WorkModeL10n on WorkMode {
  String label(AppL10n t) => switch (this) {
    WorkMode.heatAndBrew => t.modeHeatAndBrew,
    WorkMode.heat => t.modeHeat,
    WorkMode.brew => t.modeBrew,
  };
}

extension WorkModeSchedule on WorkMode {
  /// Тот же смысл в терминах будильника. Нумерация в протоколе разная, см.
  /// [ScheduleMode].
  ScheduleMode get asScheduleMode => switch (this) {
    WorkMode.heatAndBrew => ScheduleMode.heatAndBrew,
    WorkMode.heat => ScheduleMode.heat,
    WorkMode.brew => ScheduleMode.brew,
  };
}

extension ScheduleModeWork on ScheduleMode {
  /// Тот же смысл в терминах ручного пуска: нумерация в протоколе разная,
  /// а машина делает одно и то же.
  WorkMode get asWorkMode => switch (this) {
    ScheduleMode.heatAndBrew => WorkMode.heatAndBrew,
    ScheduleMode.heat => WorkMode.heat,
    ScheduleMode.brew => WorkMode.brew,
  };
}

extension ScheduleModeL10n on ScheduleMode {
  String label(AppL10n t) => switch (this) {
    ScheduleMode.heatAndBrew => t.modeHeatAndBrew,
    ScheduleMode.heat => t.modeHeat,
    ScheduleMode.brew => t.modeBrew,
  };
}

extension BeepSoundL10n on BeepSound {
  String label(AppL10n t) => switch (this) {
    BeepSound.dingDong => t.toneDingDong,
    BeepSound.diDi => t.toneDiDi,
    BeepSound.buGu => t.toneBuGu,
    BeepSound.biBi => t.toneBiBi,
  };
}
