// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_l10n.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppL10nEn extends AppL10n {
  AppL10nEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'K2 Pro';

  @override
  String get connected => 'Connected';

  @override
  String get connecting => 'Connecting…';

  @override
  String get disconnected => 'Disconnected';

  @override
  String get connect => 'Connect';

  @override
  String get disconnect => 'Disconnect';

  @override
  String get notConnected => 'Not connected';

  @override
  String get reading => 'Reading…';

  @override
  String get devicesNearby => 'Devices nearby';

  @override
  String get searching => 'Searching…';

  @override
  String get search => 'Search again';

  @override
  String get showAll => 'All BLE';

  @override
  String rssi(int value) {
    return '$value dBm';
  }

  @override
  String get stateSleep => 'Sleep';

  @override
  String get stateHeating => 'Heating';

  @override
  String get stateWaterReady => 'Water ready';

  @override
  String get stateHeatBrew => 'Heat + brew';

  @override
  String get stateBrewing => 'Brewing';

  @override
  String get stateReady => 'Ready';

  @override
  String get stateError => 'Error';

  @override
  String get phaseHeating => 'Heating';

  @override
  String get phasePreInfusion => 'Pre-infusion';

  @override
  String get phaseStandstill => 'Standstill';

  @override
  String get phaseExtraction => 'Extraction';

  @override
  String get phaseDone => 'Ready';

  @override
  String seconds(int value) {
    return '$value sec';
  }

  @override
  String get recipe => 'Recipe';

  @override
  String get recipeMediumDark => 'Medium-dark';

  @override
  String get recipeDark => 'Dark';

  @override
  String get recipeLight => 'Light';

  @override
  String get temperature => 'Temperature';

  @override
  String get flowSpeed => 'Extraction speed';

  @override
  String get preInfusion => 'Pre-infusion';

  @override
  String get standstill => 'Standstill';

  @override
  String get extraction => 'Extraction';

  @override
  String get actionStop => 'STOP';

  @override
  String get actionRun => 'RUN';

  @override
  String get runMode => 'What to run';

  @override
  String get errDryBurning => 'No water — dry burn protection';

  @override
  String get errBatteryOverheating => 'Battery overheating, wait before use';

  @override
  String get errHeaterShortCircuit => 'Heater short circuit — service needed';

  @override
  String get errLowBatteryHot => 'Battery too low for heating';

  @override
  String get errLowBattery => 'Low battery, charge soon';

  @override
  String get errUnknown => 'Device error';

  @override
  String errCode(int code) {
    return 'code $code';
  }

  @override
  String get settings => 'Settings';

  @override
  String get sectionDevice => 'Device';

  @override
  String get sectionStatistics => 'Statistics';

  @override
  String get sectionSchedule => 'Scheduled start';

  @override
  String get sectionMaintenance => 'Maintenance';

  @override
  String get deviceNameLabel => 'Name';

  @override
  String get deviceNameTitle => 'Device name';

  @override
  String get fahrenheit => 'Fahrenheit';

  @override
  String get model => 'Model';

  @override
  String get versions => 'Versions';

  @override
  String get language => 'Language';

  @override
  String get languageSystem => 'System';

  @override
  String get cupsToday => 'Cups today';

  @override
  String get lastDays => 'Last days';

  @override
  String get refresh => 'Refresh';

  @override
  String get scheduleEnabled => 'Enabled';

  @override
  String get scheduleTime => 'Time';

  @override
  String get scheduleMode => 'Mode';

  @override
  String get scheduleSound => 'Sound';

  @override
  String get scheduleTone => 'Tone';

  @override
  String get modeHeatAndBrew => 'Heat + brew';

  @override
  String get modeHeat => 'Heat';

  @override
  String get modeBrew => 'Brew';

  @override
  String get toneDingDong => 'Ding dong';

  @override
  String get toneDiDi => 'Di di';

  @override
  String get toneBuGu => 'Bu gu';

  @override
  String get toneBiBi => 'Bi bi';

  @override
  String get restoreDefaults => 'Restore machine defaults';

  @override
  String get restoreDefaultsQuestion => 'Restore defaults?';

  @override
  String get restoreDefaultsBody =>
      'Machine brewing parameters and target temperature will be reset.';

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get reset => 'Reset';

  @override
  String get done => 'Done';

  @override
  String get dash => '—';

  @override
  String get pourTime => 'Pour';

  @override
  String get sectionBrewParams => 'Brew parameters';

  @override
  String get tempCell => 'Temp';

  @override
  String get telemetry => 'Telemetry 0x00';

  @override
  String get renameDevice => 'Rename';

  @override
  String get otherDevice => 'Other machine…';

  @override
  String get presets => 'Presets';

  @override
  String get roastLight => 'Light roast';

  @override
  String get roastMedium => 'Medium roast';

  @override
  String get roastDark => 'Dark roast';

  @override
  String get temperatureHint =>
      'Hotter suits light roasts, cooler suits dark ones.';

  @override
  String limitsRange(String min, String max) {
    return '$min–$max';
  }

  @override
  String get pourTitle => 'Full pour';

  @override
  String get extractionNote =>
      'This is the full pour — the machine stops here and never runs longer. Set less for a shorter shot.';

  @override
  String cycleTotal(int value) {
    return 'Whole cycle $value s';
  }

  @override
  String get runModeHint => 'What the button starts';

  @override
  String get moreSettings => 'More…';

  @override
  String get timer => 'Scheduled start';

  @override
  String get timerOff => 'Off';

  @override
  String get secondsUnit => 'sec';

  @override
  String get stageWater => 'Water';

  @override
  String get stagePump => 'Pump';

  @override
  String get stageCup => 'Cup';

  @override
  String get charging => 'charging';

  @override
  String get ctaStart => 'Start';

  @override
  String get ctaStop => 'Stop';

  @override
  String get stepWetting => 'Wetting';

  @override
  String get stepPour => 'Pour';

  @override
  String get presetsByRoast => 'Presets by bean roast';

  @override
  String get roastLightShort => 'Light';

  @override
  String get roastMediumShort => 'Medium';

  @override
  String get roastDarkShort => 'Dark';

  @override
  String get pauseAfter => 'Pause after';

  @override
  String get pourTimeout => 'Pour timeout';

  @override
  String get scheduleHint =>
      'The machine starts the selected cycle at this time.';

  @override
  String minutesShift(String value) {
    return '$value min';
  }

  @override
  String get searchNearby => 'Looking for devices nearby…';

  @override
  String get deviceConnected => 'Connected';

  @override
  String get firmware => 'Firmware';

  @override
  String get statPoursWeek => 'In 7 days';

  @override
  String get stepNoWater => 'No water';

  @override
  String get stepHeatError => 'Heater fault';

  @override
  String get stepWater => 'Water';

  @override
  String get stepAlarm => 'Scheduled start';

  @override
  String get stepPause => 'Pause';

  @override
  String get cancelAlarm => 'Cancel scheduled start';

  @override
  String get pressure => 'Pressure';

  @override
  String get pressureNote =>
      'Steps, not bars: the machine reports no pressure back. What actually builds up on the puck is set by the grind.';

  @override
  String get ctaDone => 'Done ✓';

  @override
  String get modeHeatDesc => 'water heating only, up to the set temperature';

  @override
  String get modeHeatAndBrewDesc => 'heats the water first, then brews';

  @override
  String get modeBrewDesc => 'pour without heating the water';

  @override
  String get pourTimeTitle => 'Pour time';

  @override
  String get pourSkipNote => 'A step set to 0 s is skipped.';

  @override
  String get descWetting => 'water wets the coffee puck';

  @override
  String get descPause => 'the coffee swells before the pour';

  @override
  String get descExtraction => 'the main pour into the cup';

  @override
  String get descFlow => 'step 1–15, water delivery rate';

  @override
  String get capTimer => 'TIMER';

  @override
  String get capMode => 'MODE';

  @override
  String stepOf(int value, int max) {
    return '$value / $max';
  }

  @override
  String get modeHeatShort => 'Heat';

  @override
  String get modeFullShort => 'Full';

  @override
  String get modeBrewShort => 'Brew';

  @override
  String get descTemperature => 'water temperature';

  @override
  String get asleep => 'asleep';

  @override
  String get devices => 'Devices';

  @override
  String get myDevices => 'My devices';

  @override
  String get notInRange => 'Not in range';

  @override
  String get tapToConnect => 'Tap to connect';

  @override
  String get forgetDevice => 'Forget device';

  @override
  String get forget => 'Forget';

  @override
  String forgetDeviceQuestion(String name) {
    return 'Forget $name?';
  }

  @override
  String get forgetDeviceBody =>
      'The machine will leave the list. You can add it again from the search.';

  @override
  String get machines => 'Machines';

  @override
  String get deviceAvailable => 'Available';

  @override
  String get scheduleToday => 'Today';

  @override
  String get scheduleTomorrow => 'Tomorrow';

  @override
  String scheduleStarts(String day, String time, String mode) {
    return '$day at $time, the machine will start: $mode.';
  }

  @override
  String get confirmScheduledStart => 'Enable scheduled start?';

  @override
  String get scheduledStartWarning =>
      'The machine will start unattended. Make sure it is upright, filled with water, and ready to run.';

  @override
  String get enable => 'Enable';

  @override
  String get slideToStart => 'Slide to start';

  @override
  String get holdToStart => 'Hold to start';

  @override
  String startMode(String mode) {
    return 'Start · $mode';
  }

  @override
  String get lowBatteryStartTitle => 'Low battery';

  @override
  String get lowBatteryStartBody =>
      'The battery may not complete the heating cycle. Continue anyway?';

  @override
  String get startAnyway => 'Start anyway';

  @override
  String get faultAddWater => 'Add water';

  @override
  String get faultCoolDown => 'Let it cool down';

  @override
  String get faultService => 'Service required';

  @override
  String get faultCharge => 'Charge the machine';

  @override
  String get checkAgain => 'Check again';

  @override
  String secondsRemaining(int value) {
    return '$value s left';
  }

  @override
  String secondsOf(int value, int total) {
    return '$value/$total s';
  }

  @override
  String temperatureProgress(int current, int target, String unit) {
    return '$current/$target$unit';
  }

  @override
  String get temperatureUnit => 'Temperature unit';

  @override
  String get sectionOverview => 'Overview';

  @override
  String get sectionApp => 'App';

  @override
  String get openDeviceSettings => 'Machine settings';

  @override
  String get openDevices => 'Bluetooth devices';

  @override
  String get increase => 'Increase';

  @override
  String get decrease => 'Decrease';
}
