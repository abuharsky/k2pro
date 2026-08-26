import 'dart:math' as math;

import '../../ble/protocol.dart';
import '../../model/brew_phase.dart';

/// Слой разреза машины: положение кадра на холсте базовой картинки.
///
/// Координаты — из `export/machine-layer-v2/layout.json`: [x] — центр слоя по
/// ширине, [y] — верхняя кромка по высоте, [w] — ширина; всё в долях бокса
/// базы (её аспект [SceneLayer.baseAspect] = 2:3). Высота слоя выводится из
/// его собственного аспекта, поэтому в таблице её нет.
///
/// Цифры взяты из макета как есть и подгонки не требуют: пока холст цел,
/// чашка сама садится на верхнюю грань подставки.
enum SceneLayer {
  tank('tank', frames: 5, x: 0.495, y: 0, w: 0.47, aspect: 381 / 423, ms: 450),
  pump(
    'pump',
    frames: 2,
    x: 0.492,
    y: 0.29,
    w: 0.34,
    aspect: 448 / 407,
    ms: 400,
  ),
  puck(
    'puck',
    frames: 5,
    x: 0.49,
    y: 0.49,
    w: 0.40,
    aspect: 414 / 514,
    ms: 400,
  ),
  cup('cup', frames: 5, x: 0.49, y: 0.715, w: 0.37, aspect: 375 / 319, ms: 450);

  const SceneLayer(
    this.id, {
    required this.frames,
    required this.x,
    required this.y,
    required this.w,
    required this.aspect,
    required this.ms,
  });

  /// Аспект базовой картинки: 800×1200.
  static const double baseAspect = 2 / 3;

  final String id;

  /// Сколько кадров у слоя: `id_0` … `id_{frames-1}`.
  final int frames;

  final double x;
  final double y;
  final double w;

  /// Ширина к высоте самого кадра.
  final double aspect;

  /// Длительность кроссфейда между кадрами.
  final int ms;

  /// Высота слоя в долях высоты бокса базы.
  double get h => w / aspect * baseAspect;

  /// Нижняя кромка в долях высоты бокса базы.
  double get bottom => y + h;

  String assetOf(int frame) => 'assets/machine/${id}_$frame.png';
}

/// Всё, что сцене нужно знать о машине. Собирается на домашнем экране из
/// [K2Device], сама сцена в BLE не лезет.
class SceneState {
  const SceneState({
    required this.connected,
    required this.phase,
    required this.phaseFraction,
    required this.cupFill,
    required this.live,
    this.mode = WorkMode.heatAndBrew,
  });

  final bool connected;

  final BrewPhase phase;

  /// Доля текущей фазы, 0..1.
  final double phaseFraction;

  /// Насколько налита чашка, 0..1.
  final double cupFill;

  /// Цикл идёт — сцене можно двигаться.
  final bool live;

  /// Чем запустят (или запустили). Нужен, чтобы заранее гасить стадии, которых
  /// в этом режиме не будет: холодный пролив не греет, нагрев не льёт.
  final WorkMode mode;

  static const SceneState idle = SceneState(
    connected: false,
    phase: BrewPhase.idle,
    phaseFraction: 0,
    cupFill: 0,
    live: false,
  );

  /// Кадр слоя по текущему состоянию. Раскладка фаз — из `layout.json`.
  int frameOf(SceneLayer layer) => switch (layer) {
    SceneLayer.tank => _tank,
    SceneLayer.pump => _pump,
    SceneLayer.puck => _puck,
    SceneLayer.cup => _cup,
  };

  /// Бак: 0 полный, 1 полный с горящей спиралью, 2–4 убывающая вода.
  ///
  /// Уровня воды машина не сообщает, поэтому при экстракции он падает по
  /// формуле из макета; светящаяся спираль — наоборот, настоящие данные.
  int get _tank {
    if (!connected) return 0;
    return switch (phase) {
      BrewPhase.extraction => math.min(4, 2 + (phaseFraction * 3).floor()),
      // Пролив выпил бак досуха; после «только нагрева» лить было нечего.
      BrewPhase.done => _pours ? 4 : 0,
      // Спираль светится ровно в фазе нагрева: дальше по циклу её уже не
      // питают, идёт вода. Остаточное тепло нагревом не считается — иначе
      // сцена стоит «в нагреве» все десятки минут остывания.
      BrewPhase.heating => live && _heats ? 1 : 0,
      _ => 0,
    };
  }

  /// Помпа гонит воду: подсвечен тракт.
  int get _pump =>
      phase == BrewPhase.preInfusion || phase == BrewPhase.extraction ? 1 : 0;

  /// Таблетка: 0 сухая, 1 мокрая, 2–4 нарастающий пролив.
  int get _puck => switch (phase) {
    // Смачивание — единственное, что видно в этой фазе, а длится она секунды.
    // Ждать её середины значит не показать смачивание вовсе.
    BrewPhase.preInfusion => 1,
    BrewPhase.standstill => 1,
    BrewPhase.extraction => 2 + math.min(2, (phaseFraction * 3).floor()),
    // Пролив кончился, таблетка осталась мокрой; после нагрева она сухая.
    BrewPhase.done => _pours ? 1 : 0,
    _ => 0,
  };

  /// Чашка: пять уровней от пустой до полной.
  int get _cup =>
      _pours ? math.min(4, (cupFill.clamp(0.0, 1.0) * 5).floor()) : 0;

  /// В этом режиме машина вообще греет.
  bool get _heats => mode != WorkMode.brew;

  /// В этом режиме машина вообще льёт.
  bool get _pours => mode != WorkMode.heat;

  /// Какой узел машины сейчас работает — по нему подсвечивается секция.
  SceneLayer? get zone => switch (phase) {
    BrewPhase.heating => SceneLayer.tank,
    BrewPhase.preInfusion ||
    BrewPhase.standstill ||
    BrewPhase.extraction => SceneLayer.puck,
    // После нагрева итог цикла в баке, после пролива — в чашке.
    BrewPhase.done => _pours ? SceneLayer.cup : SceneLayer.tank,
    // В покое не светится ничего: горячая машина — это не работающая машина.
    _ => null,
  };

  @override
  bool operator ==(Object other) =>
      other is SceneState &&
      other.connected == connected &&
      other.phase == phase &&
      other.phaseFraction == phaseFraction &&
      other.cupFill == cupFill &&
      other.live == live &&
      other.mode == mode;

  @override
  int get hashCode =>
      Object.hash(connected, phase, phaseFraction, cupFill, live, mode);
}
