import 'dart:convert';

import '../ble/protocol.dart';

/// Рецепт — то, что машина умеет хранить в своих рабочих параметрах.
class Recipe {
  const Recipe({
    required this.name,
    required this.temperatureC,
    required this.pressure,
    required this.preInfusionSeconds,
    required this.standstillSeconds,
    required this.extractionSeconds,
    this.builtinKey,
  });

  final String name;
  final int temperatureC;

  /// Уставка «давление экстракции» из 0x17/0x18 — так её называет и родное
  /// приложение. Это ступени (обычно 1..15), а не бары: обратной связи по
  /// давлению машина не даёт, в телеметрии 0x00 его нет.
  final int pressure;
  final int preInfusionSeconds;
  final int standstillSeconds;
  final int extractionSeconds;

  /// Ключ встроенного пресета: его имя переводится, а не хранится текстом.
  /// null у всего, что пользователь создал или переименовал сам.
  final String? builtinKey;

  static const Recipe fallback = Recipe(
    name: 'Custom',
    temperatureC: 92,
    pressure: 5,
    preInfusionSeconds: 5,
    standstillSeconds: 5,
    extractionSeconds: 70,
  );

  Recipe copyWith({
    String? name,
    int? temperatureC,
    int? pressure,
    int? preInfusionSeconds,
    int? standstillSeconds,
    int? extractionSeconds,
    bool dropBuiltin = false,
  }) => Recipe(
    name: name ?? this.name,
    // Переименованный или правленый пресет перестаёт быть встроенным:
    // подставлять ему перевод уже неправильно.
    builtinKey: dropBuiltin || (name != null && name != this.name)
        ? null
        : builtinKey,
    temperatureC: temperatureC ?? this.temperatureC,
    pressure: pressure ?? this.pressure,
    preInfusionSeconds: preInfusionSeconds ?? this.preInfusionSeconds,
    standstillSeconds: standstillSeconds ?? this.standstillSeconds,
    extractionSeconds: extractionSeconds ?? this.extractionSeconds,
  );

  /// Совпадает ли рецепт с тем, что сейчас в машине (имя не учитывается).
  bool matches(Recipe other) =>
      temperatureC == other.temperatureC &&
      pressure == other.pressure &&
      preInfusionSeconds == other.preInfusionSeconds &&
      standstillSeconds == other.standstillSeconds &&
      extractionSeconds == other.extractionSeconds;

  Recipe clampTo(WorkParams p, TempLimits t) => copyWith(
    temperatureC: temperatureC.clamp(t.min, t.max),
    pressure: p.pressure.clamp(pressure),
    preInfusionSeconds: p.preInfusion.clamp(preInfusionSeconds),
    standstillSeconds: p.standstill.clamp(standstillSeconds),
    extractionSeconds: p.extraction.clamp(extractionSeconds),
  );

  Map<String, Object?> toJson() => {
    'name': name,
    if (builtinKey != null) 'builtin': builtinKey,
    't': temperatureC,
    'pressure': pressure,
    'pre': preInfusionSeconds,
    'still': standstillSeconds,
    'ext': extractionSeconds,
  };

  static Recipe fromJson(Map<String, Object?> j) => Recipe(
    name: j['name'] as String? ?? 'Custom',
    temperatureC: j['t'] as int? ?? fallback.temperatureC,
    // 'flow' — ключ прежних версий, когда поле звалось скоростью потока.
    pressure: j['pressure'] as int? ?? j['flow'] as int? ?? fallback.pressure,
    preInfusionSeconds: j['pre'] as int? ?? fallback.preInfusionSeconds,
    standstillSeconds: j['still'] as int? ?? fallback.standstillSeconds,
    extractionSeconds: j['ext'] as int? ?? fallback.extractionSeconds,
    builtinKey: j['builtin'] as String?,
  );

  static String encodeList(List<Recipe> list) =>
      jsonEncode(list.map((r) => r.toJson()).toList());

  static List<Recipe> decodeList(String s) {
    final raw = jsonDecode(s);
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, Object?>>()
        .map(Recipe.fromJson)
        .toList(growable: true);
  }
}
