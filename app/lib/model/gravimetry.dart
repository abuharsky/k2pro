/// Граммовая часть рецепта и журнал проливов.
///
/// В [Recipe] этому места нет: там — «то, что машина умеет хранить», и
/// `Recipe.matches` сравнивает наши уставки с её собственными. Доза, цель по
/// весу и выученная поправка на дотёк машине неизвестны и никогда в неё не
/// уедут, поэтому живут рядом и отдельно.
library;

import 'dart:convert';

import 'gravimetric_stop.dart';

/// Границы цели по весу. Ниже пяти граммов автостоп бессмыслен — столько
/// натечёт и после останова; выше двухсот не бывает ни одной посуды, которая
/// поместилась бы под машину.
const double kYieldMin = 5;
const double kYieldMax = 200;

/// Шаг цели и дозы. Десятая грамма — ровно то, что весы и различают: шаг
/// крупнее означал бы, что заказать можно не всякий вес, который они умеют
/// показать.
const double kYieldStep = 0.1;

/// Шаг при удержании кнопки. Одиночный тап двигает на десятую, а зажатая
/// кнопка идёт по грамму за шаг: докрутить с 36 до 40 — это пара секунд
/// удержания, а не сорок тапов и не четыреста тиков по десятой.
const double kYieldStepCoarse = 1.0;

/// Прижать к десятой грамма. Без этого сорок нажатий на минус превращают 36.0
/// в 35.999999999999996: дробь в двоичном виде не складывается ровно, и ошибка
/// копится с каждым шагом.
double snapGrams(double v) => (v * 10).roundToDouble() / 10;

/// Сколько проливов помним. Поправка учится по последнему, а журнал нужен,
/// чтобы человек мог ответить себе «почему сегодня хуже».
const int kShotHistory = 200;

class Gravimetry {
  const Gravimetry({
    this.doseG,
    this.targetG = 36,
    this.stopOnYield = false,
    this.drip = kSeedDrip,
    this.secondsBeforeAutoStop,
  });

  /// Вход: сколько намололи. null — не взвешивали.
  final double? doseG;

  /// Выход: сколько должно оказаться в чашке.
  final double targetG;

  /// Рубить экстракцию по весу.
  ///
  /// Это выбор человека, а не следствие того, что весы нашлись в эфире: они
  /// могут просто лежать на столе и к машине отношения не иметь. Выключено —
  /// весы показывают вес и в цикле не участвуют.
  final bool stopOnYield;

  /// Выученный дотёк этого рецепта, граммы.
  final double drip;

  /// Сколько секунд экстракции стояло до того, как их подменили потолком.
  ///
  /// При включении отсечки по весу секунды перестают быть целью и становятся
  /// предохранителем, поэтому уезжают к максимуму. Без этой памяти выключение
  /// отсечки стирало бы выставленное человеком число навсегда — а он его,
  /// может, полгода подбирал.
  final int? secondsBeforeAutoStop;

  /// Отношение вход:выход — то самое «один к двум».
  double? get ratio {
    final d = doseG;
    if (d == null || d <= 0) return null;
    return targetG / d;
  }

  Gravimetry copyWith({
    double? doseG,
    bool dropDose = false,
    double? targetG,
    bool? stopOnYield,
    double? drip,
    int? secondsBeforeAutoStop,
    bool dropSavedSeconds = false,
  }) => Gravimetry(
    doseG: dropDose ? null : (doseG ?? this.doseG),
    targetG: targetG ?? this.targetG,
    stopOnYield: stopOnYield ?? this.stopOnYield,
    drip: drip ?? this.drip,
    secondsBeforeAutoStop: dropSavedSeconds
        ? null
        : (secondsBeforeAutoStop ?? this.secondsBeforeAutoStop),
  );

  Map<String, Object?> toJson() => {
    if (doseG != null) 'dose': doseG,
    'target': targetG,
    'stop': stopOnYield,
    'drip': drip,
    if (secondsBeforeAutoStop != null) 'wasSec': secondsBeforeAutoStop,
  };

  static Gravimetry fromJson(Map<String, Object?> j) => Gravimetry(
    doseG: (j['dose'] as num?)?.toDouble(),
    targetG: (j['target'] as num?)?.toDouble() ?? 36,
    stopOnYield: j['stop'] as bool? ?? false,
    drip: (j['drip'] as num?)?.toDouble() ?? kSeedDrip,
    secondsBeforeAutoStop: (j['wasSec'] as num?)?.toInt(),
  );

  static Gravimetry decode(String? raw) {
    if (raw == null || raw.isEmpty) return const Gravimetry();
    try {
      final j = jsonDecode(raw);
      return j is Map<String, Object?> ? fromJson(j) : const Gravimetry();
    } catch (_) {
      return const Gravimetry();
    }
  }

  String encode() => jsonEncode(toJson());

  /// Наборы всех режимов одной строкой — по коду режима, как и у рецептов.
  static String encodeList(List<Gravimetry> list) =>
      jsonEncode(list.map((g) => g.toJson()).toList());

  static List<Gravimetry> decodeList(String s) {
    final raw = jsonDecode(s);
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, Object?>>()
        .map(Gravimetry.fromJson)
        .toList(growable: true);
  }
}

/// Чем кривая пролива зовётся на диске. Отметка времени: другого столь же
/// надёжного различителя у записи нет, а двух проливов в одну миллисекунду не
/// бывает.
String curveIdOf(ShotRecord s) => '${s.at.millisecondsSinceEpoch}';

/// Один пролив в журнале.
///
/// Журнал ведётся всегда, а не только с весами: сколько лилось и при какой
/// температуре — это про машину, и знать это полезно само по себе. Весы лишь
/// добавляют к записи вес, цель и промах, так что все три поля здесь
/// необязательные.
class ShotRecord {
  const ShotRecord({
    required this.at,
    required this.recipeName,
    required this.temperatureC,
    required this.elapsed,
    required this.reason,
    this.doseG,
    this.targetG,
    this.finalG,
  });

  final DateTime at;
  final String recipeName;

  /// Заданная температура — та, что стояла в рецепте на пуске.
  final int temperatureC;

  final Duration elapsed;
  final StopReason reason;

  final double? doseG;

  /// Цель по весу. null — пролив вели по времени, цели никто не заказывал.
  final double? targetG;

  /// Что оказалось в чашке после осадки. null — весов не было.
  final double? finalG;

  /// Пролив, у которого есть вес. По таким считается статистика.
  bool get weighed => finalG != null;

  /// Промах: плюс — перелили. null — сравнивать не с чем.
  double? get miss {
    final t = targetG;
    final f = finalG;
    return t == null || f == null ? null : f - t;
  }

  double? get ratio {
    final d = doseG;
    final f = finalG;
    return d == null || f == null || d <= 0 ? null : f / d;
  }

  Map<String, Object?> toJson() => {
    'at': at.millisecondsSinceEpoch,
    'name': recipeName,
    't': temperatureC,
    'sec': elapsed.inSeconds,
    'why': reason.name,
    if (doseG != null) 'dose': doseG,
    if (targetG != null) 'target': targetG,
    if (finalG != null) 'out': finalG,
  };

  static ShotRecord fromJson(Map<String, Object?> j) => ShotRecord(
    at: DateTime.fromMillisecondsSinceEpoch(j['at'] as int? ?? 0),
    recipeName: j['name'] as String? ?? '',
    temperatureC: (j['t'] as num?)?.toInt() ?? 0,
    elapsed: Duration(seconds: j['sec'] as int? ?? 0),
    reason: StopReason.values.firstWhere(
      (r) => r.name == j['why'],
      orElse: () => StopReason.manual,
    ),
    doseG: (j['dose'] as num?)?.toDouble(),
    targetG: (j['target'] as num?)?.toDouble(),
    finalG: (j['out'] as num?)?.toDouble(),
  );

  static String encodeList(List<ShotRecord> list) =>
      jsonEncode(list.map((s) => s.toJson()).toList());

  static List<ShotRecord> decodeList(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final j = jsonDecode(raw);
      if (j is! List) return const [];
      return j
          .whereType<Map<String, Object?>>()
          .map(ShotRecord.fromJson)
          .toList();
    } catch (_) {
      return const [];
    }
  }
}
