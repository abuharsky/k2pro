/// Кодек BLE-протокола весов Timemore Black Mirror DOT.
///
/// Чистый Dart без Flutter — можно тестировать отдельно, как и кодек машины.
///
/// Протокол взят из открытого драйвера Beanconqueror
/// (`src/classes/devices/timemoreDotScale.ts`, Apache-2.0) и там же проверен на
/// живых весах. Забавно, что весы говорят через тот же профиль FFF0/FFF1/FFF2,
/// что и наша машина: BLE-модуль у них одного поставщика, а вот рамка кадра
/// совсем другая — с настоящей CRC вместо суммы байтов.
///
/// Различать машину и весы в эфире можно только по имени: сервис у них общий.
library;

import 'dart:typed_data';

// ---------------------------------------------------------------------------
// GATT
// ---------------------------------------------------------------------------

const String kScaleServiceUuid = '0000fff0-0000-1000-8000-00805f9b34fb';
const String kScaleNotifyUuid = '0000fff1-0000-1000-8000-00805f9b34fb';
const String kScaleWriteUuid =
    '0000fff2-0000-1000-8000-00805f9b34fb'; // write w/o resp

/// Куски имени, по которым узнаются весы. Сравнение без учёта регистра и по
/// вхождению, а не по началу: в эфире встречались и «DOT», и «TES017…».
const List<String> kScaleNameParts = ['dot', 'tes017'];

bool isScaleName(String advertisedName) {
  final n = advertisedName.toLowerCase();
  return kScaleNameParts.any(n.contains);
}

/// Весы шлют измерения сами, около десяти раз в секунду. Дольше этого молчания
/// считаем, что их больше нет на линии: у машины такой порог пять секунд,
/// здесь можно втрое строже — поток частый и ровный.
const Duration kScaleSilence = Duration(seconds: 2);

/// Пауза после подписки на FFF1, прежде чем слать первую команду. У машины
/// такая же и по той же причине: сразу после setNotifyValue стек ещё занят.
const Duration kScaleHandshakeDelay = Duration(milliseconds: 400);

/// Между командами настройки. В драйвере-источнике стоит 500 и 200 мс;
/// берём с запасом одну величину.
const Duration kScaleWriteInterval = Duration(milliseconds: 200);

// ---------------------------------------------------------------------------
// Кадр
// ---------------------------------------------------------------------------

const int kScaleStart0 = 0xA5;
const int kScaleStart1 = 0x5A;

/// Байт 2 кадра. В нашу сторону всегда [command]; весы отвечают [reply] или
/// [push] — разницы между ними драйвер-источник не делает, и мы не делаем.
abstract final class ScaleOp {
  static const int reply = 0x01;
  static const int push = 0x02;
  static const int command = 0x03;
}

/// Байт 3 кадра: о чём речь.
abstract final class ScaleCmd {
  /// Измерение: вес, и следом четыре байта, которые ещё предстоит опознать.
  static const int measure = 0x01;

  /// Таймер весов: 1 — пуск, 2 — стоп, 3 — сброс.
  static const int timer = 0x02;

  static const int battery = 0x05;

  /// Единицы измерения: 0 — граммы.
  static const int unit = 0x06;

  /// Режим весов: `01 00` — обычный.
  static const int mode = 0x08;

  static const int tare = 0x0D;
}

/// CRC-16/IBM (он же ARC): полином 0xA001, начальное 0xFFFF.
///
/// Считается по всему кадру до самой контрольной суммы, включая заголовок.
/// В кадр она кладётся старшим байтом вперёд — не так, как этот CRC принято
/// передавать, но так делает железо.
int scaleCrc16(List<int> data) {
  var crc = 0xFFFF;
  for (final b in data) {
    crc ^= b & 0xFF;
    for (var i = 0; i < 8; i++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xA001 : crc >> 1;
    }
  }
  return crc;
}

/// Собрать кадр телефон -> весы.
Uint8List buildScaleFrame(int opcode, int cmdId, [List<int> data = const []]) {
  final body = <int>[
    kScaleStart0,
    kScaleStart1,
    opcode,
    cmdId,
    (data.length >> 8) & 0xFF,
    data.length & 0xFF,
    ...data,
  ];
  final crc = scaleCrc16(body);
  return Uint8List.fromList([...body, (crc >> 8) & 0xFF, crc & 0xFF]);
}

// ---------------------------------------------------------------------------
// Команды
// ---------------------------------------------------------------------------

enum ScaleTimerCommand {
  start(1),
  stop(2),
  reset(3);

  const ScaleTimerCommand(this.code);
  final int code;
}

Uint8List cmdScaleTare() => buildScaleFrame(ScaleOp.command, ScaleCmd.tare);

Uint8List cmdScaleTimer(ScaleTimerCommand c) =>
    buildScaleFrame(ScaleOp.command, ScaleCmd.timer, [c.code]);

/// Граммы. Без этого весы могут остаться в унциях с прошлого раза, и весь
/// счёт в приложении молча поедет в три раза.
Uint8List cmdScaleUnitGram() =>
    buildScaleFrame(ScaleOp.command, ScaleCmd.unit, [0x00]);

/// Обычный режим взвешивания — не «рецепт» и не «поток», в которых весы
/// начинают жить своей жизнью.
Uint8List cmdScaleStandardMode() =>
    buildScaleFrame(ScaleOp.command, ScaleCmd.mode, [0x01, 0x00]);

// ---------------------------------------------------------------------------
// Разбор
// ---------------------------------------------------------------------------

/// Что приехало от весов.
sealed class ScaleFrame {
  const ScaleFrame();
}

/// Измерение.
class ScaleMeasurement extends ScaleFrame {
  const ScaleMeasurement({required this.grams, required this.extra});

  /// Вес в граммах, разрешение 0.1 г. Знак настоящий: на весах, с которых
  /// сняли тару, лежащая рядом ложка даёт отрицательное число.
  final double grams;

  /// Хвост кадра после веса — четыре байта, которые в драйвере-источнике
  /// названы «поток и время», но не разобраны.
  ///
  /// Держим сырыми и кладём в трассу: опознать их можно только на живых весах,
  /// сверив с секундомером. Пока что поток мы считаем сами — у чужого фильтра
  /// неизвестная задержка, а контуру останова нужна известная.
  final Uint8List extra;
}

/// Заряд, проценты.
class ScaleBattery extends ScaleFrame {
  const ScaleBattery(this.percent);
  final int percent;
}

/// Кадр, который мы поняли по форме, но не по смыслу. Нужен трассе: молчание
/// и «сыплется непонятное» — разные болезни.
class ScaleUnknown extends ScaleFrame {
  const ScaleUnknown(this.opcode, this.cmdId, this.data);
  final int opcode;
  final int cmdId;
  final Uint8List data;
}

/// Результат разбора: сам кадр и признак сошедшейся контрольной суммы.
///
/// Сумму проверяем, но решение «выбросить» принимает слой выше. Драйвер, из
/// которого взят протокол, на DOT её не проверяет вовсе (на соседней модели —
/// проверяет), так что до живых весов уверенности нет. Если суммы не сойдутся
/// у всех кадров подряд, это будет видно в трассе сразу и как раз тем, чем
/// оно является, а не как «весы молчат».
class ScaleParse {
  const ScaleParse(this.frame, {required this.crcOk});
  final ScaleFrame frame;
  final bool crcOk;
}

/// Разобрать кадр весы -> телефон. null — это не наш кадр.
ScaleParse? parseScaleFrame(Uint8List raw) {
  if (raw.length < 8) return null;
  if (raw[0] != kScaleStart0 || raw[1] != kScaleStart1) return null;

  final len = (raw[4] << 8) | raw[5];
  if (raw.length < 8 + len) return null;

  final crcOk =
      ((raw[6 + len] << 8) | raw[7 + len]) ==
      scaleCrc16(raw.sublist(0, 6 + len));
  final data = Uint8List.sublistView(raw, 6, 6 + len);
  final opcode = raw[2];
  final cmdId = raw[3];

  if (opcode == ScaleOp.reply || opcode == ScaleOp.push) {
    if (cmdId == ScaleCmd.measure && len >= 4) {
      // Big-endian, десятые грамма. toSigned обязателен: int в Dart
      // 64-битный, и без него минус превращается в четыре миллиарда.
      final raw32 =
          (data[0] << 24) | (data[1] << 16) | (data[2] << 8) | data[3];
      return ScaleParse(
        ScaleMeasurement(
          grams: raw32.toSigned(32) / 10,
          extra: Uint8List.sublistView(data, 4),
        ),
        crcOk: crcOk,
      );
    }
    if (cmdId == ScaleCmd.battery && len >= 2) {
      return ScaleParse(ScaleBattery(data[1]), crcOk: crcOk);
    }
  }
  return ScaleParse(ScaleUnknown(opcode, cmdId, data), crcOk: crcOk);
}
