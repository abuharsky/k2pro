import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_l10n_en.dart';
import 'app_l10n_ru.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppL10n
/// returned by `AppL10n.of(context)`.
///
/// Applications need to include `AppL10n.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_l10n.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppL10n.localizationsDelegates,
///   supportedLocales: AppL10n.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppL10n.supportedLocales
/// property.
abstract class AppL10n {
  AppL10n(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppL10n of(BuildContext context) {
    return Localizations.of<AppL10n>(context, AppL10n)!;
  }

  static const LocalizationsDelegate<AppL10n> delegate = _AppL10nDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ru'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'K2 Pro'**
  String get appTitle;

  /// No description provided for @connected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get connected;

  /// No description provided for @connecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting…'**
  String get connecting;

  /// No description provided for @disconnected.
  ///
  /// In en, this message translates to:
  /// **'Disconnected'**
  String get disconnected;

  /// No description provided for @connect.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get connect;

  /// No description provided for @disconnect.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get disconnect;

  /// No description provided for @notConnected.
  ///
  /// In en, this message translates to:
  /// **'Not connected'**
  String get notConnected;

  /// No description provided for @reading.
  ///
  /// In en, this message translates to:
  /// **'Reading…'**
  String get reading;

  /// No description provided for @devicesNearby.
  ///
  /// In en, this message translates to:
  /// **'Devices nearby'**
  String get devicesNearby;

  /// No description provided for @searching.
  ///
  /// In en, this message translates to:
  /// **'Searching…'**
  String get searching;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search again'**
  String get search;

  /// No description provided for @showAll.
  ///
  /// In en, this message translates to:
  /// **'All BLE'**
  String get showAll;

  /// No description provided for @rssi.
  ///
  /// In en, this message translates to:
  /// **'{value} dBm'**
  String rssi(int value);

  /// No description provided for @stateSleep.
  ///
  /// In en, this message translates to:
  /// **'Sleep'**
  String get stateSleep;

  /// No description provided for @stateHeating.
  ///
  /// In en, this message translates to:
  /// **'Heating'**
  String get stateHeating;

  /// No description provided for @stateWaterReady.
  ///
  /// In en, this message translates to:
  /// **'Water ready'**
  String get stateWaterReady;

  /// No description provided for @stateHeatBrew.
  ///
  /// In en, this message translates to:
  /// **'Heat + brew'**
  String get stateHeatBrew;

  /// No description provided for @stateBrewing.
  ///
  /// In en, this message translates to:
  /// **'Brewing'**
  String get stateBrewing;

  /// No description provided for @stateReady.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get stateReady;

  /// No description provided for @stateError.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get stateError;

  /// No description provided for @phaseHeating.
  ///
  /// In en, this message translates to:
  /// **'Heating'**
  String get phaseHeating;

  /// No description provided for @phasePreInfusion.
  ///
  /// In en, this message translates to:
  /// **'Pre-infusion'**
  String get phasePreInfusion;

  /// No description provided for @phaseStandstill.
  ///
  /// In en, this message translates to:
  /// **'Standstill'**
  String get phaseStandstill;

  /// No description provided for @phaseExtraction.
  ///
  /// In en, this message translates to:
  /// **'Extraction'**
  String get phaseExtraction;

  /// No description provided for @phaseDone.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get phaseDone;

  /// No description provided for @seconds.
  ///
  /// In en, this message translates to:
  /// **'{value} sec'**
  String seconds(int value);

  /// No description provided for @recipe.
  ///
  /// In en, this message translates to:
  /// **'Recipe'**
  String get recipe;

  /// No description provided for @recipeMediumDark.
  ///
  /// In en, this message translates to:
  /// **'Medium-dark'**
  String get recipeMediumDark;

  /// No description provided for @recipeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get recipeDark;

  /// No description provided for @recipeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get recipeLight;

  /// No description provided for @temperature.
  ///
  /// In en, this message translates to:
  /// **'Temperature'**
  String get temperature;

  /// No description provided for @flowSpeed.
  ///
  /// In en, this message translates to:
  /// **'Extraction speed'**
  String get flowSpeed;

  /// No description provided for @preInfusion.
  ///
  /// In en, this message translates to:
  /// **'Pre-infusion'**
  String get preInfusion;

  /// No description provided for @standstill.
  ///
  /// In en, this message translates to:
  /// **'Standstill'**
  String get standstill;

  /// No description provided for @extraction.
  ///
  /// In en, this message translates to:
  /// **'Extraction'**
  String get extraction;

  /// No description provided for @actionStop.
  ///
  /// In en, this message translates to:
  /// **'STOP'**
  String get actionStop;

  /// No description provided for @actionRun.
  ///
  /// In en, this message translates to:
  /// **'RUN'**
  String get actionRun;

  /// No description provided for @runMode.
  ///
  /// In en, this message translates to:
  /// **'What to run'**
  String get runMode;

  /// No description provided for @errDryBurning.
  ///
  /// In en, this message translates to:
  /// **'No water — dry burn protection'**
  String get errDryBurning;

  /// No description provided for @errBatteryOverheating.
  ///
  /// In en, this message translates to:
  /// **'Battery overheating, wait before use'**
  String get errBatteryOverheating;

  /// No description provided for @errHeaterShortCircuit.
  ///
  /// In en, this message translates to:
  /// **'Heater short circuit — service needed'**
  String get errHeaterShortCircuit;

  /// No description provided for @errLowBatteryHot.
  ///
  /// In en, this message translates to:
  /// **'Battery too low for heating'**
  String get errLowBatteryHot;

  /// No description provided for @errLowBattery.
  ///
  /// In en, this message translates to:
  /// **'Low battery, charge soon'**
  String get errLowBattery;

  /// No description provided for @errUnknown.
  ///
  /// In en, this message translates to:
  /// **'Device error'**
  String get errUnknown;

  /// No description provided for @errCode.
  ///
  /// In en, this message translates to:
  /// **'code {code}'**
  String errCode(int code);

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @sectionDevice.
  ///
  /// In en, this message translates to:
  /// **'Device'**
  String get sectionDevice;

  /// No description provided for @sectionStatistics.
  ///
  /// In en, this message translates to:
  /// **'Statistics'**
  String get sectionStatistics;

  /// No description provided for @sectionSchedule.
  ///
  /// In en, this message translates to:
  /// **'Scheduled start'**
  String get sectionSchedule;

  /// No description provided for @sectionMaintenance.
  ///
  /// In en, this message translates to:
  /// **'Maintenance'**
  String get sectionMaintenance;

  /// No description provided for @deviceNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get deviceNameLabel;

  /// No description provided for @deviceNameTitle.
  ///
  /// In en, this message translates to:
  /// **'Device name'**
  String get deviceNameTitle;

  /// No description provided for @fahrenheit.
  ///
  /// In en, this message translates to:
  /// **'Fahrenheit'**
  String get fahrenheit;

  /// No description provided for @model.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get model;

  /// No description provided for @versions.
  ///
  /// In en, this message translates to:
  /// **'Versions'**
  String get versions;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @languageSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get languageSystem;

  /// No description provided for @cupsToday.
  ///
  /// In en, this message translates to:
  /// **'Cups today'**
  String get cupsToday;

  /// No description provided for @lastDays.
  ///
  /// In en, this message translates to:
  /// **'Last days'**
  String get lastDays;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @scheduleEnabled.
  ///
  /// In en, this message translates to:
  /// **'Enabled'**
  String get scheduleEnabled;

  /// No description provided for @scheduleTime.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get scheduleTime;

  /// No description provided for @scheduleMode.
  ///
  /// In en, this message translates to:
  /// **'Mode'**
  String get scheduleMode;

  /// No description provided for @scheduleSound.
  ///
  /// In en, this message translates to:
  /// **'Sound'**
  String get scheduleSound;

  /// No description provided for @scheduleTone.
  ///
  /// In en, this message translates to:
  /// **'Tone'**
  String get scheduleTone;

  /// No description provided for @modeHeatAndBrew.
  ///
  /// In en, this message translates to:
  /// **'Heat + brew'**
  String get modeHeatAndBrew;

  /// No description provided for @modeHeat.
  ///
  /// In en, this message translates to:
  /// **'Heat'**
  String get modeHeat;

  /// No description provided for @modeBrew.
  ///
  /// In en, this message translates to:
  /// **'Brew'**
  String get modeBrew;

  /// No description provided for @toneDingDong.
  ///
  /// In en, this message translates to:
  /// **'Ding dong'**
  String get toneDingDong;

  /// No description provided for @toneDiDi.
  ///
  /// In en, this message translates to:
  /// **'Di di'**
  String get toneDiDi;

  /// No description provided for @toneBuGu.
  ///
  /// In en, this message translates to:
  /// **'Bu gu'**
  String get toneBuGu;

  /// No description provided for @toneBiBi.
  ///
  /// In en, this message translates to:
  /// **'Bi bi'**
  String get toneBiBi;

  /// No description provided for @restoreDefaults.
  ///
  /// In en, this message translates to:
  /// **'Restore machine defaults'**
  String get restoreDefaults;

  /// No description provided for @restoreDefaultsQuestion.
  ///
  /// In en, this message translates to:
  /// **'Restore defaults?'**
  String get restoreDefaultsQuestion;

  /// No description provided for @restoreDefaultsBody.
  ///
  /// In en, this message translates to:
  /// **'Machine brewing parameters and target temperature will be reset.'**
  String get restoreDefaultsBody;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @reset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get reset;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @dash.
  ///
  /// In en, this message translates to:
  /// **'—'**
  String get dash;

  /// No description provided for @pourTime.
  ///
  /// In en, this message translates to:
  /// **'Pour'**
  String get pourTime;

  /// No description provided for @sectionBrewParams.
  ///
  /// In en, this message translates to:
  /// **'Brew parameters'**
  String get sectionBrewParams;

  /// No description provided for @tempCell.
  ///
  /// In en, this message translates to:
  /// **'Temp'**
  String get tempCell;

  /// No description provided for @telemetry.
  ///
  /// In en, this message translates to:
  /// **'Telemetry 0x00'**
  String get telemetry;

  /// No description provided for @renameDevice.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get renameDevice;

  /// No description provided for @otherDevice.
  ///
  /// In en, this message translates to:
  /// **'Other machine…'**
  String get otherDevice;

  /// No description provided for @presets.
  ///
  /// In en, this message translates to:
  /// **'Presets'**
  String get presets;

  /// No description provided for @roastLight.
  ///
  /// In en, this message translates to:
  /// **'Light roast'**
  String get roastLight;

  /// No description provided for @roastMedium.
  ///
  /// In en, this message translates to:
  /// **'Medium roast'**
  String get roastMedium;

  /// No description provided for @roastDark.
  ///
  /// In en, this message translates to:
  /// **'Dark roast'**
  String get roastDark;

  /// No description provided for @temperatureHint.
  ///
  /// In en, this message translates to:
  /// **'Hotter suits light roasts, cooler suits dark ones.'**
  String get temperatureHint;

  /// No description provided for @limitsRange.
  ///
  /// In en, this message translates to:
  /// **'{min}–{max}'**
  String limitsRange(String min, String max);

  /// No description provided for @pourTitle.
  ///
  /// In en, this message translates to:
  /// **'Full pour'**
  String get pourTitle;

  /// No description provided for @extractionNote.
  ///
  /// In en, this message translates to:
  /// **'This is the full pour — the machine stops here and never runs longer. Set less for a shorter shot.'**
  String get extractionNote;

  /// No description provided for @cycleTotal.
  ///
  /// In en, this message translates to:
  /// **'Whole cycle {value} s'**
  String cycleTotal(int value);

  /// No description provided for @runModeHint.
  ///
  /// In en, this message translates to:
  /// **'What the button starts'**
  String get runModeHint;

  /// No description provided for @moreSettings.
  ///
  /// In en, this message translates to:
  /// **'More…'**
  String get moreSettings;

  /// No description provided for @timer.
  ///
  /// In en, this message translates to:
  /// **'Timer'**
  String get timer;

  /// No description provided for @timerOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get timerOff;

  /// No description provided for @secondsUnit.
  ///
  /// In en, this message translates to:
  /// **'sec'**
  String get secondsUnit;

  /// No description provided for @hoursShort.
  ///
  /// In en, this message translates to:
  /// **'h'**
  String get hoursShort;

  /// No description provided for @minutesShort.
  ///
  /// In en, this message translates to:
  /// **'min'**
  String get minutesShort;

  /// No description provided for @stageWater.
  ///
  /// In en, this message translates to:
  /// **'Water'**
  String get stageWater;

  /// No description provided for @stagePump.
  ///
  /// In en, this message translates to:
  /// **'Pump'**
  String get stagePump;

  /// No description provided for @stageCup.
  ///
  /// In en, this message translates to:
  /// **'Cup'**
  String get stageCup;

  /// No description provided for @charging.
  ///
  /// In en, this message translates to:
  /// **'charging'**
  String get charging;

  /// No description provided for @ctaStart.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get ctaStart;

  /// No description provided for @ctaStop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get ctaStop;

  /// No description provided for @stepWetting.
  ///
  /// In en, this message translates to:
  /// **'Wetting'**
  String get stepWetting;

  /// No description provided for @stepPour.
  ///
  /// In en, this message translates to:
  /// **'Pour'**
  String get stepPour;

  /// No description provided for @presetsByRoast.
  ///
  /// In en, this message translates to:
  /// **'Presets by bean roast'**
  String get presetsByRoast;

  /// No description provided for @roastLightShort.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get roastLightShort;

  /// No description provided for @roastMediumShort.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get roastMediumShort;

  /// No description provided for @roastDarkShort.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get roastDarkShort;

  /// No description provided for @pauseAfter.
  ///
  /// In en, this message translates to:
  /// **'Pause after'**
  String get pauseAfter;

  /// No description provided for @pourTimeout.
  ///
  /// In en, this message translates to:
  /// **'Pour timeout'**
  String get pourTimeout;

  /// No description provided for @scheduleHint.
  ///
  /// In en, this message translates to:
  /// **'The machine starts the selected cycle at this time.'**
  String get scheduleHint;

  /// No description provided for @minutesShift.
  ///
  /// In en, this message translates to:
  /// **'{value} min'**
  String minutesShift(String value);

  /// No description provided for @searchNearby.
  ///
  /// In en, this message translates to:
  /// **'Looking for devices nearby…'**
  String get searchNearby;

  /// No description provided for @deviceConnected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get deviceConnected;

  /// No description provided for @firmware.
  ///
  /// In en, this message translates to:
  /// **'Firmware'**
  String get firmware;

  /// No description provided for @statPoursWeek.
  ///
  /// In en, this message translates to:
  /// **'In 7 days'**
  String get statPoursWeek;

  /// No description provided for @stepNoWater.
  ///
  /// In en, this message translates to:
  /// **'No water'**
  String get stepNoWater;

  /// No description provided for @stepHeatError.
  ///
  /// In en, this message translates to:
  /// **'Heater fault'**
  String get stepHeatError;

  /// No description provided for @stepWater.
  ///
  /// In en, this message translates to:
  /// **'Water'**
  String get stepWater;

  /// No description provided for @stepAlarm.
  ///
  /// In en, this message translates to:
  /// **'Timer'**
  String get stepAlarm;

  /// No description provided for @stepPause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get stepPause;

  /// No description provided for @cancelAlarm.
  ///
  /// In en, this message translates to:
  /// **'Cancel scheduled start'**
  String get cancelAlarm;

  /// No description provided for @pressure.
  ///
  /// In en, this message translates to:
  /// **'Pressure'**
  String get pressure;

  /// No description provided for @pressureNote.
  ///
  /// In en, this message translates to:
  /// **'Steps, not bars: the machine reports no pressure back. What actually builds up on the puck is set by the grind.'**
  String get pressureNote;

  /// No description provided for @ctaDone.
  ///
  /// In en, this message translates to:
  /// **'Done ✓'**
  String get ctaDone;

  /// No description provided for @modeHeatDesc.
  ///
  /// In en, this message translates to:
  /// **'water heating only, up to the set temperature'**
  String get modeHeatDesc;

  /// No description provided for @modeHeatAndBrewDesc.
  ///
  /// In en, this message translates to:
  /// **'heats the water first, then brews'**
  String get modeHeatAndBrewDesc;

  /// No description provided for @modeBrewDesc.
  ///
  /// In en, this message translates to:
  /// **'pour without heating the water'**
  String get modeBrewDesc;

  /// No description provided for @pourTimeTitle.
  ///
  /// In en, this message translates to:
  /// **'Pour time'**
  String get pourTimeTitle;

  /// No description provided for @pourSkipNote.
  ///
  /// In en, this message translates to:
  /// **'A step set to 0 s is skipped.'**
  String get pourSkipNote;

  /// No description provided for @descWetting.
  ///
  /// In en, this message translates to:
  /// **'water wets the coffee puck'**
  String get descWetting;

  /// No description provided for @descPause.
  ///
  /// In en, this message translates to:
  /// **'the coffee swells before the pour'**
  String get descPause;

  /// No description provided for @descExtraction.
  ///
  /// In en, this message translates to:
  /// **'the main pour into the cup'**
  String get descExtraction;

  /// No description provided for @descFlow.
  ///
  /// In en, this message translates to:
  /// **'step 1–15, water delivery rate'**
  String get descFlow;

  /// No description provided for @capTimer.
  ///
  /// In en, this message translates to:
  /// **'TIMER'**
  String get capTimer;

  /// No description provided for @capMode.
  ///
  /// In en, this message translates to:
  /// **'MODE'**
  String get capMode;

  /// No description provided for @stepOf.
  ///
  /// In en, this message translates to:
  /// **'{value} / {max}'**
  String stepOf(int value, int max);

  /// No description provided for @modeHeatShort.
  ///
  /// In en, this message translates to:
  /// **'Heat'**
  String get modeHeatShort;

  /// No description provided for @modeFullShort.
  ///
  /// In en, this message translates to:
  /// **'Full'**
  String get modeFullShort;

  /// No description provided for @modeBrewShort.
  ///
  /// In en, this message translates to:
  /// **'Brew'**
  String get modeBrewShort;

  /// No description provided for @descTemperature.
  ///
  /// In en, this message translates to:
  /// **'water temperature'**
  String get descTemperature;

  /// No description provided for @asleep.
  ///
  /// In en, this message translates to:
  /// **'asleep'**
  String get asleep;

  /// No description provided for @devices.
  ///
  /// In en, this message translates to:
  /// **'Devices'**
  String get devices;

  /// No description provided for @myDevices.
  ///
  /// In en, this message translates to:
  /// **'My devices'**
  String get myDevices;

  /// No description provided for @notInRange.
  ///
  /// In en, this message translates to:
  /// **'Not in range'**
  String get notInRange;

  /// No description provided for @tapToConnect.
  ///
  /// In en, this message translates to:
  /// **'Tap to connect'**
  String get tapToConnect;

  /// No description provided for @forgetDevice.
  ///
  /// In en, this message translates to:
  /// **'Forget device'**
  String get forgetDevice;

  /// No description provided for @forget.
  ///
  /// In en, this message translates to:
  /// **'Forget'**
  String get forget;

  /// No description provided for @forgetDeviceQuestion.
  ///
  /// In en, this message translates to:
  /// **'Forget {name}?'**
  String forgetDeviceQuestion(String name);

  /// No description provided for @forgetDeviceBody.
  ///
  /// In en, this message translates to:
  /// **'The machine will leave the list. You can add it again from the search.'**
  String get forgetDeviceBody;

  /// No description provided for @machines.
  ///
  /// In en, this message translates to:
  /// **'Machines'**
  String get machines;

  /// No description provided for @deviceAvailable.
  ///
  /// In en, this message translates to:
  /// **'Available'**
  String get deviceAvailable;

  /// No description provided for @scheduleToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get scheduleToday;

  /// No description provided for @scheduleTomorrow.
  ///
  /// In en, this message translates to:
  /// **'Tomorrow'**
  String get scheduleTomorrow;

  /// No description provided for @scheduleStarts.
  ///
  /// In en, this message translates to:
  /// **'{day} at {time}, the machine will start: {mode}.'**
  String scheduleStarts(String day, String time, String mode);

  /// No description provided for @confirmScheduledStart.
  ///
  /// In en, this message translates to:
  /// **'Enable scheduled start?'**
  String get confirmScheduledStart;

  /// No description provided for @scheduledStartWarning.
  ///
  /// In en, this message translates to:
  /// **'The machine will start unattended. Make sure it is upright, filled with water, and ready to run.'**
  String get scheduledStartWarning;

  /// No description provided for @enable.
  ///
  /// In en, this message translates to:
  /// **'Enable'**
  String get enable;

  /// No description provided for @slideToStart.
  ///
  /// In en, this message translates to:
  /// **'Slide to start'**
  String get slideToStart;

  /// No description provided for @slideToStop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get slideToStop;

  /// No description provided for @holdToStart.
  ///
  /// In en, this message translates to:
  /// **'Hold to start'**
  String get holdToStart;

  /// No description provided for @startMode.
  ///
  /// In en, this message translates to:
  /// **'Start · {mode}'**
  String startMode(String mode);

  /// No description provided for @lowBatteryStartTitle.
  ///
  /// In en, this message translates to:
  /// **'Low battery'**
  String get lowBatteryStartTitle;

  /// No description provided for @lowBatteryStartBody.
  ///
  /// In en, this message translates to:
  /// **'The battery may not complete the heating cycle. Continue anyway?'**
  String get lowBatteryStartBody;

  /// No description provided for @startAnyway.
  ///
  /// In en, this message translates to:
  /// **'Start anyway'**
  String get startAnyway;

  /// No description provided for @faultAddWater.
  ///
  /// In en, this message translates to:
  /// **'Add water'**
  String get faultAddWater;

  /// No description provided for @faultCoolDown.
  ///
  /// In en, this message translates to:
  /// **'Let it cool down'**
  String get faultCoolDown;

  /// No description provided for @faultService.
  ///
  /// In en, this message translates to:
  /// **'Service required'**
  String get faultService;

  /// No description provided for @faultCharge.
  ///
  /// In en, this message translates to:
  /// **'Charge the machine'**
  String get faultCharge;

  /// No description provided for @checkAgain.
  ///
  /// In en, this message translates to:
  /// **'Check again'**
  String get checkAgain;

  /// No description provided for @secondsRemaining.
  ///
  /// In en, this message translates to:
  /// **'{value} s left'**
  String secondsRemaining(int value);

  /// No description provided for @secondsOf.
  ///
  /// In en, this message translates to:
  /// **'{value}/{total} s'**
  String secondsOf(int value, int total);

  /// No description provided for @temperatureProgress.
  ///
  /// In en, this message translates to:
  /// **'{current} → {target}{unit}'**
  String temperatureProgress(int current, int target, String unit);

  /// No description provided for @temperatureUnit.
  ///
  /// In en, this message translates to:
  /// **'Temperature unit'**
  String get temperatureUnit;

  /// No description provided for @sectionOverview.
  ///
  /// In en, this message translates to:
  /// **'Overview'**
  String get sectionOverview;

  /// No description provided for @sectionApp.
  ///
  /// In en, this message translates to:
  /// **'App'**
  String get sectionApp;

  /// No description provided for @openDeviceSettings.
  ///
  /// In en, this message translates to:
  /// **'Machine settings'**
  String get openDeviceSettings;

  /// No description provided for @openDevices.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth devices'**
  String get openDevices;

  /// No description provided for @increase.
  ///
  /// In en, this message translates to:
  /// **'Increase'**
  String get increase;

  /// No description provided for @decrease.
  ///
  /// In en, this message translates to:
  /// **'Decrease'**
  String get decrease;

  /// No description provided for @connectDevice.
  ///
  /// In en, this message translates to:
  /// **'Connect a machine'**
  String get connectDevice;

  /// No description provided for @welcomeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Connect your K2 Pro over Bluetooth — or see how it all works without the hardware.'**
  String get welcomeSubtitle;

  /// No description provided for @demoBadge.
  ///
  /// In en, this message translates to:
  /// **'DEMO'**
  String get demoBadge;

  /// No description provided for @demoTitle.
  ///
  /// In en, this message translates to:
  /// **'Demo mode'**
  String get demoTitle;

  /// No description provided for @demoStart.
  ///
  /// In en, this message translates to:
  /// **'Try the demo'**
  String get demoStart;

  /// No description provided for @demoAbout.
  ///
  /// In en, this message translates to:
  /// **'Simulated machine and scale'**
  String get demoAbout;

  /// No description provided for @demoSection.
  ///
  /// In en, this message translates to:
  /// **'Demo'**
  String get demoSection;

  /// No description provided for @stepWeight.
  ///
  /// In en, this message translates to:
  /// **'Weight'**
  String get stepWeight;

  /// No description provided for @weightTitle.
  ///
  /// In en, this message translates to:
  /// **'Scale'**
  String get weightTitle;

  /// No description provided for @weightTare.
  ///
  /// In en, this message translates to:
  /// **'Tare'**
  String get weightTare;

  /// No description provided for @weightStopByWeight.
  ///
  /// In en, this message translates to:
  /// **'Stop by weight'**
  String get weightStopByWeight;

  /// No description provided for @weightStopByWeightHint.
  ///
  /// In en, this message translates to:
  /// **'The pour ends at the target weight. Seconds become a safety limit.'**
  String get weightStopByWeightHint;

  /// No description provided for @weightByTime.
  ///
  /// In en, this message translates to:
  /// **'By time'**
  String get weightByTime;

  /// No description provided for @weightByWeight.
  ///
  /// In en, this message translates to:
  /// **'By weight'**
  String get weightByWeight;

  /// No description provided for @weightTarget.
  ///
  /// In en, this message translates to:
  /// **'Target'**
  String get weightTarget;

  /// No description provided for @weightDose.
  ///
  /// In en, this message translates to:
  /// **'Dose'**
  String get weightDose;

  /// No description provided for @weightTakeCurrent.
  ///
  /// In en, this message translates to:
  /// **'Weigh the dose'**
  String get weightTakeCurrent;

  /// No description provided for @weightRatio.
  ///
  /// In en, this message translates to:
  /// **'Ratio 1:{value}'**
  String weightRatio(String value);

  /// No description provided for @weightNoDose.
  ///
  /// In en, this message translates to:
  /// **'not weighed'**
  String get weightNoDose;

  /// No description provided for @weightLimit.
  ///
  /// In en, this message translates to:
  /// **'Limit'**
  String get weightLimit;

  /// No description provided for @weightLimitHint.
  ///
  /// In en, this message translates to:
  /// **'The machine will stop here even if the target is not reached.'**
  String get weightLimitHint;

  /// No description provided for @weightOf.
  ///
  /// In en, this message translates to:
  /// **'{value} → {total} g'**
  String weightOf(String value, String total);

  /// No description provided for @weightGrams.
  ///
  /// In en, this message translates to:
  /// **'{value} g'**
  String weightGrams(String value);

  /// No description provided for @gramsUnit.
  ///
  /// In en, this message translates to:
  /// **'g'**
  String get gramsUnit;

  /// No description provided for @weightSettling.
  ///
  /// In en, this message translates to:
  /// **'Settling'**
  String get weightSettling;

  /// No description provided for @weightStoppedByTime.
  ///
  /// In en, this message translates to:
  /// **'Stopped by time, {value} of {total} g'**
  String weightStoppedByTime(String value, String total);

  /// No description provided for @weightScaleLost.
  ///
  /// In en, this message translates to:
  /// **'Scale lost — finishing on time'**
  String get weightScaleLost;

  /// No description provided for @weightNotConnected.
  ///
  /// In en, this message translates to:
  /// **'No scale'**
  String get weightNotConnected;

  /// No description provided for @weightConnect.
  ///
  /// In en, this message translates to:
  /// **'Connect a scale to weigh and to stop the pour by weight.'**
  String get weightConnect;

  /// No description provided for @weightJournal.
  ///
  /// In en, this message translates to:
  /// **'Pour log'**
  String get weightJournal;

  /// No description provided for @weightJournalEmpty.
  ///
  /// In en, this message translates to:
  /// **'No pours yet'**
  String get weightJournalEmpty;

  /// No description provided for @weightJournalClear.
  ///
  /// In en, this message translates to:
  /// **'Clear log'**
  String get weightJournalClear;

  /// No description provided for @weightMissOver.
  ///
  /// In en, this message translates to:
  /// **'+{value} g'**
  String weightMissOver(String value);

  /// No description provided for @weightMissUnder.
  ///
  /// In en, this message translates to:
  /// **'{value} g'**
  String weightMissUnder(String value);

  /// No description provided for @reasonWeight.
  ///
  /// In en, this message translates to:
  /// **'by weight'**
  String get reasonWeight;

  /// No description provided for @reasonTimeout.
  ///
  /// In en, this message translates to:
  /// **'by time'**
  String get reasonTimeout;

  /// No description provided for @reasonManual.
  ///
  /// In en, this message translates to:
  /// **'by hand'**
  String get reasonManual;

  /// No description provided for @reasonLinkLost.
  ///
  /// In en, this message translates to:
  /// **'link lost'**
  String get reasonLinkLost;

  /// No description provided for @scaleBattery.
  ///
  /// In en, this message translates to:
  /// **'{value}%'**
  String scaleBattery(int value);

  /// No description provided for @scaleAsleep.
  ///
  /// In en, this message translates to:
  /// **'asleep'**
  String get scaleAsleep;

  /// No description provided for @journalAccuracy.
  ///
  /// In en, this message translates to:
  /// **'Accuracy'**
  String get journalAccuracy;

  /// No description provided for @journalPours.
  ///
  /// In en, this message translates to:
  /// **'Pours'**
  String get journalPours;

  /// No description provided for @journalCount.
  ///
  /// In en, this message translates to:
  /// **'Pours'**
  String get journalCount;

  /// No description provided for @journalAvgMiss.
  ///
  /// In en, this message translates to:
  /// **'Avg miss'**
  String get journalAvgMiss;

  /// No description provided for @journalAvgTime.
  ///
  /// In en, this message translates to:
  /// **'Avg time'**
  String get journalAvgTime;

  /// No description provided for @descYield.
  ///
  /// In en, this message translates to:
  /// **'How much should end up in the cup. The pour stops here.'**
  String get descYield;

  /// No description provided for @journalTiming.
  ///
  /// In en, this message translates to:
  /// **'Shot time'**
  String get journalTiming;

  /// No description provided for @journalTimingHint.
  ///
  /// In en, this message translates to:
  /// **'At the same dose and target, steady time means a steady grind.'**
  String get journalTimingHint;

  /// No description provided for @weightOnScale.
  ///
  /// In en, this message translates to:
  /// **'{value} g on the scale'**
  String weightOnScale(String value);

  /// No description provided for @journalStats.
  ///
  /// In en, this message translates to:
  /// **'Statistics'**
  String get journalStats;

  /// No description provided for @shotNoCurve.
  ///
  /// In en, this message translates to:
  /// **'No graph for this pour — there was no scale connected.'**
  String get shotNoCurve;

  /// No description provided for @shotParams.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get shotParams;

  /// No description provided for @shotYield.
  ///
  /// In en, this message translates to:
  /// **'In the cup'**
  String get shotYield;

  /// No description provided for @shotRatio.
  ///
  /// In en, this message translates to:
  /// **'Ratio'**
  String get shotRatio;

  /// No description provided for @shotTime.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get shotTime;

  /// No description provided for @shotEnded.
  ///
  /// In en, this message translates to:
  /// **'Ended'**
  String get shotEnded;

  /// No description provided for @chartWeight.
  ///
  /// In en, this message translates to:
  /// **'Weight'**
  String get chartWeight;

  /// No description provided for @chartFlow.
  ///
  /// In en, this message translates to:
  /// **'Flow'**
  String get chartFlow;

  /// No description provided for @chartTemperature.
  ///
  /// In en, this message translates to:
  /// **'Temperature'**
  String get chartTemperature;

  /// No description provided for @today.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get today;

  /// No description provided for @timerReadyIn.
  ///
  /// In en, this message translates to:
  /// **'Ready in'**
  String get timerReadyIn;

  /// No description provided for @timerReadyHint.
  ///
  /// In en, this message translates to:
  /// **'The machine starts early so the coffee is ready right on time.'**
  String get timerReadyHint;

  /// No description provided for @timerStartAt.
  ///
  /// In en, this message translates to:
  /// **'Starts at {time}'**
  String timerStartAt(String time);

  /// No description provided for @timerByTime.
  ///
  /// In en, this message translates to:
  /// **'At a set time'**
  String get timerByTime;

  /// No description provided for @timerSchedule.
  ///
  /// In en, this message translates to:
  /// **'Schedule'**
  String get timerSchedule;

  /// No description provided for @adviceAfterShot.
  ///
  /// In en, this message translates to:
  /// **'Advice after each shot'**
  String get adviceAfterShot;

  /// No description provided for @brewAdvice.
  ///
  /// In en, this message translates to:
  /// **'Brewing tips'**
  String get brewAdvice;

  /// No description provided for @adviceHeadline.
  ///
  /// In en, this message translates to:
  /// **'How did it turn out?'**
  String get adviceHeadline;

  /// No description provided for @adviceBannerBody.
  ///
  /// In en, this message translates to:
  /// **'Tune the recipe to taste'**
  String get adviceBannerBody;

  /// No description provided for @adviceTune.
  ///
  /// In en, this message translates to:
  /// **'Tune'**
  String get adviceTune;

  /// No description provided for @adviceTasteTitle.
  ///
  /// In en, this message translates to:
  /// **'Taste'**
  String get adviceTasteTitle;

  /// No description provided for @adviceBodyTitle.
  ///
  /// In en, this message translates to:
  /// **'Body'**
  String get adviceBodyTitle;

  /// No description provided for @tasteSour.
  ///
  /// In en, this message translates to:
  /// **'Sour'**
  String get tasteSour;

  /// No description provided for @tasteSalty.
  ///
  /// In en, this message translates to:
  /// **'Salty'**
  String get tasteSalty;

  /// No description provided for @tasteEmpty.
  ///
  /// In en, this message translates to:
  /// **'Watery'**
  String get tasteEmpty;

  /// No description provided for @tasteSweet.
  ///
  /// In en, this message translates to:
  /// **'Sweet'**
  String get tasteSweet;

  /// No description provided for @tasteBitter.
  ///
  /// In en, this message translates to:
  /// **'Bitter'**
  String get tasteBitter;

  /// No description provided for @bodyThin.
  ///
  /// In en, this message translates to:
  /// **'Thin'**
  String get bodyThin;

  /// No description provided for @bodyFull.
  ///
  /// In en, this message translates to:
  /// **'Full'**
  String get bodyFull;

  /// No description provided for @adviceWhySour.
  ///
  /// In en, this message translates to:
  /// **'Sour — under-extracted: the water ran through too fast.'**
  String get adviceWhySour;

  /// No description provided for @adviceWhySalty.
  ///
  /// In en, this message translates to:
  /// **'Salty — extraction cut off too early.'**
  String get adviceWhySalty;

  /// No description provided for @adviceWhyBitter.
  ///
  /// In en, this message translates to:
  /// **'Bitter — over-extracted: the water ran too long.'**
  String get adviceWhyBitter;

  /// No description provided for @adviceWhyEmpty.
  ///
  /// In en, this message translates to:
  /// **'Watery — weak: too little coffee for the water.'**
  String get adviceWhyEmpty;

  /// No description provided for @adviceWhySweet.
  ///
  /// In en, this message translates to:
  /// **'Sweet and balanced — right on point.'**
  String get adviceWhySweet;

  /// No description provided for @adviceWhyThin.
  ///
  /// In en, this message translates to:
  /// **'Thin — lacks density.'**
  String get adviceWhyThin;

  /// No description provided for @adviceControls.
  ///
  /// In en, this message translates to:
  /// **'What to do'**
  String get adviceControls;

  /// No description provided for @advicePick.
  ///
  /// In en, this message translates to:
  /// **'Pick taste and body — I\'ll suggest what to adjust.'**
  String get advicePick;

  /// No description provided for @adviceNoChange.
  ///
  /// In en, this message translates to:
  /// **'Nothing to change.'**
  String get adviceNoChange;

  /// No description provided for @adviceRatioHint.
  ///
  /// In en, this message translates to:
  /// **'Tighten the ratio in the scale dialog.'**
  String get adviceRatioHint;

  /// No description provided for @tasteAstringent.
  ///
  /// In en, this message translates to:
  /// **'Astringent'**
  String get tasteAstringent;

  /// No description provided for @adviceWhyAstringent.
  ///
  /// In en, this message translates to:
  /// **'Astringent — over-extracted, a parched puck.'**
  String get adviceWhyAstringent;

  /// No description provided for @fixGrindFiner.
  ///
  /// In en, this message translates to:
  /// **'Grind finer'**
  String get fixGrindFiner;

  /// No description provided for @fixGrindCoarser.
  ///
  /// In en, this message translates to:
  /// **'Grind coarser'**
  String get fixGrindCoarser;

  /// No description provided for @fixDoseMore.
  ///
  /// In en, this message translates to:
  /// **'More coffee'**
  String get fixDoseMore;

  /// No description provided for @fixRatioShorter.
  ///
  /// In en, this message translates to:
  /// **'Shorter yield'**
  String get fixRatioShorter;

  /// No description provided for @fixGrindFinerWhy.
  ///
  /// In en, this message translates to:
  /// **'The main lever: finer grind slows the water — more extraction.'**
  String get fixGrindFinerWhy;

  /// No description provided for @fixGrindCoarserWhy.
  ///
  /// In en, this message translates to:
  /// **'The main lever: coarser grind speeds the water — less extraction.'**
  String get fixGrindCoarserWhy;

  /// No description provided for @fixDoseMoreWhy.
  ///
  /// In en, this message translates to:
  /// **'Add more grounds — a denser, stronger cup.'**
  String get fixDoseMoreWhy;

  /// No description provided for @fixRatioShorterWhy.
  ///
  /// In en, this message translates to:
  /// **'Lower the scale target — less water, a denser cup.'**
  String get fixRatioShorterWhy;

  /// No description provided for @fixTempUpWhy.
  ///
  /// In en, this message translates to:
  /// **'If the grind is dialed in — raise the temperature a degree or two.'**
  String get fixTempUpWhy;

  /// No description provided for @fixTempDownWhy.
  ///
  /// In en, this message translates to:
  /// **'If the grind is dialed in — lower the temperature a degree or two.'**
  String get fixTempDownWhy;

  /// No description provided for @adviceLastResort.
  ///
  /// In en, this message translates to:
  /// **'Last resort'**
  String get adviceLastResort;

  /// No description provided for @adviceScaleOff.
  ///
  /// In en, this message translates to:
  /// **'Connect a scale to control the yield.'**
  String get adviceScaleOff;
}

class _AppL10nDelegate extends LocalizationsDelegate<AppL10n> {
  const _AppL10nDelegate();

  @override
  Future<AppL10n> load(Locale locale) {
    return SynchronousFuture<AppL10n>(lookupAppL10n(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ru'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppL10nDelegate old) => false;
}

AppL10n lookupAppL10n(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppL10nEn();
    case 'ru':
      return AppL10nRu();
  }

  throw FlutterError(
    'AppL10n.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
