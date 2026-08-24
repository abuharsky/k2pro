// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_l10n.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppL10nRu extends AppL10n {
  AppL10nRu([String locale = 'ru']) : super(locale);

  @override
  String get appTitle => 'K2 Pro';

  @override
  String get connected => 'На связи';

  @override
  String get connecting => 'Подключение…';

  @override
  String get disconnected => 'Не подключено';

  @override
  String get connect => 'Подключиться';

  @override
  String get disconnect => 'Отключиться';

  @override
  String get notConnected => 'Нет связи';

  @override
  String get reading => 'Читаем…';

  @override
  String get devicesNearby => 'Устройства рядом';

  @override
  String get searching => 'Ищем…';

  @override
  String get search => 'Искать снова';

  @override
  String get showAll => 'Все BLE';

  @override
  String rssi(int value) {
    return '$value дБм';
  }

  @override
  String get stateSleep => 'Сон';

  @override
  String get stateHeating => 'Нагрев';

  @override
  String get stateWaterReady => 'Вода готова';

  @override
  String get stateHeatBrew => 'Нагрев и пролив';

  @override
  String get stateBrewing => 'Пролив';

  @override
  String get stateReady => 'Готово';

  @override
  String get stateError => 'Ошибка';

  @override
  String get phaseHeating => 'Нагрев';

  @override
  String get phasePreInfusion => 'Предсмачивание';

  @override
  String get phaseStandstill => 'Выдержка';

  @override
  String get phaseExtraction => 'Экстракция';

  @override
  String get phaseDone => 'Готово';

  @override
  String seconds(int value) {
    return '$value сек';
  }

  @override
  String get recipe => 'Рецепт';

  @override
  String get recipeMediumDark => 'Средняя обжарка';

  @override
  String get recipeDark => 'Тёмная обжарка';

  @override
  String get recipeLight => 'Светлая обжарка';

  @override
  String get temperature => 'Температура';

  @override
  String get flowSpeed => 'Скорость экстракции';

  @override
  String get preInfusion => 'Предсмачивание';

  @override
  String get standstill => 'Выдержка';

  @override
  String get extraction => 'Экстракция';

  @override
  String get actionStop => 'СТОП';

  @override
  String get actionRun => 'ПУСК';

  @override
  String get runMode => 'Что запускать';

  @override
  String get errDryBurning => 'Нет воды — защита от сухого хода';

  @override
  String get errBatteryOverheating => 'Аккумулятор перегрет, дайте остыть';

  @override
  String get errHeaterShortCircuit => 'Замыкание нагревателя — нужен сервис';

  @override
  String get errLowBatteryHot => 'Заряда не хватит на нагрев';

  @override
  String get errLowBattery => 'Низкий заряд, скоро потребуется зарядка';

  @override
  String get errUnknown => 'Ошибка устройства';

  @override
  String errCode(int code) {
    return 'код $code';
  }

  @override
  String get settings => 'Настройки';

  @override
  String get sectionDevice => 'Устройство';

  @override
  String get sectionStatistics => 'Статистика';

  @override
  String get sectionSchedule => 'Отложенный старт';

  @override
  String get sectionMaintenance => 'Обслуживание';

  @override
  String get deviceNameLabel => 'Имя';

  @override
  String get deviceNameTitle => 'Имя устройства';

  @override
  String get fahrenheit => 'Фаренгейт';

  @override
  String get model => 'Модель';

  @override
  String get versions => 'Версии';

  @override
  String get language => 'Язык';

  @override
  String get languageSystem => 'Системный';

  @override
  String get cupsToday => 'Чашек сегодня';

  @override
  String get lastDays => 'Последние дни';

  @override
  String get refresh => 'Обновить';

  @override
  String get scheduleEnabled => 'Включён';

  @override
  String get scheduleTime => 'Время';

  @override
  String get scheduleMode => 'Режим';

  @override
  String get scheduleSound => 'Звук';

  @override
  String get scheduleTone => 'Сигнал';

  @override
  String get modeHeatAndBrew => 'Нагрев + пролив';

  @override
  String get modeHeat => 'Нагрев';

  @override
  String get modeBrew => 'Пролив';

  @override
  String get toneDingDong => 'Дин-дон';

  @override
  String get toneDiDi => 'Ди-ди';

  @override
  String get toneBuGu => 'Бу-гу';

  @override
  String get toneBiBi => 'Би-би';

  @override
  String get restoreDefaults => 'Сбросить машину к заводским';

  @override
  String get restoreDefaultsQuestion => 'Сбросить настройки?';

  @override
  String get restoreDefaultsBody =>
      'Параметры пролива и заданная температура вернутся к заводским.';

  @override
  String get cancel => 'Отмена';

  @override
  String get save => 'Сохранить';

  @override
  String get reset => 'Сбросить';

  @override
  String get done => 'Готово';

  @override
  String get dash => '—';

  @override
  String get pourTime => 'Пролив';

  @override
  String get sectionBrewParams => 'Параметры пролива';

  @override
  String get tempCell => 'Темп.';

  @override
  String get telemetry => 'Телеметрия 0x00';

  @override
  String get renameDevice => 'Переименовать';

  @override
  String get otherDevice => 'Другая машина…';

  @override
  String get presets => 'Пресеты';

  @override
  String get roastLight => 'Светлая обжарка';

  @override
  String get roastMedium => 'Средняя обжарка';

  @override
  String get roastDark => 'Тёмная обжарка';

  @override
  String get temperatureHint =>
      'Светлой обжарке нужно погорячее, тёмной — попрохладнее.';

  @override
  String limitsRange(String min, String max) {
    return '$min–$max';
  }

  @override
  String get pourTitle => 'Весь пролив';

  @override
  String get extractionNote =>
      'Это полный пролив — дольше машина лить не будет. Поставьте меньше, если нужна короткая порция.';

  @override
  String cycleTotal(int value) {
    return 'Весь цикл $value с';
  }

  @override
  String get runModeHint => 'Что запускает кнопка';

  @override
  String get moreSettings => 'Ещё…';

  @override
  String get timer => 'Запуск по времени';

  @override
  String get timerOff => 'Выкл';

  @override
  String get secondsUnit => 'сек';

  @override
  String get stageWater => 'Вода';

  @override
  String get stagePump => 'Помпа';

  @override
  String get stageCup => 'Чашка';

  @override
  String get charging => 'зарядка';

  @override
  String get ctaStart => 'Старт';

  @override
  String get ctaStop => 'Стоп';

  @override
  String get stepWetting => 'Смачивание';

  @override
  String get stepPour => 'Пролив';

  @override
  String get presetsByRoast => 'Пресеты по типу обжарки зерна';

  @override
  String get roastLightShort => 'Светлая';

  @override
  String get roastMediumShort => 'Средняя';

  @override
  String get roastDarkShort => 'Тёмная';

  @override
  String get pauseAfter => 'Пауза после';

  @override
  String get pourTimeout => 'Тайм-аут пролива';

  @override
  String get scheduleHint => 'В это время машина начнёт выбранный цикл.';

  @override
  String minutesShift(String value) {
    return '$value мин';
  }

  @override
  String get searchNearby => 'Поиск устройств поблизости…';

  @override
  String get deviceConnected => 'Подключено';

  @override
  String get firmware => 'Прошивка';

  @override
  String get statPoursWeek => 'За 7 дней';

  @override
  String get stepNoWater => 'Нет воды';

  @override
  String get stepHeatError => 'Ошибка нагрева';

  @override
  String get stepWater => 'Вода';

  @override
  String get stepAlarm => 'Запуск';

  @override
  String get stepPause => 'Пауза';

  @override
  String get cancelAlarm => 'Отменить запуск';

  @override
  String get pressure => 'Давление';

  @override
  String get pressureNote =>
      'Ступени, а не бары: обратной связи по давлению машина не даёт. Сколько его наберётся на таблетке, решает помол.';

  @override
  String get ctaDone => 'Готово ✓';

  @override
  String get modeHeatDesc => 'только нагрев воды до заданной температуры';

  @override
  String get modeHeatAndBrewDesc => 'сначала нагрев воды, затем пролив';

  @override
  String get modeBrewDesc => 'пролив без нагрева воды';

  @override
  String get pourTimeTitle => 'Время пролива';

  @override
  String get pourSkipNote => 'Шаг, выставленный в 0 с, пропускается.';

  @override
  String get descWetting => 'вода смачивает таблетку кофе';

  @override
  String get descPause => 'кофе набухает перед проливом';

  @override
  String get descExtraction => 'основной пролив в чашку';

  @override
  String get descFlow => 'ступень 1–15, скорость подачи воды';

  @override
  String get capTimer => 'ТАЙМЕР';

  @override
  String get capMode => 'РЕЖИМ';

  @override
  String stepOf(int value, int max) {
    return '$value / $max';
  }

  @override
  String get modeHeatShort => 'Нагрев';

  @override
  String get modeFullShort => 'Полный';

  @override
  String get modeBrewShort => 'Пролив';

  @override
  String get descTemperature => 'температура воды';

  @override
  String get asleep => 'спит';

  @override
  String get devices => 'Устройства';

  @override
  String get myDevices => 'Мои устройства';

  @override
  String get notInRange => 'Не в эфире';

  @override
  String get tapToConnect => 'Нажмите, чтобы подключиться';

  @override
  String get forgetDevice => 'Забыть устройство';

  @override
  String get forget => 'Забыть';

  @override
  String forgetDeviceQuestion(String name) {
    return 'Забыть $name?';
  }

  @override
  String get forgetDeviceBody =>
      'Машина пропадёт из списка. Добавить её снова можно через поиск.';

  @override
  String get machines => 'Машины';

  @override
  String get deviceAvailable => 'Доступна';

  @override
  String get scheduleToday => 'Сегодня';

  @override
  String get scheduleTomorrow => 'Завтра';

  @override
  String scheduleStarts(String day, String time, String mode) {
    return '$day, в $time машина запустит режим «$mode».';
  }

  @override
  String get confirmScheduledStart => 'Включить запуск по времени?';

  @override
  String get scheduledStartWarning =>
      'Машина запустится без вашего участия. Убедитесь, что она стоит вертикально, заполнена водой и готова к работе.';

  @override
  String get enable => 'Включить';

  @override
  String get slideToStart => 'Проведите для запуска';

  @override
  String get holdToStart => 'Удерживайте для запуска';

  @override
  String startMode(String mode) {
    return 'Старт · $mode';
  }

  @override
  String get lowBatteryStartTitle => 'Низкий заряд';

  @override
  String get lowBatteryStartBody =>
      'Заряда может не хватить на полный нагрев. Всё равно продолжить?';

  @override
  String get startAnyway => 'Всё равно запустить';

  @override
  String get faultAddWater => 'Добавьте воду';

  @override
  String get faultCoolDown => 'Дайте машине остыть';

  @override
  String get faultService => 'Нужен сервис';

  @override
  String get faultCharge => 'Зарядите машину';

  @override
  String get checkAgain => 'Проверить';

  @override
  String secondsRemaining(int value) {
    return 'осталось $value с';
  }

  @override
  String secondsOf(int value, int total) {
    return '$value/$total с';
  }

  @override
  String temperatureProgress(int current, int target, String unit) {
    return '$current/$target$unit';
  }

  @override
  String get temperatureUnit => 'Единицы температуры';

  @override
  String get sectionOverview => 'Обзор';

  @override
  String get sectionApp => 'Приложение';

  @override
  String get openDeviceSettings => 'Настройки машины';

  @override
  String get openDevices => 'Устройства Bluetooth';

  @override
  String get increase => 'Увеличить';

  @override
  String get decrease => 'Уменьшить';
}
