/// Кодек BLE-протокола кофемашины K2 Pro (Timeyaa PCM03).
///
/// Чистый Dart без Flutter — можно тестировать отдельно.
/// Описание формата: docs/happygo-ble-protocol.md
library;

import 'dart:typed_data';

// ---------------------------------------------------------------------------
// GATT
// ---------------------------------------------------------------------------

const String kServiceUuid = '0000fff0-0000-1000-8000-00805f9b34fb';
const String kWriteUuid =
    '0000fff2-0000-1000-8000-00805f9b34fb'; // write w/o resp
const String kNotifyUuid = '0000fff1-0000-1000-8000-00805f9b34fb'; // notify

const String kNamePrefix = 'BL_PCM03';

/// Все префиксы имён, по которым оригинальное приложение узнаёт свои машины.
const List<String> kNamePrefixes = ['BL_PCM03', 'SmartMug', 'Hi-t-1'];
const int kRequestMtu = 105;

/// Оригинал выдерживает 40 мс между командами рукопожатия.
const Duration kMinWriteInterval = Duration(milliseconds: 40);

/// И 300 мс после setNotifyValue, прежде чем слать первую команду.
const Duration kHandshakeDelay = Duration(milliseconds: 300);

/// Пауза, после которой уставку можно считать выбранной, а не проезжаемой.
/// Пока крутят колесо, каждый шаг — это отдельная запись в машину: в живом
/// логе за шесть секунд ушло двенадцать кадров 0x23, и все двенадцать
/// промежуточных состояний машина приняла всерьёз.
const Duration kSettingsDebounce = Duration(milliseconds: 400);

/// Сколько ждать цикла после срабатывания будильника, прежде чем идти
/// проверять флаг. Машина стартует не мгновенно: в живом логе между временем
/// уставки и началом работы прошло семь секунд.
const Duration kScheduleGrace = Duration(seconds: 60);

/// Сколько молчания считать сном.
///
/// Телеметрию 0x00 машина шлёт сама раз в 1.02 с и безусловно — пока кадры
/// идут, она жива. В дежурном режиме (индикаторы погашены) BLE-соединение
/// остаётся, а кадров нет вовсе: за всё рукопожатие не приходит ни одного
/// ответа на семь команд.
///
/// Порог взят выше любой наблюдавшейся паузы: на 82797 кадрах в 36 живых
/// сессиях максимальный разрыв — 3.54 с, дольше трёх секунд молчания было
/// дважды, дольше четырёх — ни разу.
const Duration kTelemetrySilence = Duration(seconds: 5);

/// Сколько ждать ответа на первую попытку.
///
/// По 427 парам «запрос-ответ» из живой трассы: медиана 89 мс, p95 — 209 мс,
/// p99 — 239 мс, и ни одна команда, кроме 0x02, не отвечала дольше 260 мс.
/// То есть штатный ответ укладывается в четверть секунды, а полный таймаут
/// в четыре секунды — это в пятнадцать раз больше p99. Кадр, которого нет,
/// не появится: ждать его полный срок значит просто стоять.
///
/// Раньше здесь было сказано, что кадры теряются от столкновения с тиком
/// телеметрии. Это не подтвердилось: из 26 потерь 22 случились раньше, чем
/// машина прислала первый кадр телеметрии вообще, а фаза остальных четырёх
/// ничем не выделяется. Настоящая причина — обычная потеря в эфире, и лечится
/// она быстрым повтором, а не выбором момента.
const Duration kFirstTryTimeout = Duration(milliseconds: 600);

/// Потолок ожидания. Каждая следующая попытка ждёт вдвое дольше предыдущей,
/// но не дольше этого: команда, на которую машина отвечает медленно, всё-таки
/// должна успеть, а серия молчаний не должна складываться в десяток секунд.
const Duration kMaxTryTimeout = Duration(seconds: 4);

/// Сколько ждать ответа на [attempt]-й попытке из [tries], не дольше [cap].
///
/// Лесенка: 0.6 с, 1.2 с, 2.4 с… Одиночная попытка ждёт весь срок — повторять
/// всё равно некому, и обрывать её раньше значит просто потерять ответ.
Duration retryTimeout(int attempt, int tries, [Duration cap = kMaxTryTimeout]) {
  // Лесенка одна на все запросы, сколько бы попыток ни было отпущено. Раньше
  // единственной попытке доставался сразу потолок — «повторять всё равно
  // нечем, так подождём подольше». На молчащей машине это стоило четырёх
  // секунд на кадр: в живой трассе форс-запись уставок перед пуском съедала
  // восемь секунд, и кадр пуска уходил на двенадцатой. Ждать дольше первого
  // шага бессмысленно: штатный ответ приходит за 89 мс.
  final us = kFirstTryTimeout.inMicroseconds << (attempt - 1);
  return Duration(microseconds: us.clamp(0, cap.inMicroseconds));
}

/// Пауза перед первой попыткой восстановить оборванную связь.
///
/// Обрыв бывает мгновенным — машину унесли на шаг в сторону и принесли
/// обратно, — и бывает настоящим: её выключили. Первая попытка идёт почти
/// сразу, дальше пауза удваивается до [kReconnectMaxDelay], чтобы выключенная
/// машина не держала радио занятым до вечера.
const Duration kReconnectFirstDelay = Duration(seconds: 2);

/// Потолок паузы между попытками переподключения.
const Duration kReconnectMaxDelay = Duration(seconds: 30);

/// Сколько ждать перед [attempt]-й попыткой переподключения (нумерация с нуля).
Duration reconnectDelay(int attempt) {
  final us = kReconnectFirstDelay.inMicroseconds << attempt;
  return Duration(microseconds: us.clamp(0, kReconnectMaxDelay.inMicroseconds));
}

const int kStartTx = 0x7F; // телефон -> машина
const int kStartRx = 0x7E; // машина -> телефон
const int kHeaderLen = 5;
const int kMaxFrameLen = 0x1000;

// ---------------------------------------------------------------------------
// Команды
// ---------------------------------------------------------------------------

abstract final class Cmd {
  static const int deviceState = 0x00;
  static const int setWorkState = 0x02;
  static const int setTime = 0x04;
  static const int cups = 0x06;
  static const int deviceInfo = 0x08;
  static const int getTempSetting = 0x15;
  static const int setTempSetting = 0x16;
  static const int getWorkParams = 0x17;
  static const int setWorkParams = 0x18;
  static const int todayCups = 0x19;
  static const int reset = 0x20;
  static const int setAppointment = 0x23;

  /// Машина шлёт сама, без запроса. Замечена ровно один раз: за 90 мс до
  /// того, как цикл оборвался раньше уставки, и в баке кончилась вода.
  /// Полезная нагрузка была `01 00`. Одного случая мало для трактовки,
  /// поэтому кадр не толкуем — только фиксируем.
  static const int event = 0x12;
  static const int getAppointment = 0x24;
  static const int enterOta = 0xA0;
}

/// Режим в команде 0x02. Нумерация НЕ совпадает с [ScheduleMode].
enum WorkMode {
  /// Только нагрев воды, без пролива.
  heat(0),

  /// Нагрев и следом экстракция.
  heatAndBrew(1),

  /// Пролив без нагрева.
  brew(2);

  const WorkMode(this.code);
  final int code;
}

/// Режим в командах таймера 0x23/0x24. Нумерация НЕ совпадает с [WorkMode].
enum ScheduleMode {
  heatAndBrew(0),
  heat(1),
  brew(2);

  const ScheduleMode(this.code);
  final int code;

  static ScheduleMode fromCode(int c) =>
      values.firstWhere((e) => e.code == c, orElse: () => heatAndBrew);
}

enum ReminderMode {
  silent(0),
  sound(1);

  const ReminderMode(this.code);
  final int code;

  static ReminderMode fromCode(int c) => c == 1 ? sound : silent;
}

enum BeepSound {
  dingDong(0),
  diDi(1),
  buGu(2),
  biBi(3);

  const BeepSound(this.code);
  final int code;

  static BeepSound fromCode(int c) =>
      values.firstWhere((e) => e.code == c, orElse: () => dingDong);
}

/// Состояние машины, байт 4 ответа 0x00.
enum MachineState {
  standby(0),
  heatBrewing(1),
  heatBrewDone(2),
  brewing(3),
  brewDone(4),
  heating(5),
  heatDone(6);

  const MachineState(this.code);
  final int code;

  static MachineState fromCode(int c) =>
      values.firstWhere((e) => e.code == c, orElse: () => standby);

  /// Машина занята: нельзя менять заданную температуру и параметры.
  bool get isBusy => this == heatBrewing || this == brewing || this == heating;

  /// Цикл завершён — «готово».
  bool get isDone =>
      this == heatBrewDone || this == brewDone || this == heatDone;
}

/// Код ошибки, байт 5 ответа 0x00.
enum MachineError {
  none(0),
  dryBurning(1),
  batteryOverheating(2),
  heaterShortCircuit(3),
  lowBatteryHot(4),
  lowBattery(5),

  /// Машина сообщила код, которого нет в этом списке. Раньше такой код
  /// приравнивался к «ошибки нет» и молча пропадал — а машина в этот момент
  /// пищит и отказывается работать. Показываем как есть; само число едет
  /// рядом в [DeviceStatus.errorCode].
  unknown(-1);

  const MachineError(this.code);
  final int code;

  static MachineError fromCode(int c) =>
      values.firstWhere((e) => e.code == c, orElse: () => unknown);
}

enum FragStatus { none, first, middle, last }

enum ChargeState { notCharging, charging, full }

// ---------------------------------------------------------------------------
// Кадр
// ---------------------------------------------------------------------------

class FrameFormatException implements Exception {
  FrameFormatException(this.message);
  final String message;
  @override
  String toString() => 'FrameFormatException: $message';
}

int frameChecksum(int start, int lenHi, int lenLo, int cmd, List<int> payload) {
  var sum = start + lenHi + lenLo + cmd;
  for (final b in payload) {
    sum += b;
  }
  return sum & 0xFF;
}

/// Собрать кадр телефон -> машина.
Uint8List buildFrame(int cmd, [List<int> payload = const []]) {
  final total = kHeaderLen + payload.length;
  if (total > 0x3FFF) {
    throw ArgumentError('payload too long');
  }
  final lenHi = (total >> 8) & 0x3F; // frag всегда 0 в нашу сторону
  final lenLo = total & 0xFF;
  final cs = frameChecksum(kStartTx, lenHi, lenLo, cmd, payload);
  return Uint8List.fromList([kStartTx, lenHi, lenLo, cs, cmd, ...payload]);
}

class Frame {
  Frame(this.cmd, this.payload, this.frag);

  final int cmd;
  final Uint8List payload;
  final FragStatus frag;

  @override
  String toString() =>
      'Frame(0x${cmd.toRadixString(16).padLeft(2, '0')}, ${frag.name}, '
      '${payload.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')})';
}

Frame parseFrame(List<int> raw) {
  if (raw.length < kHeaderLen || raw[0] != kStartRx) {
    throw FrameFormatException('bad start byte');
  }
  final total = ((raw[1] & 0x3F) << 8) | raw[2];
  final frag = FragStatus.values[raw[1] >> 6];
  // Машина завышает длину первого фрагмента 0x08 на несколько байт: кадр
  // приходит целиком в одном notify, но header обещает больше. Для фрагментов
  // доверяем границе чанка, иначе кадр не собрать вообще.
  final truncated = total != raw.length;
  if (truncated && frag == FragStatus.none) {
    throw FrameFormatException(
      'length mismatch: header=$total real=${raw.length}',
    );
  }
  final cmd = raw[4];
  final payload = Uint8List.fromList(raw.sublist(5));
  if (!truncated &&
      raw[3] != frameChecksum(raw[0], raw[1], raw[2], cmd, payload)) {
    throw FrameFormatException('bad checksum');
  }
  return Frame(cmd, payload, frag);
}

/// Склейка notify-чанков в кадры.
class FrameDecoder {
  final List<int> _buf = [];

  void reset() => _buf.clear();

  /// Длинные ответы приходят несколькими notify, поэтому хвост копится между
  /// вызовами. Исключение — фрагменты 0x08: машина завышает их длину в
  /// заголовке, и недобранный фрагмент нужно закрыть по границе чанка, иначе
  /// он съест следующий кадр и весь ответ пропадёт.
  List<Uint8List> push(List<int> chunk) {
    final out = <Uint8List>[];
    if (_pendingIsFragment() && _startsFrame(chunk)) {
      out.add(Uint8List.fromList(_buf));
      _buf.clear();
    }
    _buf.addAll(chunk);
    while (_buf.isNotEmpty) {
      final idx = _buf.indexOf(kStartRx);
      if (idx < 0) {
        _buf.clear();
        break;
      }
      if (idx > 0) {
        _buf.removeRange(0, idx);
        continue;
      }
      if (_buf.length < kHeaderLen) break;
      final total = ((_buf[1] & 0x3F) << 8) | _buf[2];
      if (total < kHeaderLen || total > kMaxFrameLen) {
        _buf.removeAt(0);
        continue;
      }
      if (total > _buf.length) break;
      out.add(Uint8List.fromList(_buf.sublist(0, total)));
      _buf.removeRange(0, total);
    }
    return out;
  }

  /// В буфере лежит начало фрагмента, которому машина обещала больше байт.
  bool _pendingIsFragment() =>
      _buf.length >= kHeaderLen &&
      _buf[0] == kStartRx &&
      (_buf[1] >> 6) != 0 &&
      (((_buf[1] & 0x3F) << 8) | _buf[2]) > _buf.length;

  /// Чанк начинается с самостоятельного кадра — значит предыдущий закончен.
  static bool _startsFrame(List<int> c) =>
      c.length >= kHeaderLen &&
      c[0] == kStartRx &&
      ((((c[1] & 0x3F) << 8) | c[2]) <= c.length);
}

/// Сборка фрагментированных ответов (только 0x06 и 0x08).
class FragmentAssembler {
  final List<int> _buf = [];

  void reset() => _buf.clear();

  /// Возвращает собранную нагрузку, либо null пока фрагменты не кончились.
  Uint8List? feed(Frame f) {
    switch (f.frag) {
      case FragStatus.none:
        return f.payload;
      case FragStatus.first:
        _buf
          ..clear()
          ..addAll(f.payload);
        return null;
      case FragStatus.middle:
        _buf.addAll(f.payload);
        return null;
      case FragStatus.last:
        _buf.addAll(f.payload);
        final data = Uint8List.fromList(_buf);
        _buf.clear();
        return data;
    }
  }
}

// ---------------------------------------------------------------------------
// Конструкторы команд
// ---------------------------------------------------------------------------

Uint8List cmdGetDeviceState() => buildFrame(Cmd.deviceState);
Uint8List cmdGetDeviceInfo() => buildFrame(Cmd.deviceInfo);
Uint8List cmdGetTempSetting() => buildFrame(Cmd.getTempSetting);
Uint8List cmdGetWorkParams() => buildFrame(Cmd.getWorkParams);
Uint8List cmdGetAppointment() => buildFrame(Cmd.getAppointment);
Uint8List cmdGetTodayCups() => buildFrame(Cmd.todayCups);
Uint8List cmdReset() => buildFrame(Cmd.reset);
Uint8List cmdEnterOta() => buildFrame(Cmd.enterOta);

Uint8List cmdSetTargetTemperature(int celsius) =>
    buildFrame(Cmd.setTempSetting, [celsiusToWire(celsius) & 0xFF]);

/// Порядок байтов — `[mode, start]`, а не `[start, mode]`, как читалось из
/// снапшота: имена аргументов там сохранились, а порядок записи в буфер — нет.
/// Живая машина расставила всё по местам. Со старым порядком `01 00` (нагрев)
/// не делал ничего — это стоп с режимом 1, а `01 01` и `01 02` одинаково
/// запускали нагрев с проливом, потому что второй байт читался как флаг пуска.
Uint8List cmdSetWorkState(bool start, WorkMode mode) =>
    buildFrame(Cmd.setWorkState, [mode.code, start ? 1 : 0]);

Uint8List cmdStop() => cmdSetWorkState(false, WorkMode.heat);

Uint8List cmdGetCups({bool clear = false}) =>
    buildFrame(Cmd.cups, [clear ? 1 : 0]);

/// Последний байт отбрасывается, если машина не сообщила параметры
/// времени экстракции (короткий ответ 0x17).
Uint8List cmdSetWorkParams({
  required int pressure,
  required int preInfusionSeconds,
  required int standstillSeconds,
  int? extractionSeconds,
}) {
  final body = <int>[
    pressure & 0xFF,
    preInfusionSeconds & 0xFF,
    standstillSeconds & 0xFF,
    if (extractionSeconds != null) extractionSeconds & 0xFF,
  ];
  return buildFrame(Cmd.setWorkParams, body);
}

Uint8List cmdSetTime([DateTime? now]) {
  final t = now ?? DateTime.now();
  return buildFrame(Cmd.setTime, [
    t.weekday, // 1 = понедельник .. 7 = воскресенье
    t.month,
    t.day,
    (t.year - 2020) & 0xFF,
    t.hour,
    t.minute,
    t.second,
  ]);
}

Uint8List cmdSetAppointment(Appointment a) => buildFrame(Cmd.setAppointment, [
  a.mode.code,
  a.hour & 0xFF,
  a.minute & 0xFF,
  a.reminder.code,
  a.beep.code,
  a.enabled ? 1 : 0,
]);

// ---------------------------------------------------------------------------
// Разбор ответов
// ---------------------------------------------------------------------------

class DeviceStatus {
  const DeviceStatus({
    required this.batteryRaw,
    required this.batteryLevel,
    required this.charge,
    required this.temperatureC,
    required this.state,
    required this.error,
    required this.errorCode,
  });

  /// Сырое число из пакета. Процентами оно только выглядит: за 45 тысяч
  /// пакетов приняло ровно три значения — 35, 60, 85. Это представители
  /// четырёх корзин, а не измерение. Показывать его пользователю нельзя,
  /// оставлено для логов.
  final int batteryRaw;
  final ChargeState charge;
  final int temperatureC;
  final MachineState state;
  final MachineError error;

  /// Сырой байт ошибки. Совпадает с [MachineError.code] у всех известных
  /// кодов и остаётся единственным, что мы знаем про незнакомый.
  final int errorCode;

  /// Деление батареи 0..4 — то единственное, что машина про заряд знает.
  /// Ровно столько же аппаратных точек светится на её корпусе.
  final int batteryLevel;
}

DeviceStatus parseDeviceStatus(Uint8List p) {
  if (p.length < 6)
    throw FrameFormatException('device state payload too short');
  final raw = p[1] & 0x7F;
  final flags = p[2];

  // Пороги ровно как в оригинале: 0 / 1..24 / 25..50 / 51..75 / выше.
  var level = raw == 0
      ? 0
      : raw < 25
      ? 1
      : raw <= 50
      ? 2
      : raw <= 75
      ? 3
      : 4;

  var charge = (flags & 0x80) != 0
      ? ChargeState.charging
      : ChargeState.notCharging;
  // Два флага перебивают расчёт по числу: 0x20 сажает уровень в ноль,
  // 0x40 — «заряд окончен», полная батарея независимо от байта.
  if ((flags & 0x20) != 0) level = 0;
  if ((flags & 0x40) != 0) {
    level = 4;
    charge = ChargeState.full;
  }

  return DeviceStatus(
    batteryRaw: raw,
    batteryLevel: level,
    charge: charge,
    temperatureC: p[3],
    state: MachineState.fromCode(p[4]),
    error: MachineError.fromCode(p[5]),
    errorCode: p[5],
  );
}

class TempLimits {
  const TempLimits(this.min, this.max, this.target);
  final int min;
  final int max;
  final int target;

  int clamp(int v) => v < min ? min : (v > max ? max : v);
}

/// Запасные границы заданной температуры, когда машина отдаёт заведомо неверные.
const int kFallbackTempMin = 40;
const int kFallbackTempMax = 100;

/// Границы, с которых приложение живёт до первого ответа машины.
///
/// Диапазоны нельзя оставлять пустыми: пустой диапазон нечем показать и нечем
/// ограничить правку, а машина отвечает не всегда — из дежурного режима она
/// молчит на всё рукопожатие. Оригинал решает это так же: конструктор
/// `PcmDevice` заполняет все свои диапазоны зашитыми числами ещё до всякого
/// BLE и правку не блокирует никогда.
///
/// Числа взяты не у него — его дефолты (смачивание 0–20, экстракция 60–360,
/// давление 0–4) не совпадают с PCM03SMAX ни в одной строке. Здесь то, что
/// эта машина отдаёт на самом деле: `0x17 07 05 00 0a 05 00 0a 1e 1e fa 01 0f`.
/// Живут они недолго — на смену им приходит либо кэш прошлого сеанса, либо
/// свежий ответ.
const TempLimits kFallbackLimits = TempLimits(
  kFallbackTempMin,
  kFallbackTempMax,
  92,
);

const WorkParams kFallbackParams = WorkParams(
  pressure: Range(5, 1, 15),
  preInfusion: Range(5, 0, 10),
  standstill: Range(5, 0, 10),
  extraction: Range(70, 30, 250),
  hasExtraction: true,
);

/// Установка температуры едет по проводу в Фаренгейтах, а текущая температура
/// в телеметрии (`0x00[3]`) — в Цельсиях. Так устроен оригинал: он переводит
/// принятые °C в °F и дальше живёт целиком в °F, а на экран пересчитывает
/// обратно. Отсюда и `64 cc 5b` у PCM03SMAX: это 100…204 °F, то есть 38…96 °C.
///
/// Внутри приложения температура всегда в °C, перевод — только здесь, на
/// границе. Границы округляем внутрь диапазона, чтобы обратный перевод не
/// выскочил за то, что машина принимает.
int celsiusFromWire(int f) => ((f - 32) / 1.8).round();
int celsiusToWire(int c) => (c * 1.8 + 32).round();

TempLimits parseTempLimits(Uint8List p) {
  if (p.length < 3)
    throw FrameFormatException('temp setting payload too short');
  var min = ((p[0] - 32) / 1.8).ceil();
  var max = ((p[1] - 32) / 1.8).floor();
  final target = celsiusFromWire(p[2]);
  if (min >= max) {
    min = kFallbackTempMin;
    max = kFallbackTempMax;
  }
  return TempLimits(min, max, target);
}

class Range {
  const Range(this.value, this.min, this.max);
  final int value;
  final int min;
  final int max;

  int clamp(int v) => v < min ? min : (v > max ? max : v);
}

class WorkParams {
  const WorkParams({
    required this.pressure,
    required this.preInfusion,
    required this.standstill,
    required this.extraction,
    required this.hasExtraction,
  });

  /// «Давление экстракции» родного приложения: ступени, границы приезжают
  /// байтами 10–11. У старых прошивок их нет вовсе — тогда 0..2.
  final Range pressure;
  final Range preInfusion;
  final Range standstill;
  final Range extraction;

  /// Машина прислала параметры времени экстракции — можно слать 4 байта.
  final bool hasExtraction;
}

WorkParams parseWorkParams(Uint8List p) {
  if (p.length < 10) throw FrameFormatException('work param payload too short');
  final hasRange = p.length >= 12;
  return WorkParams(
    // При max < min устройство считается «без диапазона», подставляем 0..2.
    pressure: hasRange && p[11] >= p[10]
        ? Range(p[0], p[10], p[11])
        : Range(p[0], 0, 2),
    preInfusion: Range(p[1], p[2], p[3]),
    standstill: Range(p[4], p[5], p[6]),
    extraction: Range(p[7], p[8], p[9]),
    hasExtraction: true,
  );
}

/// Эхо на 0x18 (4 байта) и на 0x20 (5 байт) — форматы разные.
class WorkParamEcho {
  const WorkParamEcho({
    required this.pressure,
    required this.preInfusion,
    required this.standstill,
    required this.extraction,
    this.targetTemperature,
  });

  final int pressure;
  final int preInfusion;
  final int standstill;
  final int extraction;

  /// Присутствует только в ответе на 0x20 (сброс к заводским).
  final int? targetTemperature;
}

WorkParamEcho parseWorkParamEcho(Uint8List p) {
  if (p.length >= 5) {
    return WorkParamEcho(
      pressure: p[0],
      preInfusion: p[1],
      standstill: p[2],
      // Установка и здесь в °F — поле то же самое, что в 0x15.
      targetTemperature: celsiusFromWire(p[3]),
      extraction: p[4],
    );
  }
  if (p.length >= 4) {
    return WorkParamEcho(
      pressure: p[0],
      preInfusion: p[1],
      standstill: p[2],
      extraction: p[3],
    );
  }
  throw FrameFormatException('work param echo too short');
}

class Appointment {
  const Appointment({
    required this.mode,
    required this.hour,
    required this.minute,
    required this.reminder,
    required this.beep,
    required this.enabled,
    this.spent = false,
  });

  const Appointment.disabled()
    : mode = ScheduleMode.heatAndBrew,
      hour = 7,
      minute = 0,
      reminder = ReminderMode.sound,
      beep = BeepSound.dingDong,
      enabled = false,
      spent = false;

  final ScheduleMode mode;
  final int hour;
  final int minute;
  final ReminderMode reminder;
  final BeepSound beep;

  /// Взведён — то есть флаг в кадре равен ровно единице.
  final bool enabled;

  /// Машина отметила, что задача отработала.
  ///
  /// Флаг в кадре не булев: 0 — выключен, 1 — взведён, 2 — отработал. Живой
  /// лог: взвели `... 01`, будильник сработал, и на следующем 0x24 машина
  /// вернула `... 02`. Оригинал сравнивает байт ровно с единицей и потому
  /// показывает «выключен», а что именно случилось — не различает.
  final bool spent;

  Appointment copyWith({
    ScheduleMode? mode,
    int? hour,
    int? minute,
    ReminderMode? reminder,
    BeepSound? beep,
    bool? enabled,
    bool? spent,
  }) => Appointment(
    mode: mode ?? this.mode,
    hour: hour ?? this.hour,
    minute: minute ?? this.minute,
    reminder: reminder ?? this.reminder,
    beep: beep ?? this.beep,
    enabled: enabled ?? this.enabled,
    // Своей записью отметку «отработал» всегда снимаем: обратно в машину
    // уходит только 0 или 1, третьего значения мы не пишем.
    spent: spent ?? (enabled == null && this.spent),
  );
}

Appointment parseAppointment(Uint8List p) {
  if (p.length < 6) throw FrameFormatException('appointment payload too short');
  return Appointment(
    mode: ScheduleMode.fromCode(p[0]),
    hour: p[1],
    minute: p[2],
    reminder: ReminderMode.fromCode(p[3]),
    beep: BeepSound.fromCode(p[4]),
    // Ровно с единицей — так же, как оригинал. Двойка это не «включён»,
    // а «отработал», и включённым его показывать нельзя.
    enabled: p[5] == 1,
    spent: p[5] == 2,
  );
}

/// Ответ 0x06: payload[2] — сегодня, [3] — вчера и так далее.
Map<DateTime, int> parseCupsHistory(Uint8List p, {DateTime? today}) {
  if (p.length < 3) throw FrameFormatException('cups payload too short');
  final base = today ?? DateTime.now();
  final day = DateTime(base.year, base.month, base.day);
  final out = <DateTime, int>{};
  for (var i = 2; i < p.length; i++) {
    out[day.subtract(Duration(days: i - 2))] = p[i];
  }
  return out;
}

class DeviceInfo {
  const DeviceInfo(this.hardware, this.firmware, this.model);

  /// Версия железа. В ответе 0x08 идёт первой — так же её читает оригинал:
  /// первая строка ложится в поле, которое экран версий подписывает
  /// «hardwareVersion», вторая — в «firmwareVersion».
  final String hardware;

  /// Версия прошивки. Её и показываем человеку: железо он всё равно не меняет.
  final String firmware;

  final String model;
}

/// Ответ 0x08: [резерв][len][ascii] x3.
DeviceInfo parseDeviceInfo(Uint8List p) {
  if (p.length < 2) throw FrameFormatException('device info payload too short');
  final parts = <String>[];
  final lens = <int>[];
  var i = 1;
  for (var k = 0; k < 3 && i < p.length; k++) {
    final n = p[i];
    lens.add(n);
    final end = (i + 1 + n).clamp(0, p.length);
    parts.add(String.fromCharCodes(p.sublist((i + 1).clamp(0, p.length), end)));
    i += 1 + n;
  }
  while (parts.length < 3) {
    parts.add('');
    lens.add(0);
  }
  var model = parts[2];
  if (lens[2] == 0) {
    model = 'PCM03';
  } else if (lens[2] == 1) {
    model = 'PCM03S';
  }
  return DeviceInfo(parts[0], parts[1], model);
}
