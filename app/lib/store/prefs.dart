import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ble/protocol.dart';
import '../model/recipe.dart';

/// Локальные настройки: имя, единицы, последние известные параметры пролива.
///
/// В протоколе этого нет — машина не хранит ни имени, ни °F. Сами параметры
/// она хранит и отдаёт по 0x15/0x17, так что здесь только кэш: показать что-то
/// осмысленное, пока связи нет.
class Prefs extends ChangeNotifier {
  Prefs._(this._sp);

  final SharedPreferences _sp;

  static const _kName = 'device_name';
  static const _kFahrenheit = 'unit_is_f';
  static const _kRecipe = 'recipe';
  static const _kLastId = 'last_device_id';
  static const _kDevices = 'devices';
  static const _kLocale = 'locale';
  static const _kRunMode = 'run_mode';
  static const _kRanges = 'ranges';

  static Future<Prefs> load() async =>
      Prefs._(await SharedPreferences.getInstance()).._migrate();

  /// Раньше машина была одна: имя лежало отдельной строкой, а идентификатор —
  /// отдельной. Переносим эту пару в список, чтобы дальше жил только он.
  void _migrate() {
    if (_sp.getString(_kDevices) != null) return;
    final id = _sp.getString(_kLastId);
    if (id == null) return;
    _writeDevices([
      SavedDevice(id: id, name: _sp.getString(_kName) ?? _kFallbackName),
    ]);
  }

  static const _kFallbackName = 'K2 Pro';

  // ---- список машин -----------------------------------------------------

  /// Машины, которые однажды добавили. Порядок — от последней добавленной:
  /// список правится только отсюда, поиск лишь дописывает в конец.
  List<SavedDevice> get devices {
    final raw = _sp.getString(_kDevices);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return [];
      return [
        for (final e in list)
          if (e is Map && e['id'] is String)
            SavedDevice(
              id: e['id'] as String,
              name: e['name'] as String? ?? _kFallbackName,
            ),
      ];
    } catch (_) {
      return [];
    }
  }

  void _writeDevices(List<SavedDevice> list) {
    _sp.setString(
      _kDevices,
      jsonEncode([
        for (final d in list) {'id': d.id, 'name': d.name},
      ]),
    );
  }

  /// Своё имя машины, если её уже добавляли.
  String? nameOf(String id) {
    for (final d in devices) {
      if (d.id == id) return d.name;
    }
    return null;
  }

  /// Машина, к которой подключились, попадает в список. Имя из эфира берём
  /// только для новой: переименование живёт дольше рекламного имени.
  void remember(String id, String advertisedName) {
    final list = devices;
    if (!list.any((d) => d.id == id)) {
      list.add(
        SavedDevice(
          id: id,
          name: advertisedName.isEmpty ? _kFallbackName : advertisedName,
        ),
      );
      _writeDevices(list);
    }
    lastDeviceId = id;
    notifyListeners();
  }

  /// Забыть машину. Единственный способ убрать её из списка — и живёт он в
  /// настройках: в поиске тап по ряду всегда значит «подключись».
  void forget(String id) {
    final list = devices..removeWhere((d) => d.id == id);
    _writeDevices(list);
    if (lastDeviceId == id) {
      lastDeviceId = list.isEmpty ? null : list.last.id;
    }
    notifyListeners();
  }

  /// Имя текущей машины — той, с которой работали последней.
  String get deviceName {
    final id = lastDeviceId;
    if (id != null) {
      final own = nameOf(id);
      if (own != null) return own;
    }
    return _sp.getString(_kName) ?? _kFallbackName;
  }

  set deviceName(String v) {
    final id = lastDeviceId;
    if (id != null && devices.any((d) => d.id == id)) {
      _writeDevices([
        for (final d in devices) d.id == id ? SavedDevice(id: id, name: v) : d,
      ]);
    } else {
      // Машины ещё нет — имя приютит старая строка, до первого подключения.
      _sp.setString(_kName, v);
    }
    notifyListeners();
  }

  /// Код языка приложения. null — как в системе.
  String? get localeCode => _sp.getString(_kLocale);
  set localeCode(String? v) {
    if (v == null) {
      _sp.remove(_kLocale);
    } else {
      _sp.setString(_kLocale, v);
    }
    notifyListeners();
  }

  bool get fahrenheit => _sp.getBool(_kFahrenheit) ?? false;
  set fahrenheit(bool v) {
    _sp.setBool(_kFahrenheit, v);
    notifyListeners();
  }

  String? get lastDeviceId => _sp.getString(_kLastId);
  set lastDeviceId(String? v) {
    if (v == null) {
      _sp.remove(_kLastId);
    } else {
      _sp.setString(_kLastId, v);
    }
  }

  /// Что делает главная кнопка. Машина этого не помнит — режим живёт здесь,
  /// чтобы «пуск» повторял последнее осознанное действие.
  WorkMode get runMode {
    final c = _sp.getInt(_kRunMode);
    return WorkMode.values.firstWhere(
      (m) => m.code == c,
      orElse: () => WorkMode.heatAndBrew,
    );
  }

  set runMode(WorkMode v) {
    _sp.setInt(_kRunMode, v.code);
    notifyListeners();
  }

  /// Последние параметры, снятые с машины. Истина всегда в железе — это
  /// только то, что показать до подключения.
  Recipe get recipe {
    final raw = _sp.getString(_kRecipe);
    if (raw == null || raw.isEmpty) return Recipe.fallback;
    try {
      final list = Recipe.decodeList(raw);
      return list.isEmpty ? Recipe.fallback : list.first;
    } catch (_) {
      return Recipe.fallback;
    }
  }

  set recipe(Recipe v) {
    if (v.matches(recipe))
      return; // машина шлёт параметры пачками, не дёргаем UI
    _sp.setString(_kRecipe, Recipe.encodeList([v]));
    notifyListeners();
  }

  // ---- диапазоны уставок ------------------------------------------------

  /// Границы, которые машина назвала в прошлый раз.
  ///
  /// Хранятся отдельно от [recipe]: тот — что налить, а это — что машина
  /// вообще принимает. Значения внутри диапазонов здесь не значат ничего,
  /// уставки живут в рецепте; пишем их как есть, чтобы не плодить типов.
  /// Нужны затем, чтобы правка была открыта и с молчащей машиной — своими
  /// числами, а не чужими заводскими.
  ({TempLimits limits, WorkParams params})? get ranges {
    final raw = _sp.getString(_kRanges);
    if (raw == null || raw.isEmpty) return null;
    try {
      final j = jsonDecode(raw);
      if (j is! Map) return null;
      Range range(String k, Range or) {
        final v = j[k];
        if (v is! List || v.length < 3) return or;
        return Range(v[0] as int, v[1] as int, v[2] as int);
      }

      final t = j['temp'];
      return (
        limits: t is List && t.length >= 3
            ? TempLimits(t[0] as int, t[1] as int, t[2] as int)
            : kFallbackLimits,
        params: WorkParams(
          pressure: range('pressure', kFallbackParams.pressure),
          preInfusion: range('pre', kFallbackParams.preInfusion),
          standstill: range('still', kFallbackParams.standstill),
          extraction: range('ext', kFallbackParams.extraction),
          hasExtraction: j['hasExt'] as bool? ?? true,
        ),
      );
    } catch (_) {
      return null;
    }
  }

  void saveRanges(TempLimits t, WorkParams p) {
    List<int> r(Range x) => [x.value, x.min, x.max];
    final raw = jsonEncode({
      'temp': [t.min, t.max, t.target],
      'pressure': r(p.pressure),
      'pre': r(p.preInfusion),
      'still': r(p.standstill),
      'ext': r(p.extraction),
      'hasExt': p.hasExtraction,
    });
    if (raw == _sp.getString(_kRanges)) return;
    _sp.setString(_kRanges, raw);
  }
}

/// Пересчёт для отображения. Внутри приложения температура всегда в °C:
/// провод переводится на границе протокола (см. [celsiusFromWire]).
int toDisplayTemp(int celsius, bool fahrenheit) =>
    fahrenheit ? (celsius * 1.8 + 32).round() : celsius;

int fromDisplayTemp(int shown, bool fahrenheit) =>
    fahrenheit ? ((shown - 32) / 1.8).round() : shown;

/// Машина из списка добавленных: идентификатор и имя, которым её назвали.
class SavedDevice {
  const SavedDevice({required this.id, required this.name});

  final String id;
  final String name;
}
