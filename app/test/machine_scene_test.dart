import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k2pro/ble/protocol.dart';
import 'package:k2pro/model/brew_phase.dart';
import 'package:k2pro/ui/scene/machine_scene.dart';
import 'package:k2pro/ui/scene/scene_state.dart';

/// Прямоугольник картинки слоя на экране. Провайдер завёрнут в [ResizeImage]
/// ради cacheWidth, поэтому до имени ассета добираемся через него.
Rect _rectOf(WidgetTester tester, String asset) {
  final finder = find.byWidgetPredicate((w) {
    if (w is! Image) return false;
    final p = w.image;
    final inner = p is ResizeImage ? p.imageProvider : p;
    return inner is AssetImage && inner.assetName == 'assets/machine/$asset';
  }, skipOffstage: false);
  expect(finder, findsOneWidget, reason: asset);
  // Бокс каждой картинки уже ровно её пропорций, поэтому fill. С contain
  // картинка центровалась бы внутри своего бокса и getRect ниже мерил бы не
  // то, что видно, — а слои снова могли бы разъехаться с базой.
  expect(tester.widget<Image>(finder).fit, BoxFit.fill, reason: asset);
  return tester.getRect(finder);
}

void main() {
  /// Слои и база — один холст. Раньше пропорцию держал AspectRatio, а под
  /// тугими констрейнтами он её не держит: база центровалась сама по себе, и
  /// при ресайзе окна слои уезжали относительно неё.
  Future<void> checkRigid(WidgetTester tester, Widget scene) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Center(child: scene)),
      ),
    );

    final base = _rectOf(tester, 'base.png');
    expect(
      base.width / base.height,
      closeTo(MachineScene.aspect, 0.001),
      reason: 'база всегда 2:3',
    );

    for (final layer in SceneLayer.values) {
      final r = _rectOf(tester, '${layer.id}_0.png');
      expect(
        r.left - base.left,
        closeTo(base.width * (layer.x - layer.w / 2), 0.01),
        reason: '${layer.id}: левый край',
      );
      expect(
        r.top - base.top,
        closeTo(base.height * layer.y, 0.01),
        reason: '${layer.id}: верхняя кромка',
      );
      expect(
        r.width,
        closeTo(base.width * layer.w, 0.01),
        reason: '${layer.id}: ширина',
      );
      expect(
        r.width / r.height,
        closeTo(layer.aspect, 0.001),
        reason: '${layer.id}: аспект кадра',
      );
    }
  }

  const scene = MachineScene(state: SceneState.idle);

  // Тесное окно, широкое, узкое и высокое: машина всюду показывается целиком.
  for (final size in [
    const Size(300, 500),
    const Size(900, 400),
    const Size(200, 900),
    const Size(120, 160),
  ]) {
    testWidgets('слои держатся базы в боксе $size', (tester) async {
      await checkRigid(tester, SizedBox.fromSize(size: size, child: scene));
    });
  }

  testWidgets('слои держатся базы под тугими констрейнтами', (tester) async {
    // Так машину сжимает домашний экран — именно на этом сцена и разъезжалась.
    await checkRigid(
      tester,
      const SizedBox(
        width: 340,
        height: 620,
        child: FractionallySizedBox(
          widthFactor: 0.9,
          heightFactor: 0.9,
          child: scene,
        ),
      ),
    );
  });

  testWidgets('машина целиком влезает в отведённое место', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: SizedBox(width: 900, height: 400, child: scene)),
        ),
      ),
    );
    final base = _rectOf(tester, 'base.png');
    expect(base.height, lessThanOrEqualTo(400.001));
    expect(base.width, lessThanOrEqualTo(900.001));
  });

  // ---- что показывают слои ----------------------------------------------

  SceneState state(
    BrewPhase phase, {
    bool live = false,
    double fraction = 0,
    double cupFill = 0,
    WorkMode mode = WorkMode.heatAndBrew,
  }) => SceneState(
    connected: true,
    phase: phase,
    phaseFraction: fraction,
    cupFill: cupFill,
    live: live,
    mode: mode,
  );

  test('остановленный цикл возвращает сцену в покой', () {
    final heating = state(BrewPhase.heating, live: true);
    expect(heating.frameOf(SceneLayer.tank), 1, reason: 'спираль под током');
    expect(heating.zone, SceneLayer.tank);

    // Кнопка «стоп»: машина ушла в standby, но вода ещё горячая. Спираль
    // гаснет сразу — раньше сцена так и стояла «в нагреве» до остывания.
    final stopped = state(BrewPhase.idle);
    for (final layer in SceneLayer.values) {
      expect(stopped.frameOf(layer), 0, reason: layer.id);
    }
    expect(stopped.zone, isNull);
  });

  test('после «только нагрева» бак полон, а чашка пуста', () {
    // Общий для всех режимов cupFill: сцена сама решает, лился ли кофе.
    final done = state(BrewPhase.done, cupFill: 1, mode: WorkMode.heat);
    expect(done.frameOf(SceneLayer.tank), 0, reason: 'лить было нечего');
    expect(done.frameOf(SceneLayer.puck), 0, reason: 'таблетка сухая');
    expect(done.frameOf(SceneLayer.cup), 0);
    expect(done.zone, SceneLayer.tank);
  });

  test('после пролива бак пуст, а чашка полна', () {
    final done = state(BrewPhase.done, cupFill: 1);
    expect(done.frameOf(SceneLayer.tank), 4);
    expect(done.frameOf(SceneLayer.puck), 1, reason: 'таблетка мокрая');
    expect(done.frameOf(SceneLayer.cup), 4);
    expect(done.zone, SceneLayer.cup);
  });

  test('холодный пролив не зажигает спираль', () {
    final wetting = state(
      BrewPhase.preInfusion,
      live: true,
      fraction: 0.8,
      mode: WorkMode.brew,
    );
    expect(wetting.frameOf(SceneLayer.tank), 0);
    expect(
      wetting.frameOf(SceneLayer.pump),
      1,
      reason: 'помпа всё равно гонит',
    );
    expect(wetting.frameOf(SceneLayer.puck), 1, reason: 'таблетка смочена');
  });

  test('смачивание идёт без нагрева и видно сразу', () {
    // Нагрев к этому моменту закончился: спираль обесточена, идёт вода.
    for (final fraction in [0.0, 0.4, 1.0]) {
      final wetting = state(
        BrewPhase.preInfusion,
        live: true,
        fraction: fraction,
      );
      expect(wetting.frameOf(SceneLayer.tank), 0, reason: 'спираль погасла');
      expect(wetting.frameOf(SceneLayer.puck), 1, reason: 'доля $fraction');
      expect(wetting.zone, SceneLayer.puck);
    }

    // Пауза после смачивания: воду не гонят, таблетка стоит мокрая.
    final pause = state(BrewPhase.standstill, live: true);
    expect(pause.frameOf(SceneLayer.tank), 0);
    expect(pause.frameOf(SceneLayer.pump), 0);
    expect(pause.frameOf(SceneLayer.puck), 1);
  });

  test('экстракция считает бак, таблетку и чашку по прогрессу', () {
    final start = state(BrewPhase.extraction, live: true, fraction: 0);
    expect(start.frameOf(SceneLayer.tank), 2);
    expect(start.frameOf(SceneLayer.puck), 2);
    expect(start.frameOf(SceneLayer.cup), 0);

    final end = state(
      BrewPhase.extraction,
      live: true,
      fraction: 1,
      cupFill: 1,
    );
    expect(end.frameOf(SceneLayer.tank), 4);
    expect(end.frameOf(SceneLayer.puck), 4);
    expect(end.frameOf(SceneLayer.cup), 4);
  });

  test('без связи машина стоит в покое', () {
    const off = SceneState.idle;
    for (final layer in SceneLayer.values) {
      expect(off.frameOf(layer), 0, reason: layer.id);
    }
    expect(off.zone, isNull);
  });
}
