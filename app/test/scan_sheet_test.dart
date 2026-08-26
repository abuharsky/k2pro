import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k2pro/ble/demo.dart';
import 'package:k2pro/ble/k2_device.dart';
import 'package:k2pro/ble/mock_transport.dart';
import 'package:k2pro/ble/scale/mock_scale_transport.dart';
import 'package:k2pro/ble/scale/scale_device.dart';
import 'package:k2pro/ble/switchable_transport.dart';
import 'package:k2pro/main.dart';
import 'package:k2pro/store/prefs.dart';
import 'package:k2pro/store/recipe_editor.dart';
import 'package:k2pro/ui/home_page.dart';
import 'package:k2pro/ui/sheets/sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Лист подключения и лишние нажатия.
///
/// Лист закрывает себя сам — после подключения, которое идёт секундами. Всё
/// это время он остаётся на экране, а человек, не увидев отклика, жмёт ещё
/// раз. Если каждое нажатие снимает с навигатора верхний маршрут, второе
/// снимает уже не лист, а главный экран: навигатор пустеет, и остаётся чёрное
/// поле, из которого нет выхода. Здесь проверяется, что лишние нажатия
/// закрывают ровно лист — и ничего под ним.
void main() {
  late Prefs prefs;
  late K2Device device;
  late ScaleDevice scale;
  late Demo demo;

  /// Приложение с уже добавленной машиной: развилка в `K2App` показывает
  /// главный экран, и он — единственное, что лежит под листом.
  Future<void> withApp(
    WidgetTester tester,
    Future<void> Function() body,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({
      'devices': '[{"id":"$kMockMachineId","name":"BL_PCM03_SIM"}]',
      'last_device_id': kMockMachineId,
    });
    prefs = await Prefs.load();
    final machineLink = SwitchableTransport(MockTransport());
    final scaleLink = SwitchableTransport(MockScaleTransport());
    device = K2Device(machineLink);
    scale = ScaleDevice(scaleLink);
    demo = Demo(
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
        editor: RecipeEditor(device: device, prefs: prefs),
        demo: demo,
      ),
    );
    try {
      await body();
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

  /// Открыть лист кнопкой связи в шапке.
  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(find.bySemanticsLabel('Bluetooth devices').first);
    await settle(tester, steps: 6);
    expect(find.byType(SheetShell), findsOneWidget);
  }

  testWidgets('двойной тап по подключённой машине не уносит главный экран', (
    tester,
  ) async {
    await withApp(tester, () async {
      await settle(tester);
      expect(device.isConnected, isTrue);
      await openSheet(tester);

      // Два нажатия до следующего кадра: приложение занято связью, кадры
      // выходят рывками, и второе нажатие уходит в тот же кадр, что первое.
      await tester.tap(find.text('BL_PCM03_SIM'));
      await tester.tap(find.text('BL_PCM03_SIM'), warnIfMissed: false);
      await settle(tester);

      expect(find.byType(SheetShell), findsNothing);
      expect(find.byType(HomePage), findsOneWidget);
    });
  });

  testWidgets('лишние тапы по демо не уносят главный экран', (tester) async {
    await withApp(tester, () async {
      await settle(tester);
      await openSheet(tester);

      // Вход в демо идёт не мгновенно: сперва разрыв прежней связи. Всё это
      // время ряд остаётся под пальцем, и второе нажатие не должно ни закрыть
      // лист раньше времени, ни тем более снять маршрут под ним. Оба нажатия
      // уходят в один кадр — так это и выглядит на занятом связью приложении.
      await tester.tap(find.text('Demo mode'));
      await tester.tap(find.text('Demo mode'), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 16));
      expect(demo.on, isTrue);

      // Лист закрывается сам — но только когда демо поднялось. Уехать раньше
      // он не имеет права: это значит, что маршрут снял лишний тап.
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        find.byType(SheetShell),
        findsOneWidget,
        reason: 'лист уехал раньше времени',
      );

      await settle(tester);

      expect(demo.on, isTrue);
      expect(find.byType(SheetShell), findsNothing);
      expect(find.byType(HomePage), findsOneWidget);
      expect(find.text('DEMO'), findsOneWidget);
    });
  });
}
