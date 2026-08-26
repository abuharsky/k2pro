import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k2pro/ble/demo.dart';
import 'package:k2pro/ble/k2_device.dart';
import 'package:k2pro/ble/protocol.dart';
import 'package:k2pro/ble/scale/scale_device.dart';
import 'package:k2pro/ble/switchable_transport.dart';
import 'package:k2pro/main.dart';
import 'package:k2pro/store/prefs.dart';
import 'package:k2pro/store/recipe_editor.dart';
import 'package:k2pro/ui/journal_page.dart';
import 'package:k2pro/ui/sheets/sheet.dart';
import 'package:k2pro/ui/theme.dart';
import 'package:k2pro/ui/widgets/scale_button.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'silent_transport.dart';

/// Интерфейс весов на симуляторе: живого железа у нас нет, а проверять надо.
///
/// Демо поднимает машину и весы разом, симулятор весов шлёт настоящие кадры
/// DOT — так что здесь проверяется тот же путь, что пойдёт на живых весах, до
/// самой отрисовки карточки.
void main() {
  late Prefs prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await Prefs.load();
  });

  Future<void> withApp(
    WidgetTester tester,
    Future<void> Function(Demo demo, K2Device device, ScaleDevice scale) body,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final machineLink = SwitchableTransport(SilentTransport());
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
      await body(demo, device, scale);
    } finally {
      demo.dispose();
      device.dispose();
      scale.dispose();
      editor.dispose();
      await tester.pump();
    }
  }

  Future<void> settle(WidgetTester tester, {int steps = 24}) async {
    for (var i = 0; i < steps; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  testWidgets('без весов карточки веса нет', (tester) async {
    await withApp(tester, (demo, device, scale) async {
      unawaited(demo.enter());
      await settle(tester);
      expect(find.text('WEIGHT'), findsOneWidget);

      // Весы унесли со стола: карточка уходит вместе с ними. Показывать цель,
      // которую нечем измерить, значит обещать несделанное.
      unawaited(scale.disconnect());
      await settle(tester);
      expect(find.text('WEIGHT'), findsNothing);
      expect(find.byType(ScaleButton), findsNothing);
    });
  });

  testWidgets('весы дают карточку и кнопку внизу', (tester) async {
    await withApp(tester, (demo, device, scale) async {
      // Не ждём: пока демо поднимается, время двигают именно pump-ы.
      unawaited(demo.enter());
      await settle(tester);

      expect(scale.isLive, isTrue, reason: 'симулятор весов должен отвечать');
      expect(find.text('WEIGHT'), findsOneWidget);
      // Кнопка в нижнем ряду: живой вес видно, не открывая ничего.
      expect(find.byType(ScaleButton), findsOneWidget);
    });
  });

  testWidgets('по времени карточка веса только показывает', (tester) async {
    await withApp(tester, (demo, device, scale) async {
      // Не ждём: пока демо поднимается, время двигают именно pump-ы.
      unawaited(demo.enter());
      await settle(tester);

      // Отсечка выключена: цели карточка не заказывала и показывает живой вес.
      expect(prefs.gravimetry.stopOnYield, isFalse);
      expect(find.textContaining('36.0'), findsNothing);
    });
  });

  testWidgets('отсечка задирает секунды к потолку и возвращает их', (
    tester,
  ) async {
    await withApp(tester, (demo, device, scale) async {
      // Не ждём: пока демо поднимается, время двигают именно pump-ы.
      unawaited(demo.enter());
      await settle(tester);

      final mock = demo.machineMock!;
      final wasSeconds = device.workParams.extraction.value;
      final ceiling = device.workParams.extraction.max;
      expect(ceiling, greaterThan(wasSeconds));

      Future<void> toggle() async {
        await tester.tap(find.text('WEIGHT'));
        await settle(tester);
        await tester.tap(find.byType(KSwitch));
        await settle(tester);
        await tester.tapAt(const Offset(195, 60)); // мимо листа — закрыть
        await settle(tester);
      }

      List<int> lastParams() => mock.sent
          .where((f) => f[4] == Cmd.setWorkParams && f.length > 8)
          .last
          .toList();

      await toggle();
      expect(prefs.gravimetry.stopOnYield, isTrue);
      expect(prefs.gravimetry.secondsBeforeAutoStop, wasSeconds);
      expect(
        lastParams()[8],
        ceiling,
        reason: 'секунды стали предохранителем и уехали к потолку',
      );

      await toggle();
      expect(prefs.gravimetry.stopOnYield, isFalse);
      expect(
        lastParams()[8],
        wasSeconds,
        reason: 'выключили отсечку — вернули то, что человек выставил сам',
      );
    });
  });

  testWidgets('счётчик веса: тап — десятая, удержание — по грамму', (
    tester,
  ) async {
    await withApp(tester, (demo, device, scale) async {
      unawaited(demo.enter());
      await settle(tester);

      await tester.tap(find.text('WEIGHT'));
      await settle(tester);

      // Кнопки счётчика по порядку: цель −, цель +, доза −, доза +.
      final targetPlus = find.byType(StepButton).at(1);

      final t0 = prefs.gravimetry.targetG;
      await tester.tap(targetPlus);
      await settle(tester);
      expect(
        prefs.gravimetry.targetG,
        closeTo(t0 + 0.1, 1e-9),
        reason: 'одиночный тап двигает на десятую',
      );

      final t1 = prefs.gravimetry.targetG;
      await tester.longPress(targetPlus);
      await settle(tester);
      expect(
        prefs.gravimetry.targetG,
        greaterThanOrEqualTo(t1 + 1.0),
        reason: 'удержание идёт по грамму за шаг',
      );
    });
  });

  testWidgets('кнопка весов открывает взвешивание', (tester) async {
    await withApp(tester, (demo, device, scale) async {
      // Не ждём: пока демо поднимается, время двигают именно pump-ы.
      unawaited(demo.enter());
      await settle(tester);

      await tester.tap(find.byType(ScaleButton));
      await settle(tester);

      // Диалог — чистый прибор: имя весов, цифра и тара одной буквой.
      expect(find.text('DOT'), findsOneWidget);
      expect(find.text('T'), findsOneWidget);
      expect(find.byType(JournalPage), findsNothing);
    });
  });

  testWidgets('журнал живёт в настройках машины и без весов', (tester) async {
    await withApp(tester, (demo, device, scale) async {
      unawaited(demo.enter());
      await settle(tester);

      // Гамбургер: журнал стоит там всегда — он про машину, а не про весы.
      await tester.tap(find.bySemanticsLabel('Machine settings').first);
      await settle(tester);
      await tester.ensureVisible(find.text('Pour log'));
      await tester.pump();
      await tester.tap(find.text('Pour log'));
      await settle(tester);

      expect(find.byType(JournalPage), findsOneWidget);
      // Проливов ещё не было — журнал говорит об этом, а не рисует пустой
      // график.
      expect(find.text('No pours yet'), findsOneWidget);
    });
  });
}
