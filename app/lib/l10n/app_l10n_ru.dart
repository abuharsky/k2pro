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
  String get timer => 'Таймер';

  @override
  String get timerOff => 'Выкл';

  @override
  String get secondsUnit => 'сек';

  @override
  String get hoursShort => 'ч';

  @override
  String get minutesShort => 'мин';

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
  String get stepAlarm => 'Таймер';

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
  String get slideToStop => 'Остановить';

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
    return '$current → $target$unit';
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

  @override
  String get connectDevice => 'Подключить машину';

  @override
  String get welcomeSubtitle =>
      'Подключите K2 Pro по Bluetooth — или посмотрите, как всё устроено, без железа.';

  @override
  String get demoBadge => 'ДЕМО';

  @override
  String get demoTitle => 'Демо-режим';

  @override
  String get demoStart => 'Посмотреть демо';

  @override
  String get demoAbout => 'Симулятор машины и весов';

  @override
  String get demoSection => 'Демо';

  @override
  String get stepWeight => 'Вес';

  @override
  String get weightTitle => 'Весы';

  @override
  String get weightTare => 'Тара';

  @override
  String get weightStopByWeight => 'Отсечка по весу';

  @override
  String get weightStopByWeightHint =>
      'Пролив закончится на заданном весе. Секунды становятся предохранителем.';

  @override
  String get weightByTime => 'По времени';

  @override
  String get weightByWeight => 'По весу';

  @override
  String get weightTarget => 'Цель';

  @override
  String get weightDose => 'Доза';

  @override
  String get weightTakeCurrent => 'Взвесить дозу';

  @override
  String weightRatio(String value) {
    return 'Отношение 1:$value';
  }

  @override
  String get weightNoDose => 'не взвешена';

  @override
  String get weightLimit => 'Предел';

  @override
  String get weightLimitHint =>
      'На этой отметке машина встанет, даже если вес не набрался.';

  @override
  String weightOf(String value, String total) {
    return '$value → $total г';
  }

  @override
  String weightGrams(String value) {
    return '$value г';
  }

  @override
  String get gramsUnit => 'г';

  @override
  String get weightSettling => 'Осадка';

  @override
  String weightStoppedByTime(String value, String total) {
    return 'Остановлено по времени, $value из $total г';
  }

  @override
  String get weightScaleLost => 'Весы пропали — дорабатываю по времени';

  @override
  String get weightNotConnected => 'Весов нет';

  @override
  String get weightConnect =>
      'Подключите весы, чтобы взвешивать и рубить пролив по весу.';

  @override
  String get weightJournal => 'Журнал проливов';

  @override
  String get weightJournalEmpty => 'Проливов ещё не было';

  @override
  String get weightJournalClear => 'Очистить журнал';

  @override
  String weightMissOver(String value) {
    return '+$value г';
  }

  @override
  String weightMissUnder(String value) {
    return '$value г';
  }

  @override
  String get reasonWeight => 'по весу';

  @override
  String get reasonTimeout => 'по времени';

  @override
  String get reasonManual => 'вручную';

  @override
  String get reasonLinkLost => 'связь пропала';

  @override
  String scaleBattery(int value) {
    return '$value%';
  }

  @override
  String get scaleAsleep => 'спят';

  @override
  String get journalAccuracy => 'Точность';

  @override
  String get journalPours => 'Проливы';

  @override
  String get journalCount => 'Проливов';

  @override
  String get journalAvgMiss => 'Средний промах';

  @override
  String get journalAvgTime => 'Среднее время';

  @override
  String get descYield =>
      'Сколько должно оказаться в чашке. На этой отметке пролив закончится.';

  @override
  String get journalTiming => 'Время пролива';

  @override
  String get journalTimingHint =>
      'При одной дозе и одной цели ровное время значит ровный помол.';

  @override
  String weightOnScale(String value) {
    return 'сейчас на весах $value г';
  }

  @override
  String get journalStats => 'Статистика';

  @override
  String get shotNoCurve =>
      'Графика у этого пролива нет — весы не были подключены.';

  @override
  String get shotParams => 'Подробности';

  @override
  String get shotYield => 'В чашке';

  @override
  String get shotRatio => 'Отношение';

  @override
  String get shotTime => 'Время';

  @override
  String get shotEnded => 'Закончился';

  @override
  String get chartWeight => 'Вес';

  @override
  String get chartFlow => 'Поток';

  @override
  String get chartTemperature => 'Температура';

  @override
  String get today => 'Сегодня';

  @override
  String get timerReadyIn => 'Готов через';

  @override
  String get timerReadyHint =>
      'Машина начнёт заранее, чтобы кофе был готов точно к сроку.';

  @override
  String timerStartAt(String time) {
    return 'Старт в $time';
  }

  @override
  String get timerByTime => 'Ко времени';

  @override
  String get timerSchedule => 'Запланировать';

  @override
  String get adviceAfterShot => 'Советы после пролива';

  @override
  String get brewAdvice => 'Советы по приготовлению';

  @override
  String get adviceHeadline => 'Как получилось?';

  @override
  String get adviceBannerBody => 'Подстроим рецепт по вкусу';

  @override
  String get adviceTune => 'Настроить';

  @override
  String get adviceTasteTitle => 'Вкус';

  @override
  String get adviceBodyTitle => 'Тело';

  @override
  String get tasteSour => 'Кислый';

  @override
  String get tasteSalty => 'Солёный';

  @override
  String get tasteEmpty => 'Пустой';

  @override
  String get tasteSweet => 'Сладкий';

  @override
  String get tasteBitter => 'Горький';

  @override
  String get bodyThin => 'Нет тела';

  @override
  String get bodyFull => 'Есть тело';

  @override
  String get adviceWhySour =>
      'Кисло — не хватило экстракции: вода прошла слишком быстро.';

  @override
  String get adviceWhySalty => 'Солёно — экстракция оборвалась рано.';

  @override
  String get adviceWhyBitter =>
      'Горчит — переэкстракция: вода шла слишком долго.';

  @override
  String get adviceWhyEmpty =>
      'Пусто — слабо и водянисто: кофе мало на объём воды.';

  @override
  String get adviceWhySweet => 'Сладко и сбалансированно — в точку.';

  @override
  String get adviceWhyThin => 'Тонко — не хватает плотности.';

  @override
  String get adviceControls => 'Что делать';

  @override
  String get advicePick => 'Отметьте вкус и тело — подскажу, что тронуть.';

  @override
  String get adviceNoChange => 'Ничего менять не нужно.';

  @override
  String get adviceRatioHint => 'Соотношение плотнее — в диалоге весов.';

  @override
  String get tasteAstringent => 'Терпкий';

  @override
  String get adviceWhyAstringent =>
      'Вяжет — переэкстракция и пересушенная таблетка.';

  @override
  String get fixGrindFiner => 'Смолоть мельче';

  @override
  String get fixGrindCoarser => 'Смолоть крупнее';

  @override
  String get fixDoseMore => 'Больше кофе';

  @override
  String get fixRatioShorter => 'Короче выход';

  @override
  String get fixGrindFinerWhy =>
      'Главный рычаг: мельче помол — вода идёт медленнее, экстракции больше.';

  @override
  String get fixGrindCoarserWhy =>
      'Главный рычаг: крупнее помол — вода быстрее, экстракции меньше.';

  @override
  String get fixDoseMoreWhy => 'Добавьте закладку — чашка плотнее и крепче.';

  @override
  String get fixRatioShorterWhy =>
      'Убавьте цель на весах — меньше воды, плотнее чашка.';

  @override
  String get fixTempUpWhy =>
      'Если помол уже настроен — поднимите температуру на градус-два.';

  @override
  String get fixTempDownWhy =>
      'Если помол уже настроен — опустите температуру на градус-два.';

  @override
  String get adviceLastResort => 'В крайнем случае';

  @override
  String get adviceScaleOff => 'Подключите весы, чтобы управлять выходом.';
}
