import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k2pro/ble/demo.dart';
import 'package:k2pro/ble/k2_device.dart';
import 'package:k2pro/ble/mock_transport.dart';
import 'package:k2pro/ble/scale/mock_scale_transport.dart';
import 'package:k2pro/ble/scale/scale_device.dart';
import 'package:k2pro/ble/switchable_transport.dart';
import 'package:k2pro/ble/protocol.dart';
import 'package:k2pro/l10n/app_l10n.dart';
import 'package:k2pro/main.dart';
import 'package:k2pro/model/brew_phase.dart';
import 'package:k2pro/model/gravimetric_stop.dart';
import 'package:k2pro/model/gravimetry.dart';
import 'package:k2pro/model/shot_curve.dart';
import 'package:k2pro/store/shot_store.dart';
import 'package:k2pro/ui/shot_page.dart';
import 'package:k2pro/store/prefs.dart';
import 'package:k2pro/store/recipe_editor.dart';
import 'package:k2pro/ui/scene/machine_scene.dart';
import 'package:k2pro/ui/scene/scene_state.dart';
import 'package:k2pro/ui/theme.dart';
import 'package:k2pro/ui/widgets/cycle_timeline.dart';
import 'package:k2pro/ui/widgets/bottom_bar.dart';
import 'package:k2pro/ui/widgets/scale_button.dart';
import 'package:k2pro/ui/widgets/round_button.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Рендер экранов в PNG (в обычный прогон flutter test не попадает —
/// каталог вне test/):
///   flutter test tool/screenshots --update-goldens
/// Результат — tool/screenshots/goldens/*.png
///
/// Шрифты подгружаются из кеша SDK, иначе тестовый рендерер рисует текст
/// прямоугольниками.
/// Общие часы мока и устройства в кадре. По умолчанию замерли на одной точке —
/// снимки детерминированы; кадру «готово» их перематывают вперёд.
DateTime _shotClock = DateTime(2026, 1, 1, 6);

void main() {
  setUpAll(() async {
    final root = Platform.environment['FLUTTER_ROOT'];
    if (root == null) return;
    final dir = Directory('$root/bin/cache/artifacts/material_fonts');
    if (!dir.existsSync()) return;

    Future<void> load(String family, List<String> files) async {
      final loader = FontLoader(family);
      for (final f in files) {
        final file = File('${dir.path}/$f');
        if (file.existsSync()) {
          loader.addFont(
            Future.value(file.readAsBytesSync().buffer.asByteData()),
          );
        }
      }
      await loader.load();
    }

    await load('Roboto', [
      'Roboto-Regular.ttf',
      'Roboto-Medium.ttf',
      'Roboto-Bold.ttf',
      'Roboto-Light.ttf',
    ]);
    await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _shotClock = DateTime(2026, 1, 1, 6);
  });

  Future<void> shoot(
    WidgetTester tester,
    String name, {
    required Future<void> Function(K2Device device, Prefs prefs, ShotStore store)
    scenario,
    Future<void> Function(WidgetTester tester)? after,
    bool withDemo = false,
  }) async {
    // physicalSize задаётся в физических пикселях: логический размер = /dpr.
    const dpr = 2.0;
    tester.view.physicalSize = const Size(390 * dpr, 844 * dpr);
    tester.view.devicePixelRatio = dpr;
    // Безопасные поля настоящего телефона: без них шапка в кадре прилипает
    // к самому краю, и по снимку не понять, как экран выглядит на устройстве.
    tester.view.padding = const FakeViewPadding(
      top: 47 * dpr,
      bottom: 34 * dpr,
    );
    tester.view.viewPadding = const FakeViewPadding(
      top: 47 * dpr,
      bottom: 34 * dpr,
    );
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    final prefs = await Prefs.load();
    // Кривые складываем во временную папку: настоящая живёт за платформенным
    // каналом, которого в тесте нет.
    final curves = Directory.systemTemp.createTempSync('k2goldens');
    addTearDown(() => curves.deleteSync(recursive: true));
    final store = ShotStore(dir: curves);
    // Демо заводится только там, где его и снимают: в остальных кадрах
    // транспорт подставлен напрямую, и первый экран не должен вмешиваться.
    //
    // Часы мока перематываемы через [_shotClock]: фазы цикла он считает по
    // времени, и без перемотки кадр «готово» не снять — фейковый pump двигает
    // таймеры, но не настоящие часы. Часам устройства перемотка ни к чему и
    // даже вредна: по ним оно судит о свежести телеметрии и, прыгнув вперёд,
    // счёл бы связь потерянной. Поэтому у устройства часы стоят на месте.
    DateTime clock() => _shotClock;
    final machineLink = SwitchableTransport(MockTransport(now: clock));
    final device = K2Device(
      withDemo ? machineLink : MockTransport(now: clock),
      now: () => DateTime(2026, 1, 1, 6),
    );
    final scaleLink = SwitchableTransport(MockScaleTransport());
    final scale = ScaleDevice(withDemo ? scaleLink : MockScaleTransport());
    final editor = RecipeEditor(device: device, prefs: prefs);
    final demo = withDemo
        ? Demo(
            machineLink: machineLink,
            scaleLink: scaleLink,
            device: device,
            scale: scale,
            prefs: prefs,
          )
        : null;
    await tester.pumpWidget(
      K2App(
        device: device,
        scale: scale,
        prefs: prefs,
        editor: editor,
        demo: demo,
        store: store,
      ),
    );
    await tester.pump();
    try {
      await scenario(device, prefs, store);
      if (after != null) await after(tester);
      // Слои сцены декодируются настоящим асинхроном: без паузы вне фейкового
      // времени машина не успевает появиться и в кадр попадает пустой фон.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 600)),
      );
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/$name.png'),
      );
    } finally {
      demo?.dispose();
      device.dispose();
      scale.dispose();
      await tester.pump();
    }
  }

  Future<void> settle(WidgetTester tester, {int steps = 12}) async {
    for (var i = 0; i < steps; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  Future<void> slideStart(WidgetTester tester) async {
    // Слайдер занимает правую часть панели: слева от него может стоять
    // карточка весов, поэтому тянем от самой кнопки, а не от края панели.
    final parts = find.descendant(
      of: find.byType(BottomBar),
      matching: find.byType(GestureDetector),
    );
    var cta = tester.getRect(parts.first);
    for (var i = 1; i < parts.evaluate().length; i++) {
      final r = tester.getRect(parts.at(i));
      if (r.width > cta.width) cta = r;
    }
    final gesture = await tester.startGesture(
      Offset(cta.left + 48, cta.center.dy),
    );
    await gesture.moveBy(const Offset(250, 0));
    await gesture.up();
    await tester.pump();
  }

  testWidgets('00 welcome', (tester) async {
    // Первый экран: машин ещё нет, и выбор ровно один из двух.
    await shoot(
      tester,
      '00_welcome',
      withDemo: true,
      scenario: (_, _, _) async {},
    );
  });

  testWidgets('00b demo', (tester) async {
    // Демо: та же машина, тот же цикл, но метка в шапке не даёт спутать
    // симулятор с железом.
    await shoot(
      tester,
      '00b_demo',
      withDemo: true,
      scenario: (_, _, _) async {
        await tester.tap(find.text('Try the demo'));
        await settle(tester, steps: 24);
      },
    );
  });

  /// Демо с весами: обе карточки в колонке и вторая строка в шапке.
  Future<void> demoWithScale(WidgetTester tester, {required bool byWeight}) async {
    await tester.tap(find.text('Try the demo'));
    await settle(tester, steps: 24);
    if (byWeight) {
      await tester.tap(find.text('WEIGHT'));
      await settle(tester, steps: 8);
      await tester.tap(find.byType(KSwitch));
      await settle(tester, steps: 8);
      await tester.tapAt(const Offset(195, 60));
      await settle(tester, steps: 8);
    }
  }

  testWidgets('12 weight watching', (tester) async {
    // Весы есть, но пролив идёт по времени: карточка веса приглушена и просто
    // показывает число.
    await shoot(
      tester,
      '12_weight_watching',
      withDemo: true,
      scenario: (_, _, _) async => demoWithScale(tester, byWeight: false),
    );
  });

  testWidgets('12b weight armed', (tester) async {
    // Отсечка включена: у веса цель и кольцо, у пролива — «предел».
    await shoot(
      tester,
      '12b_weight_armed',
      withDemo: true,
      scenario: (_, _, _) async => demoWithScale(tester, byWeight: true),
    );
  });

  testWidgets('12c weight sheet', (tester) async {
    await shoot(
      tester,
      '12c_weight_sheet',
      withDemo: true,
      scenario: (_, _, _) async => demoWithScale(tester, byWeight: true),
      after: (tester) async {
        await tester.tap(find.text('WEIGHT'));
        await settle(tester, steps: 8);
      },
    );
  });

  testWidgets('12d weight dialog', (tester) async {
    await shoot(
      tester,
      '12d_weight_dialog',
      withDemo: true,
      scenario: (_, _, _) async => demoWithScale(tester, byWeight: false),
      after: (tester) async {
        await tester.tap(find.byType(ScaleButton));
        await settle(tester, steps: 8);
      },
    );
  });

  testWidgets('12e scale journal', (tester) async {
    // Журнал с историей: по графику промахов видно, как контур пристреливался,
    // а по времени пролива — ровно ли мелет кофемолка.
    await shoot(
      tester,
      '12e_scale_journal',
      withDemo: true,
      scenario: (_, prefs, store) async {
        const misses = [-1.4, -1.0, -0.7, -0.3, 0.2, -0.1, 0.3, -0.2, 0.1, -0.3];
        const times = [31, 29, 28, 27, 27, 26, 28, 27, 26, 27];
        for (var i = 0; i < misses.length; i++) {
          prefs.addShot(
            ShotRecord(
              at: DateTime(2026, 1, 1, 6, i),
              recipeName: 'Espresso',
              temperatureC: 93,
              doseG: 18,
              targetG: 36,
              finalG: 36 + misses[i],
              elapsed: Duration(seconds: times[i]),
              reason: StopReason.weight,
            ),
          );
        }
        await demoWithScale(tester, byWeight: true);
      },
      after: (tester) async {
        await tester.tap(find.bySemanticsLabel('Machine settings').first);
        await settle(tester, steps: 8);
        await tester.ensureVisible(find.text('Pour log'));
        await tester.pump();
        await tester.tap(find.text('Pour log'));
        await settle(tester, steps: 8);
      },
    );
  });

  testWidgets('12g weight running', (tester) async {
    // Пролив по весу в разгаре: в карточке живой отсчёт и цель через стрелку —
    // так же, как в градусах.
    await shoot(
      tester,
      '12g_weight_running',
      withDemo: true,
      scenario: (_, _, _) async {
        await demoWithScale(tester, byWeight: true);
        await slideStart(tester);
        // ждём, пока догреется и пойдёт пролив
        await settle(tester, steps: 90);
      },
    );
  });

  testWidgets('12f shot chart', (tester) async {
    // График пролива отдельно от экрана: сам экран читает кривую с диска, а
    // тестовый рендерер живёт в фальшивом времени и настоящий ввод-вывод не
    // проворачивает. Рисуется здесь ровно тот же виджет, что и в приложении.
    //
    // Кривую строим тем же `CurveRecorder`, что собирает её на живой машине, и
    // кормим его правдоподобным проливом: смачивание тонкой струёй, сухая
    // пауза, экстракция, спуск с упреждением и стекающий хвост.
    const dpr = 2.0;
    tester.view.physicalSize = const Size(390 * dpr, 300 * dpr);
    tester.view.devicePixelRatio = dpr;
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    final at = DateTime(2026, 1, 1, 6);
    final rec = CurveRecorder(startedAt: at);
    var g = 0.0;
    var temp = 93.0;
    for (var ms = 0; ms <= 31000; ms += 100) {
      final t = ms / 1000;
      final flow = t < 5
          ? 0.8
          : t < 10
          ? 0.0
          : t < 27.4
          ? 2.0
          : 0.0;
      g += flow * 0.1;
      // После спуска в чашку стекает то, что осталось в корзине.
      if (t >= 27.4) g += 1.0 * 0.1 * math.exp(-(t - 27.4) / 0.6);
      if (flow > 0) temp -= 0.055;
      rec.addWeight(at.add(Duration(milliseconds: ms)), (g * 10).round() / 10);
      rec.addTemperature(at.add(Duration(milliseconds: ms)), temp.round());
    }
    rec.markStop(at.add(const Duration(milliseconds: 27400)));

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: K.theme(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        home: Scaffold(
          body: AppBackground(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Center(child: ShotChart(curve: rec.build())),
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/12f_shot_chart.png'),
    );
  });

  testWidgets('01 disconnected', (tester) async {
    await shoot(tester, '01_disconnected', scenario: (_, _, _) async {});
  });

  testWidgets('02 connected idle', (tester) async {
    await shoot(
      tester,
      '02_idle',
      scenario: (device, _, _) async {
        device.connect('mock');
        await settle(tester);
      },
    );
  });

  testWidgets('03 heating', (tester) async {
    await shoot(
      tester,
      '03_heating',
      scenario: (device, _, _) async {
        device.connect('mock');
        await settle(tester);
        await slideStart(tester);
        await settle(tester, steps: 8);
      },
    );
  });

  testWidgets('04 brewing', (tester) async {
    await shoot(
      tester,
      '04_brewing',
      scenario: (device, _, _) async {
        device.connect('mock');
        await settle(tester);
        await slideStart(tester);
        // ждём, пока догреется и пойдёт таймлайн фаз
        await settle(tester, steps: 90);
      },
    );
  });

  testWidgets('05 scan sheet', (tester) async {
    await shoot(
      tester,
      '05_scan',
      scenario: (device, _, _) async {
        await tester.tap(find.text('Connect'));
        await tester.pump();
        await settle(tester, steps: 6);
      },
    );
  });

  testWidgets('05b scan sheet with saved device', (tester) async {
    // Машина в списке есть, а в эфире её нет: ряд остаётся на месте, ниже
    // идёт то, что нашёл поиск.
    SharedPreferences.setMockInitialValues({
      'devices': '[{"id":"office-01","name":"Office"}]',
    });
    await shoot(
      tester,
      '05b_scan_saved',
      scenario: (device, _, _) async {
        await tester.tap(find.text('Connect'));
        await tester.pump();
        await settle(tester, steps: 6);
      },
    );
  });

  testWidgets('05c scan sheet with demo row', (tester) async {
    // Путь первого запуска: первый экран → список устройств. Демо стоит там
    // последним и отдельной секцией — не притворяясь машиной.
    await shoot(
      tester,
      '05c_scan_demo',
      withDemo: true,
      scenario: (_, _, _) async {
        await tester.tap(find.text('Connect a machine'));
        await tester.pump();
        await settle(tester, steps: 6);
      },
    );
  });

  testWidgets('06 device sheet', (tester) async {
    await shoot(
      tester,
      '06_settings',
      scenario: (device, _, _) async {
        device.connect('mock');
        await settle(tester);
      },
      after: (tester) async {
        await tester.tap(find.byType(RoundIconButton).first);
        await settle(tester, steps: 6);
      },
    );
  });

  testWidgets('06b temperature sheet', (tester) async {
    await shoot(
      tester,
      '06b_temperature',
      scenario: (device, _, _) async {
        device.connect('mock');
        await settle(tester);
      },
      after: (tester) async {
        await tester.tap(find.text('92°C'));
        await settle(tester, steps: 6);
      },
    );
  });

  testWidgets('06c pour sheet', (tester) async {
    await shoot(
      tester,
      '06c_pour',
      scenario: (device, _, _) async {
        device.connect('mock');
        await settle(tester);
      },
      after: (tester) async {
        await tester.tap(find.text('80 sec'));
        await settle(tester, steps: 6);
      },
    );
  });

  testWidgets('06e timer sheet', (tester) async {
    await shoot(
      tester,
      '06e_timer',
      scenario: (device, _, _) async {
        device.connect('mock');
        await settle(tester);
        device.setSchedule(
          device.appointment.copyWith(enabled: true, hour: 7, minute: 30),
        );
        await settle(tester, steps: 4);
      },
      after: (tester) async {
        // При взведённом таймере ячейка внизу гаснет — лист открывает
        // карточка таймлайна.
        await tester.tap(find.byKey(const ValueKey(StepKind.alarm)));
        await settle(tester, steps: 6);
      },
    );
  });

  testWidgets('06f timer presets', (tester) async {
    await shoot(
      tester,
      '06f_timer_presets',
      scenario: (device, _, _) async {
        device.connect('mock');
        await settle(tester);
      },
      after: (tester) async {
        await tester.tap(find.byKey(const ValueKey(StepKind.alarm)));
        await settle(tester, steps: 6);
      },
    );
  });

  testWidgets('06g timer by time', (tester) async {
    await shoot(
      tester,
      '06g_timer_bytime',
      scenario: (device, _, _) async {
        device.connect('mock');
        await settle(tester);
      },
      after: (tester) async {
        await tester.tap(find.byKey(const ValueKey(StepKind.alarm)));
        await settle(tester, steps: 6);
        // Раскрываем «Ко времени» прямо в этом же листе — второй модалки нет.
        await tester.tap(find.text('At a set time'));
        await settle(tester, steps: 6);
      },
    );
  });

  testWidgets('06d mode sheet', (tester) async {
    await shoot(
      tester,
      '06d_mode_sheet',
      scenario: (device, _, _) async {
        device.connect('mock');
        await settle(tester);
      },
      after: (tester) async {
        // Режим — первая карточка колонки.
        await tester.tap(find.byKey(const ValueKey(StepKind.mode)));
        await settle(tester, steps: 6);
      },
    );
  });

  /// Сцену снимаем отдельно от экрана: фазы цикла считаются по DateTime.now(),
  /// а в widget-тестах часы настоящие — доиграть до экстракции через pump нельзя.
  Future<void> shootScene(
    WidgetTester tester,
    String name,
    SceneState state,
  ) async {
    const dpr = 2.0;
    tester.view.physicalSize = const Size(300 * dpr, 500 * dpr);
    tester.view.devicePixelRatio = dpr;
    addTearDown(tester.view.reset);

    const key = ValueKey('scene');
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: K.theme(),
        home: Scaffold(
          backgroundColor: K.bg0,
          body: Center(
            child: ColoredBox(
              key: key,
              color: K.bg0,
              child: MachineScene(state: state),
            ),
          ),
        ),
      ),
    );

    // Декодирование PNG идёт настоящим асинхроном: без runAsync слои остаются
    // пустыми и в кадр попадает голый фон.
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 600));
    });
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    await expectLater(find.byKey(key), matchesGoldenFile('goldens/$name.png'));
  }

  testWidgets('07 scene extraction', (tester) async {
    await shootScene(
      tester,
      '07_scene_extraction',
      const SceneState(
        connected: true,
        phase: BrewPhase.extraction,
        phaseFraction: 0.7,
        cupFill: 0.7,
        live: true,
      ),
    );
  });

  testWidgets('07b scene done', (tester) async {
    await shootScene(
      tester,
      '07b_scene_done',
      const SceneState(
        connected: true,
        phase: BrewPhase.done,
        phaseFraction: 1,
        cupFill: 1,
        live: false,
      ),
    );
  });

  testWidgets('10 armed alarm', (tester) async {
    await shoot(
      tester,
      '10_armed',
      scenario: (device, _, _) async {
        device.connect('mock');
        await settle(tester);
        device.setSchedule(
          device.appointment.copyWith(enabled: true, hour: 7, minute: 30),
        );
        await settle(tester, steps: 4);
      },
    );
  });

  testWidgets('11 heat only', (tester) async {
    await shoot(
      tester,
      '11_heat_only',
      scenario: (device, prefs, _) async {
        prefs.runMode = WorkMode.heat;
        device.connect('mock');
        await settle(tester);
      },
    );
  });

  testWidgets('09 error', (tester) async {
    await shoot(
      tester,
      '09_error',
      scenario: (device, _, _) async {
        device.connect('mock');
        await settle(tester);
        // Сухой ход: в баке нет воды, греть нечего.
        device.lastFault = MachineError.dryBurning;
        device.lastFaultAt = DateTime(2026, 1, 1, 8, 12);
        await settle(tester, steps: 6);
      },
    );
  });

  testWidgets('08 russian', (tester) async {
    await shoot(
      tester,
      '08_russian',
      scenario: (device, prefs, _) async {
        prefs.localeCode = 'ru';
        device.connect('mock');
        await settle(tester);
      },
    );
  });

  testWidgets('12 advice banner', (tester) async {
    await shoot(
      tester,
      '12_advice_banner',
      scenario: (device, _, _) async {
        device.connect('mock');
        await settle(tester);
        await slideStart(tester);
        // Даём команде пуска долететь до мока: он ставит начало цикла по своим
        // часам, и перемотать их можно только после этого — иначе начало
        // окажется уже за срезом, и «прошло» останется нулём.
        await settle(tester, steps: 12);
        // Перематываем часы за длину цикла — мок домалывает пролив до
        // готовности, и всплывает баннер совета.
        _shotClock = _shotClock.add(const Duration(minutes: 5));
        await settle(tester, steps: 80);
      },
    );
  });

  testWidgets('13 advice page', (tester) async {
    await shoot(
      tester,
      '13_advice',
      scenario: (device, _, _) async {
        device.connect('mock');
        await settle(tester);
      },
      after: (tester) async {
        // Меню машины → «Советы по приготовлению».
        await tester.tap(find.byType(RoundIconButton).first);
        await settle(tester, steps: 6);
        await tester.tap(find.text('Brewing tips'));
        await settle(tester, steps: 6);
        // Отмечаем вкус — появляется разбор и подсветка ручек.
        await tester.tap(find.text('Sour'));
        await settle(tester, steps: 4);
      },
    );
  });

  /// Открыть «Советы» и отметить вкус (и, если задано, тело).
  Future<void> openAdvice(
    WidgetTester tester, {
    required String taste,
    String? body,
  }) async {
    await tester.tap(find.byType(RoundIconButton).first);
    await settle(tester, steps: 6);
    await tester.tap(find.text('Brewing tips'));
    await settle(tester, steps: 6);
    await tester.tap(find.text(taste));
    if (body != null) await tester.tap(find.text(body));
    await settle(tester, steps: 4);
  }

  testWidgets('13b advice bitter', (tester) async {
    await shoot(
      tester,
      '13b_advice_bitter',
      scenario: (device, _, _) async {
        device.connect('mock');
        await settle(tester);
      },
      after: (tester) => openAdvice(tester, taste: 'Bitter'),
    );
  });

  testWidgets('13c advice watery', (tester) async {
    await shoot(
      tester,
      '13c_advice_watery',
      scenario: (device, _, _) async {
        device.connect('mock');
        await settle(tester);
      },
      after: (tester) => openAdvice(tester, taste: 'Watery'),
    );
  });

  testWidgets('13d advice astringent', (tester) async {
    await shoot(
      tester,
      '13d_advice_astringent',
      scenario: (device, _, _) async {
        device.connect('mock');
        await settle(tester);
      },
      after: (tester) => openAdvice(tester, taste: 'Astringent'),
    );
  });

  testWidgets('13e advice conflict', (tester) async {
    await shoot(
      tester,
      '13e_advice_conflict',
      scenario: (device, _, _) async {
        device.connect('mock');
        await settle(tester);
      },
      // Горько + жидкое тело: помол не трогаем, ведём дозой и выходом.
      after: (tester) => openAdvice(tester, taste: 'Bitter', body: 'Thin'),
    );
  });

  testWidgets('13f advice with scale', (tester) async {
    await shoot(
      tester,
      '13f_advice_scale',
      withDemo: true,
      scenario: (_, _, _) async {
        // Демо поднимает весы — появляется рычаг выхода.
        await tester.tap(find.text('Try the demo'));
        await settle(tester, steps: 24);
      },
      after: (tester) => openAdvice(tester, taste: 'Bitter'),
    );
  });
}
