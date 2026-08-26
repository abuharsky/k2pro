import 'dart:async';

import 'package:flutter/foundation.dart';

import '../ble/k2_device.dart';
import '../ble/protocol.dart';
import '../ble/trace.dart';
import '../model/recipe.dart';
import 'prefs.dart';

/// Уставки, которые пользователь набрал, но которые ещё не уехали в машину.
///
/// Правка ползёт по шагу за тап, а каждый шаг — это команда по BLE. Копим и
/// шлём один раз, когда человек остановился. Живёт отдельно от экрана, потому
/// что крутить одни и те же числа могут двое: телефон и часы. Общее состояние
/// здесь — иначе на часах число прыгало бы назад на каждом снимке телеметрии.
class RecipeEditor extends ChangeNotifier {
  RecipeEditor({required this.device, required this.prefs}) {
    // Что машина рассказала о себе в прошлый раз. До её ответа это
    // единственное, чем правка может быть ограничена — и единственное, что
    // делает её вообще возможной.
    final r = prefs.ranges;
    if (r != null) device.seed(limits: r.limits, params: r.params);
    device.addListener(_cache);
  }

  final K2Device device;
  final Prefs prefs;

  Timer? _push;

  int? _temp;
  int? _extraction;
  int? _pre;
  int? _still;
  int? _pressure;

  /// Что уже уложено в настройки. См. [_cache].
  TempLimits? _savedLimits;
  WorkParams? _savedParams;

  /// Что показывать: свежая правка, иначе то, что в машине, иначе кэш настроек.
  Recipe get active {
    final base = device.rangesFromDevice ? device.deviceRecipe : prefs.recipe;
    return base.copyWith(
      temperatureC: _temp,
      extractionSeconds: _extraction,
      preInfusionSeconds: _pre,
      standstillSeconds: _still,
      pressure: _pressure,
    );
  }

  /// Правка ещё не ушла в машину.
  bool get isDirty => _push?.isActive ?? false;

  /// Изменить уставку. В машину уходит одной командой после паузы.
  void edit({
    int? temperatureC,
    int? extractionSeconds,
    int? preInfusionSeconds,
    int? standstillSeconds,
    int? pressure,
  }) {
    if (temperatureC != null) _temp = temperatureC;
    if (extractionSeconds != null) _extraction = extractionSeconds;
    if (preInfusionSeconds != null) _pre = preInfusionSeconds;
    if (standstillSeconds != null) _still = standstillSeconds;
    if (pressure != null) _pressure = pressure;
    Trace.instance.ui(
      'правка ${[if (temperatureC != null) 't=$temperatureC', if (extractionSeconds != null) 'ext=$extractionSeconds', if (preInfusionSeconds != null) 'pre=$preInfusionSeconds', if (standstillSeconds != null) 'still=$standstillSeconds', if (pressure != null) 'p=$pressure'].join(' ')}',
    );
    notifyListeners();

    _push?.cancel();
    _push = Timer(kSettingsDebounce, _flush);
  }

  Future<void> _flush() async {
    Trace.instance.ui('дебаунс истёк, пишу уставки');
    final r = active.clampTo(device.workParams, device.tempLimits);
    prefs.recipe = r;
    await device.setRecipe(r);
    _clear();
    notifyListeners();
  }

  /// Снять накопленную правку и отдать её тому, кто будет писать в машину.
  ///
  /// Зовётся перед пуском. Ничего не отправляет и ничего не ждёт — только
  /// закрывает дебаунс и возвращает то, что должно оказаться в машине. Раньше
  /// этот же метод сам ходил в машину и пуск ждал его: на молчащей машине
  /// ожидание стоило восьми секунд, и всё это время кнопка не отзывалась.
  /// Теперь порядок «уставки, потом пуск» держит [K2Device.start], а ожидание
  /// на кнопке заводится первым же действием.
  Recipe commit() {
    Trace.instance.ui('уставки сняты для записи перед пуском');
    _push?.cancel();
    _push = null;
    final r = active.clampTo(device.workParams, device.tempLimits);
    prefs.recipe = r;
    _clear();
    notifyListeners();
    return r;
  }

  /// Переключить режим и подтянуть его набор.
  ///
  /// Каждый режим помнит свои уставки: под эспрессо — паузы и предсмачивание,
  /// под пролив американо — просто пролив. Порядок такой: сперва снимаем текущее
  /// в набор старого режима (заодно закрываем дебаунс), потом делаем активным
  /// новый и возвращаем в машину его набор. Машина держит один рецепт, поэтому
  /// «память режима» — это восстановление снимка при переключении.
  Future<void> selectMode(WorkMode mode) async {
    if (mode == prefs.runMode) return;
    // commit() сохраняет активное в набор ещё старого режима и гасит таймер
    // записи — иначе отложенная правка старого режима догнала бы уже новый.
    commit();
    prefs.runMode = mode;
    final r = prefs.recipeFor(mode);
    notifyListeners();
    // force: набор нового режима может совпасть по числам с тем, что сейчас в
    // машине лишь частично; пишем целиком, чтобы железо точно встало на него.
    if (device.isConnected) await device.setRecipe(r, force: true);
  }

  void _clear() {
    _temp = null;
    _extraction = null;
    _pre = null;
    _still = null;
    _pressure = null;
  }

  /// Машина — источник истины. Запоминаем её параметры, чтобы было что
  /// показать до подключения.
  void _cache() {
    if (!device.isConnected || !device.rangesFromDevice) return;
    // Слушатель срабатывает на каждый кадр телеметрии, а диапазоны машина
    // пересобирает только когда отвечает про них: сверяем по ссылке.
    if (!identical(_savedLimits, device.tempLimits) ||
        !identical(_savedParams, device.workParams)) {
      _savedLimits = device.tempLimits;
      _savedParams = device.workParams;
      prefs.saveRanges(device.tempLimits, device.workParams);
    }
    if (isDirty) return; // своя правка ещё в пути
    prefs.recipe = device.deviceRecipe;
  }

  @override
  void dispose() {
    device.removeListener(_cache);
    _push?.cancel();
    super.dispose();
  }
}
