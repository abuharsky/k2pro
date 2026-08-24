import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k2pro/ble/k2_device.dart';
import 'package:k2pro/ble/mock_transport.dart';
import 'package:k2pro/ble/protocol.dart';
import 'package:k2pro/main.dart';
import 'package:k2pro/model/brew_phase.dart';
import 'package:k2pro/store/prefs.dart';
import 'package:k2pro/store/recipe_editor.dart';
import 'package:k2pro/ui/scene/machine_scene.dart';
import 'package:k2pro/ui/scene/scene_state.dart';
import 'package:k2pro/ui/theme.dart';
import 'package:k2pro/ui/widgets/cycle_timeline.dart';
import 'package:k2pro/ui/widgets/bottom_bar.dart';
import 'package:k2pro/ui/widgets/round_button.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Рендер экранов в PNG (в обычный прогон flutter test не попадает —
/// каталог вне test/):
///   flutter test tool/screenshots --update-goldens
/// Результат — tool/screenshots/goldens/*.png
///
/// Шрифты подгружаются из кеша SDK, иначе тестовый рендерер рисует текст
/// прямоугольниками.
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

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> shoot(
    WidgetTester tester,
    String name, {
    required Future<void> Function(K2Device device, Prefs prefs) scenario,
    Future<void> Function(WidgetTester tester)? after,
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
    final device = K2Device(
      MockTransport(),
      now: () => DateTime(2026, 1, 1, 6),
    );
    final editor = RecipeEditor(device: device, prefs: prefs);
    await tester.pumpWidget(
      K2App(device: device, prefs: prefs, editor: editor),
    );
    await tester.pump();
    try {
      await scenario(device, prefs);
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
      device.dispose();
      await tester.pump();
    }
  }

  Future<void> settle(WidgetTester tester, {int steps = 12}) async {
    for (var i = 0; i < steps; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  Future<void> slideStart(WidgetTester tester) async {
    final bar = tester.getRect(find.byType(BottomBar));
    final gesture = await tester.startGesture(
      Offset(bar.left + 48, bar.center.dy),
    );
    await gesture.moveBy(const Offset(250, 0));
    await gesture.up();
    await tester.pump();
  }

  testWidgets('01 disconnected', (tester) async {
    await shoot(tester, '01_disconnected', scenario: (_, _) async {});
  });

  testWidgets('02 connected idle', (tester) async {
    await shoot(
      tester,
      '02_idle',
      scenario: (device, _) async {
        device.connect('mock');
        await settle(tester);
      },
    );
  });

  testWidgets('03 heating', (tester) async {
    await shoot(
      tester,
      '03_heating',
      scenario: (device, _) async {
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
      scenario: (device, _) async {
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
      scenario: (device, _) async {
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
      scenario: (device, _) async {
        await tester.tap(find.text('Connect'));
        await tester.pump();
        await settle(tester, steps: 6);
      },
    );
  });

  testWidgets('06 device sheet', (tester) async {
    await shoot(
      tester,
      '06_settings',
      scenario: (device, _) async {
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
      scenario: (device, _) async {
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
      scenario: (device, _) async {
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
      scenario: (device, _) async {
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

  testWidgets('06d mode sheet', (tester) async {
    await shoot(
      tester,
      '06d_mode_sheet',
      scenario: (device, _) async {
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
      scenario: (device, _) async {
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
      scenario: (device, prefs) async {
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
      scenario: (device, _) async {
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
      scenario: (device, prefs) async {
        prefs.localeCode = 'ru';
        device.connect('mock');
        await settle(tester);
      },
    );
  });
}
