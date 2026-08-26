import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k2pro/ble/demo.dart';
import 'package:k2pro/ble/k2_device.dart';
import 'package:k2pro/ble/scale/scale_device.dart';
import 'package:k2pro/ble/switchable_transport.dart';
import 'package:k2pro/ble/transport.dart';
import 'package:k2pro/main.dart';
import 'package:k2pro/store/prefs.dart';
import 'package:k2pro/store/recipe_editor.dart';
import 'package:k2pro/ui/home_page.dart';
import 'package:k2pro/ui/sheets/sheet.dart';
import 'package:k2pro/ui/welcome_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'silent_transport.dart';

/// Приложение целиком: устройства, переходники и демо поверх них.
typedef Rig = ({
  K2Device device,
  ScaleDevice scale,
  Demo demo,
  SwitchableTransport machineLink,
  K2Transport realMachine,
});

void main() {
  late Prefs prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await Prefs.load();
  });

  /// Собрать приложение так же, как это делает `main`: между устройством и
  /// эфиром переходник, поверх — демо-режим. Таймеры гасим до конца теста:
  /// симулятор тикает, пока его не закрыли.
  Future<void> withApp(
    WidgetTester tester,
    Future<void> Function(Rig r) body,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final realMachine = SilentTransport();
    final machineLink = SwitchableTransport(realMachine);
    final scaleLink = SwitchableTransport(SilentTransport());
    final device = K2Device(machineLink);
    final scale = ScaleDevice(scaleLink);
    final editor = RecipeEditor(device: device, prefs: prefs);
    final demo = Demo(
      machineLink: machineLink,
      scaleLink: scaleLink,
      device: device,
      scale: scale,
      prefs: prefs,
    );

    await tester.pumpWidget(
      K2App(
        device: device,
        scale: scale,
        prefs: prefs,
        editor: editor,
        demo: demo,
      ),
    );
    await tester.pump();
    try {
      await body((
        device: device,
        scale: scale,
        demo: demo,
        machineLink: machineLink,
        realMachine: realMachine,
      ));
    } finally {
      demo.dispose();
      device.dispose();
      scale.dispose();
      await tester.pump();
    }
  }

  Future<void> settle(WidgetTester tester, {int steps = 24}) async {
    for (var i = 0; i < steps; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  testWidgets('первый запуск предлагает машину или демо', (tester) async {
    await withApp(tester, (r) async {
      expect(find.byType(WelcomePage), findsOneWidget);
      expect(find.byType(HomePage), findsNothing);
      expect(find.text('Connect a machine'), findsOneWidget);
      expect(find.text('Try the demo'), findsOneWidget);
    });
  });

  testWidgets('демо поднимает и машину, и весы', (tester) async {
    await withApp(tester, (r) async {
      await tester.tap(find.text('Try the demo'));
      await settle(tester);

      expect(r.device.isConnected, isTrue);
      expect(r.scale.isConnected, isTrue);
      // Симулятор отвечает настоящими кадрами, поэтому телеметрия, диапазоны и
      // анкета приезжают ровно так же, как с живой машины.
      expect(r.device.status, isNotNull);
      expect(r.device.tempLimits.target, 92);
      expect(r.device.info?.model, 'PCM03SPRO');

      // Первый экран уступил место главному, и демо на нём помечено.
      expect(find.byType(HomePage), findsOneWidget);
      expect(find.text('DEMO'), findsOneWidget);
    });
  });

  testWidgets('демо не оставляет следов', (tester) async {
    await withApp(tester, (r) async {
      final wasRecipe = prefs.recipe;

      await tester.tap(find.text('Try the demo'));
      await settle(tester);

      expect(r.demo.on, isTrue);
      // Демо-машина не попадает ни в список, ни в «последнюю»: иначе при
      // следующем запуске автоподключение ушло бы искать симулятор в эфире.
      expect(prefs.devices, isEmpty);
      expect(prefs.lastDeviceId, isNull);
      // И уставки симулятора не перетирают кэш настоящей машины.
      expect(prefs.ranges, isNull);
      expect(prefs.recipe.matches(wasRecipe), isTrue);
    });
  });

  testWidgets('демо живёт в списке устройств, а не в настройках', (
    tester,
  ) async {
    await withApp(tester, (r) async {
      // Первый экран ведёт в тот же список, что и кнопка связи на главном.
      await tester.tap(find.text('Connect a machine'));
      await settle(tester, steps: 6);

      // Ряд стоит своей секцией, последним — ниже всего, что про настоящие
      // машины. Метки в шапке здесь быть не может: она живёт на главном
      // экране, а мы ещё на первом.
      expect(find.text('DEMO'), findsOneWidget);
      expect(find.text('Demo mode'), findsOneWidget);
      expect(find.text('Simulated machine and scale'), findsOneWidget);

      await tester.tap(find.text('Demo mode'));
      await settle(tester);

      expect(r.demo.on, isTrue);
      expect(r.device.isConnected, isTrue);
      expect(r.scale.isConnected, isTrue);
      // Лист закрылся сам, как и после подключения к настоящей машине.
      expect(find.byType(SheetShell), findsNothing);
      expect(find.byType(HomePage), findsOneWidget);
    });
  });

  testWidgets('из демо выходят «отключиться», а не отдельным пунктом', (
    tester,
  ) async {
    await withApp(tester, (r) async {
      await tester.tap(find.text('Try the demo'));
      await settle(tester);
      expect(r.demo.on, isTrue);

      // Шторка машины: никаких «выйти из демо», обычное «отключиться».
      await tester.tap(find.text('K2 Pro'));
      await settle(tester, steps: 6);
      expect(find.text('Demo mode'), findsOneWidget); // подпись вместо прошивки
      // Шторка машины стала длиннее — журнал добавил ряд, — и «Отключиться»
      // ушло за нижний край. Она прокручивается, тест тоже должен.
      await tester.ensureVisible(find.text('Disconnect'));
      await tester.pump();
      await tester.tap(find.text('Disconnect'));
      await settle(tester);

      expect(r.demo.on, isFalse);
      expect(identical(r.machineLink.inner, r.realMachine), isTrue);
      expect(find.byType(WelcomePage), findsOneWidget);
    });
  });

  testWidgets('выход из демо возвращает эфир', (tester) async {
    await withApp(tester, (r) async {
      await tester.tap(find.text('Try the demo'));
      await settle(tester);
      expect(identical(r.machineLink.inner, r.realMachine), isFalse);

      await r.demo.leave();
      await settle(tester);

      expect(r.demo.on, isFalse);
      expect(identical(r.machineLink.inner, r.realMachine), isTrue);
      expect(r.device.isConnected, isFalse);
      expect(r.scale.isConnected, isFalse);
      // Машины по-прежнему ни одной — значит, снова первый экран.
      expect(find.byType(WelcomePage), findsOneWidget);
    });
  });
}
