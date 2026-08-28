// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_l10n.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppL10nEn extends AppL10n {
  AppL10nEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'BetterCup';

  @override
  String get demoMachineName => 'K2 Pro';

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
  String get timer => 'Timer';

  @override
  String get timerOff => 'Off';

  @override
  String get secondsUnit => 'sec';

  @override
  String get hoursShort => 'h';

  @override
  String get minutesShort => 'min';

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
  String get stepAlarm => 'Timer';

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
  String get slideToStop => 'Stop';

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
    return '$current → $target$unit';
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

  @override
  String get connectDevice => 'Connect a machine';

  @override
  String get welcomeSubtitle =>
      'Connect your K2 Pro over Bluetooth — or see how it all works without the hardware.';

  @override
  String get demoBadge => 'DEMO';

  @override
  String get demoTitle => 'Demo mode';

  @override
  String get demoStart => 'Try the demo';

  @override
  String get demoAbout => 'Simulated machine and scale';

  @override
  String get demoSection => 'Demo';

  @override
  String get stepWeight => 'Weight';

  @override
  String get weightTitle => 'Scale';

  @override
  String get weightTare => 'Tare';

  @override
  String get weightStopByWeight => 'Stop by weight';

  @override
  String get weightStopByWeightHint =>
      'The pour ends at the target weight. Seconds become a safety limit.';

  @override
  String get weightByTime => 'By time';

  @override
  String get weightByWeight => 'By weight';

  @override
  String get weightTarget => 'Target';

  @override
  String get weightDose => 'Dose';

  @override
  String get weightTakeCurrent => 'Weigh the dose';

  @override
  String weightRatio(String value) {
    return 'Ratio 1:$value';
  }

  @override
  String get weightNoDose => 'not weighed';

  @override
  String get weightLimit => 'Limit';

  @override
  String get weightLimitHint =>
      'The machine will stop here even if the target is not reached.';

  @override
  String weightOf(String value, String total) {
    return '$value → $total g';
  }

  @override
  String weightGrams(String value) {
    return '$value g';
  }

  @override
  String get gramsUnit => 'g';

  @override
  String get weightSettling => 'Settling';

  @override
  String weightStoppedByTime(String value, String total) {
    return 'Stopped by time, $value of $total g';
  }

  @override
  String get weightScaleLost => 'Scale lost — finishing on time';

  @override
  String get weightNotConnected => 'No scale';

  @override
  String get weightConnect =>
      'Connect a scale to weigh and to stop the pour by weight.';

  @override
  String get weightJournal => 'Pour log';

  @override
  String get weightJournalEmpty => 'No pours yet';

  @override
  String get weightJournalClear => 'Clear log';

  @override
  String weightMissOver(String value) {
    return '+$value g';
  }

  @override
  String weightMissUnder(String value) {
    return '$value g';
  }

  @override
  String get reasonWeight => 'by weight';

  @override
  String get reasonTimeout => 'by time';

  @override
  String get reasonManual => 'by hand';

  @override
  String get reasonLinkLost => 'link lost';

  @override
  String scaleBattery(int value) {
    return '$value%';
  }

  @override
  String get scaleAsleep => 'asleep';

  @override
  String get journalAccuracy => 'Accuracy';

  @override
  String get journalPours => 'Pours';

  @override
  String get journalCount => 'Pours';

  @override
  String get journalAvgMiss => 'Avg miss';

  @override
  String get journalAvgTime => 'Avg time';

  @override
  String get descYield =>
      'How much should end up in the cup. The pour stops here.';

  @override
  String get journalTiming => 'Shot time';

  @override
  String get journalTimingHint =>
      'At the same dose and target, steady time means a steady grind.';

  @override
  String weightOnScale(String value) {
    return '$value g on the scale';
  }

  @override
  String get journalStats => 'Statistics';

  @override
  String get shotNoCurve =>
      'No graph for this pour — there was no scale connected.';

  @override
  String get shotParams => 'Details';

  @override
  String get shotYield => 'In the cup';

  @override
  String get shotRatio => 'Ratio';

  @override
  String get shotTime => 'Time';

  @override
  String get shotEnded => 'Ended';

  @override
  String get chartWeight => 'Weight';

  @override
  String get chartFlow => 'Flow';

  @override
  String get chartTemperature => 'Temperature';

  @override
  String get today => 'Today';

  @override
  String get timerReadyIn => 'Ready in';

  @override
  String get timerReadyHint =>
      'The machine starts early so the coffee is ready right on time.';

  @override
  String timerStartAt(String time) {
    return 'Starts at $time';
  }

  @override
  String get timerByTime => 'At a set time';

  @override
  String get timerSchedule => 'Schedule';

  @override
  String get adviceAfterShot => 'Advice after each shot';

  @override
  String get brewAdvice => 'Brewing tips';

  @override
  String get adviceHeadline => 'How did it turn out?';

  @override
  String get adviceBannerBody => 'Tune the recipe to taste';

  @override
  String get adviceTune => 'Tune';

  @override
  String get adviceTasteTitle => 'Taste';

  @override
  String get adviceBodyTitle => 'Body';

  @override
  String get tasteSour => 'Sour';

  @override
  String get tasteSalty => 'Salty';

  @override
  String get tasteEmpty => 'Watery';

  @override
  String get tasteSweet => 'Sweet';

  @override
  String get tasteBitter => 'Bitter';

  @override
  String get bodyThin => 'Thin';

  @override
  String get bodyFull => 'Full';

  @override
  String get adviceWhySour =>
      'Sour — under-extracted: the water ran through too fast.';

  @override
  String get adviceWhySalty => 'Salty — extraction cut off too early.';

  @override
  String get adviceWhyBitter =>
      'Bitter — over-extracted: the water ran too long.';

  @override
  String get adviceWhyEmpty =>
      'Watery — weak: too little coffee for the water.';

  @override
  String get adviceWhySweet => 'Sweet and balanced — right on point.';

  @override
  String get adviceWhyThin => 'Thin — lacks density.';

  @override
  String get adviceControls => 'What to do';

  @override
  String get advicePick =>
      'Pick taste and body — I\'ll suggest what to adjust.';

  @override
  String get adviceNoChange => 'Nothing to change.';

  @override
  String get adviceRatioHint => 'Tighten the ratio in the scale dialog.';

  @override
  String get tasteAstringent => 'Astringent';

  @override
  String get adviceWhyAstringent =>
      'Astringent — over-extracted, a parched puck.';

  @override
  String get fixGrindFiner => 'Grind finer';

  @override
  String get fixGrindCoarser => 'Grind coarser';

  @override
  String get fixDoseMore => 'More coffee';

  @override
  String get fixRatioShorter => 'Shorter yield';

  @override
  String get fixGrindFinerWhy =>
      'The main lever: finer grind slows the water — more extraction.';

  @override
  String get fixGrindCoarserWhy =>
      'The main lever: coarser grind speeds the water — less extraction.';

  @override
  String get fixDoseMoreWhy => 'Add more grounds — a denser, stronger cup.';

  @override
  String get fixRatioShorterWhy =>
      'Lower the scale target — less water, a denser cup.';

  @override
  String get fixTempUpWhy =>
      'If the grind is dialed in — raise the temperature a degree or two.';

  @override
  String get fixTempDownWhy =>
      'If the grind is dialed in — lower the temperature a degree or two.';

  @override
  String get adviceLastResort => 'Last resort';

  @override
  String get adviceScaleOff => 'Connect a scale to control the yield.';
}
