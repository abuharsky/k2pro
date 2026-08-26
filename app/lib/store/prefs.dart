import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ble/protocol.dart';
import '../model/gravimetry.dart';
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
  static const _kRecipeByMode = 'recipe_by_mode';
  static const _kLastId = 'last_device_id';
  static const _kDevices = 'devices';
  static const _kLocale = 'locale';
  static const _kRunMode = 'run_mode';
  static const _kRanges = 'ranges';
  static const _kScaleId = 'last_scale_id';
  static const _kScaleName = 'scale_name';
  static const _kGravimetry = 'gravimetry';
  static const _kGravimetryByMode = 'gravimetry_by_mode';
  static const _kShots = 'shots';
  static const _kAdviceBanner = 'advice_banner';

  static Future<Prefs> load() async =>
      Prefs._(await SharedPreferences.getInstance()).._migrate();

  /// Раньше машина была одна: имя лежало отдельной строкой, а идентификатор —
  /// отдельной. Переносим эту пару в список, чтобы дальше жил только он.
  /// Рекламного имени у неё не сохранилось — там, где оно нужно, встанет
  /// [SavedDevice.fallbackName].
  void _migrate() {
    if (_sp.getString(_kDevices) != null) return;
    final id = _sp.getString(_kLastId);
    if (id == null) return;
    _writeDevices([SavedDevice(id: id, alias: _sp.getString(_kName))]);
  }

  // ---- демо -------------------------------------------------------------

  /// Приложение работает на симуляторах.
  ///
  /// Живёт только в памяти: демо не переживает перезапуск намеренно. Здесь оно
  /// нужно затем, чтобы демо не оставляло следов, — и собрано это в одном
  /// месте, а не россыпью проверок по экранам.
  ///
  /// Пока флаг стоит, хранилище глотает всё, что описывает *устройство*: имя,
  /// список машин, уставки, диапазоны, журнал проливов. Иначе демо-машина
  /// попадала бы в «Мои устройства», её идентификатор — в [lastDeviceId] (и
  /// автоподключение при следующем запуске ушло бы искать симулятор в живом
  /// эфире), а её уставки перетёрли бы кэш настоящей машины.
  ///
  /// Настройки самого приложения — язык, °C/°F, режим кнопки — пишутся как
  /// обычно: они про приложение, а не про машину.
  bool demo = false;

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
              name: e['name'] as String? ?? '',
              alias: e['alias'] as String?,
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
        for (final d in list)
          {'id': d.id, 'name': d.name, if (d.alias != null) 'alias': d.alias},
      ]),
    );
  }

  /// Как показывать машину в списке, если её уже добавляли.
  String? nameOf(String id) {
    for (final d in devices) {
      if (d.id == id) return d.title;
    }
    return null;
  }

  /// Машина, к которой подключились, попадает в список. Рекламное имя обновляем
  /// при каждой встрече, а данное хозяином — не трогаем: оно живёт дольше.
  void remember(String id, String advertisedName) {
    if (demo) return;
    final list = devices;
    final i = list.indexWhere((d) => d.id == id);
    final was = i < 0 ? null : list[i];
    final entry = SavedDevice(
      id: id,
      name: advertisedName.isEmpty ? (was?.name ?? '') : advertisedName,
      alias: was?.alias,
    );
    if (was == null) {
      list.add(entry);
    } else {
      list[i] = entry;
    }
    _writeDevices(list);
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

  /// Имя текущей машины — той, с которой работали последней. Рекламное имя
  /// сюда не поднимается: в шапке стоит «K2 Pro», пока машину не назвали
  /// своими словами. `BL_PCM03_SIM` — примета эфира, ему место в списке.
  String get deviceName {
    final id = lastDeviceId;
    if (id != null) {
      for (final d in devices) {
        if (d.id == id) return d.alias ?? SavedDevice.fallbackName;
      }
    }
    return _sp.getString(_kName) ?? SavedDevice.fallbackName;
  }

  set deviceName(String v) {
    if (demo) return;
    final id = lastDeviceId;
    final list = devices;
    final i = id == null ? -1 : list.indexWhere((d) => d.id == id);
    if (i < 0) {
      // Машины ещё нет — имя приютит старая строка, до первого подключения.
      _sp.setString(_kName, v);
    } else {
      list[i] = SavedDevice(id: list[i].id, name: list[i].name, alias: v);
      _writeDevices(list);
    }
    notifyListeners();
  }

  // ---- весы -------------------------------------------------------------

  /// Весы держим одни — вторых на столе не бывает. Отдельным ключом, а не в
  /// общем списке машин: подключение у них независимое, и путать «к чему
  /// подключиться» с «чем взвесить» нельзя.
  String? get lastScaleId => _sp.getString(_kScaleId);

  static const _kScaleFallbackName = 'DOT';

  String get scaleName => _sp.getString(_kScaleName) ?? _kScaleFallbackName;

  void rememberScale(String id, String advertisedName) {
    if (demo) return;
    _sp.setString(_kScaleId, id);
    if (advertisedName.isNotEmpty) _sp.setString(_kScaleName, advertisedName);
    notifyListeners();
  }

  void forgetScale() {
    _sp.remove(_kScaleId);
    _sp.remove(_kScaleName);
    notifyListeners();
  }

  // ---- граммы -----------------------------------------------------------

  /// Доза, цель по весу, автостоп и выученная поправка. Одна на текущий
  /// рецепт — ровно как сам [recipe], а рецепт свой у каждого режима.
  Gravimetry get gravimetry => gravimetryFor(runMode);
  set gravimetry(Gravimetry v) => setGravimetryFor(runMode, v);

  /// Граммовый набор конкретного режима.
  ///
  /// Отсечка по весу — такая же уставка режима, как секунды экстракции, и
  /// разъезжаться с ними ей нельзя: включение подменяет секунды потолком, а
  /// секунды лежат в рецепте режима. Будь отсечка одна на всех, включённая в
  /// «проливе» она оставалась бы включённой и в «нагрев + пролив», где секунды
  /// никто не подменял, — и предохранитель оказывался бы целью.
  ///
  /// Цель и доза едут туда же: американо на 250 г и эспрессо на 36 г — это
  /// разные режимы, и держать на них одно число незачем.
  Gravimetry gravimetryFor(WorkMode m) {
    final raw = _sp.getString(_kGravimetryByMode);
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = Gravimetry.decodeList(raw);
        if (m.code >= 0 && m.code < list.length) return list[m.code];
      } catch (_) {}
    }
    // Единая ячейка прежних версий — общий сид для режимов, у которых своего
    // набора ещё не завели.
    return Gravimetry.decode(_sp.getString(_kGravimetry));
  }

  void setGravimetryFor(WorkMode m, Gravimetry v) {
    // Собираем полный набор по всем режимам и подменяем один — как у рецептов.
    final ordered = [
      for (var code = 0; code < WorkMode.values.length; code++)
        gravimetryFor(_modeByCode(code)),
    ];
    ordered[m.code] = v;
    _sp.setString(_kGravimetryByMode, Gravimetry.encodeList(ordered));
    notifyListeners();
  }

  /// Журнал проливов, от свежего к старому.
  List<ShotRecord> get shots => ShotRecord.decodeList(_sp.getString(_kShots));

  void addShot(ShotRecord s) {
    if (demo) return;
    final list = [s, ...shots];
    if (list.length > kShotHistory) list.removeRange(kShotHistory, list.length);
    _sp.setString(_kShots, ShotRecord.encodeList(list));
    notifyListeners();
  }

  void clearShots() {
    _sp.remove(_kShots);
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

  /// Показывать разбор чашки сразу после пролива.
  ///
  /// Совет нужен, пока рецепт сводят: раз сведённый, он повторяется каждой
  /// чашкой и превращается в помеху. Сам разбор из настроек никуда не девается
  /// — выключается только то, что он лезет наверх сам.
  bool get adviceBanner => _sp.getBool(_kAdviceBanner) ?? true;
  set adviceBanner(bool v) {
    _sp.setBool(_kAdviceBanner, v);
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

  /// Рецепт активного режима. Правка, кэш телеметрии и пуск ходят через него,
  /// поэтому всё приложение всегда работает с набором выбранного режима.
  /// Истина всё так же в железе — это то, что показать до подключения и что
  /// вернуть в машину при переключении режима.
  Recipe get recipe => recipeFor(runMode);
  set recipe(Recipe v) => setRecipeFor(runMode, v);

  /// Рецепт конкретного режима. У каждого режима свой набор: под «нагрев +
  /// пролив» — эспрессо с предсмачиванием и паузами, под «пролив» — просто
  /// кипяток американо без пауз. Пока своего набора у режима нет, отдаём
  /// единый рецепт прошлых версий как общий сид.
  Recipe recipeFor(WorkMode m) {
    final raw = _sp.getString(_kRecipeByMode);
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = Recipe.decodeList(raw);
        if (m.code >= 0 && m.code < list.length) return list[m.code];
      } catch (_) {}
    }
    return _legacyRecipe;
  }

  void setRecipeFor(WorkMode m, Recipe v) {
    if (demo) return;
    if (recipeFor(m).matches(v))
      return; // машина шлёт параметры пачками, не дёргаем UI
    // Собираем полный набор по всем режимам и подменяем один: наборы
    // остальных режимов при этом не трогаем.
    final ordered = [
      for (var code = 0; code < WorkMode.values.length; code++)
        recipeFor(_modeByCode(code)),
    ];
    ordered[m.code] = v;
    _sp.setString(_kRecipeByMode, Recipe.encodeList(ordered));
    notifyListeners();
  }

  WorkMode _modeByCode(int code) => WorkMode.values.firstWhere(
    (w) => w.code == code,
    orElse: () => WorkMode.heatAndBrew,
  );

  /// Единый рецепт прежних версий: одна ячейка [_kRecipe]. Остаётся сидом для
  /// режимов, у которых своего набора ещё не завели.
  Recipe get _legacyRecipe {
    final raw = _sp.getString(_kRecipe);
    if (raw == null || raw.isEmpty) return Recipe.fallback;
    try {
      final list = Recipe.decodeList(raw);
      return list.isEmpty ? Recipe.fallback : list.first;
    } catch (_) {
      return Recipe.fallback;
    }
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
    if (demo) return;
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

/// Машина из списка добавленных.
class SavedDevice {
  const SavedDevice({required this.id, this.name = '', this.alias});

  /// Как называть машину, которой не досталось ни имени хозяина, ни эфира.
  static const String fallbackName = 'K2 Pro';

  final String id;

  /// Имя из рекламы — то, чем машина представилась в эфире.
  final String name;

  /// Имя, которым её назвал хозяин. Оно и стоит в шапке.
  final String? alias;

  /// Что показывать в списке: своё имя, иначе эфирное.
  String get title => alias ?? (name.isEmpty ? fallbackName : name);
}
