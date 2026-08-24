import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k2pro/ble/k2_device.dart';
import 'package:k2pro/ble/mock_transport.dart';
import 'package:k2pro/ble/cycle.dart';
import 'package:k2pro/model/brew_phase.dart';
import 'package:k2pro/ble/protocol.dart';
import 'package:k2pro/main.dart';
import 'package:k2pro/store/prefs.dart';
import 'package:k2pro/store/recipe_editor.dart';
import 'package:k2pro/ui/sheets/sheet.dart';
import 'package:k2pro/ui/widgets/bottom_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Полный сеанс: подключение, рукопожатие, правка, пуск, телеметрия, стоп.
///
/// Отдельным файлом, потому что проверяет не виджет и не функцию, а связку
/// целиком — ровно тот путь, по которому три дня ловились регрессии на живой
/// машине. Утверждения тут про кадры: что ушло в эфир и в каком порядке.
void main() {
  late Prefs prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await Prefs.load();
  });

  /// Коды команд из всего, что приложение записало.
  List<int> cmds(MockTransport t) => t.sent.map((f) => f[4]).toList();

  /// Нагрузка последнего кадра с этой командой.
  Uint8List payloadOf(MockTransport t, int cmd) =>
      t.sent.lastWhere((f) => f[4] == cmd).sublist(5);

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  /// Устройство на моке с часами теста, погашенное в конце — иначе тикер
  /// телеметрии переживает тело теста, и проверка «таймеров не осталось»
  /// падает раньше, чем успевает отработать teardown.
  Future<void> withDevice(
    WidgetTester tester,
    Future<void> Function(MockTransport mock, K2Device device) body,
  ) async {
    final mock = MockTransport();
    final device = K2Device(mock, now: () => tester.binding.clock.now());
    try {
      await body(mock, device);
    } finally {
      device.dispose();
      await tester.pump();
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

  testWidgets('сеанс целиком: рукопожатие → правка → пуск → стоп', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final mock = MockTransport();
    final device = K2Device(mock);
    final editor = RecipeEditor(device: device, prefs: prefs);
    await tester.pumpWidget(
      K2App(device: device, prefs: prefs, editor: editor),
    );
    await tester.pump();

    try {
      // --- рукопожатие ----------------------------------------------------
      device.connect('mock');
      await settle(tester);

      expect(device.isConnected, isTrue);
      expect(
        cmds(mock),
        containsAllInOrder([
          Cmd.setTime,
          Cmd.getTempSetting,
          Cmd.getWorkParams,
          Cmd.getAppointment,
          Cmd.deviceInfo,
          Cmd.todayCups,
          Cmd.cups,
          Cmd.deviceState,
        ]),
        reason: 'порядок рукопожатия взят у оригинала и держится',
      );
      expect(device.rangesFromDevice, isTrue);
      expect(device.status, isNotNull, reason: 'телеметрия пошла');

      // --- правка ---------------------------------------------------------
      final before = device.deviceRecipe.temperatureC;
      await tester.tap(find.text('$before°C'));
      await settle(tester);
      await tester.tap(find.byType(StepButton).last);
      await settle(tester);
      if (find.byType(BackButton).evaluate().isNotEmpty) {
        await tester.tap(find.byType(BackButton));
      } else {
        await tester.tapAt(const Offset(195, 40));
      }
      await settle(tester);

      expect(device.deviceRecipe.temperatureC, before + 1);
      // Машина хранит уставку в градусах Фаренгейта — сверяем в них.
      expect(
        payloadOf(mock, Cmd.setTempSetting).first,
        celsiusToWire(before + 1),
      );

      // --- пуск -----------------------------------------------------------
      final beforeStart = mock.sent.length;
      await slideStart(tester);
      await settle(tester);

      final afterStart = mock.sent.skip(beforeStart).map((f) => f[4]).toList();
      expect(
        afterStart,
        containsAllInOrder([
          Cmd.setTempSetting,
          Cmd.setWorkParams,
          Cmd.setWorkState,
        ]),
        reason: 'уставки ложатся в машину раньше, чем она по ним заработает',
      );
      expect(payloadOf(mock, Cmd.setWorkState)[0], 1, reason: 'пуск');
      expect(device.isBusy, isTrue);
      expect(device.cycleState, CycleState.running);
      expect(find.text('Stop'), findsOneWidget);

      // --- стоп -----------------------------------------------------------
      await tester.tap(find.text('Stop'));
      await settle(tester);

      expect(payloadOf(mock, Cmd.setWorkState)[0], 0, reason: 'останов');
      expect(device.isBusy, isFalse);
      expect(device.cycleState, CycleState.idle);
      expect(find.text('Slide to start'), findsOneWidget);
    } finally {
      device.dispose();
      await tester.pump();
    }
  });

  testWidgets('спящая машина не запирает кнопку пуска', (tester) async {
    // Машина принимает подключение и молчит. Раньше опрос при этом уходил
    // целиком — восемь запросов по четыре секунды каждый, — и нажатый пуск
    // ждал, пока очередь доедет до него: в живой трассе двадцать две секунды.
    final mock = MockTransport()..mute = true;
    // Часы — те же, что у фейкового времени теста: сон машины меряется
    // молчанием, а молчание — часами.
    final device = K2Device(mock, now: () => tester.binding.clock.now());
    addTearDown(device.dispose);

    device.connect('mock');
    await tester.pump(const Duration(milliseconds: 100));
    for (var i = 0; i < 32; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }

    // Пробный камень отстрелялся и на этом опрос кончился: ничего, кроме
    // setTime, в эфир не ушло.
    expect(cmds(mock).toSet(), {Cmd.setTime});
    expect(device.isAsleep, isTrue);

    // Линия свободна, и кадр пуска уходит сразу, а не в конце чужого опроса.
    device.heatAndBrew();
    await tester.pump(const Duration(milliseconds: 100));
    expect(cmds(mock), contains(Cmd.setWorkState));

    // Машина проснулась — опрос доводится сам, без переподключения.
    mock.mute = false;
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(device.isAsleep, isFalse);
    expect(
      cmds(mock),
      containsAll([Cmd.getTempSetting, Cmd.getWorkParams, Cmd.deviceInfo]),
    );

    await device.disconnect();
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
  });

  testWidgets('цикл: от нажатия до подтверждения кнопка ждёт', (tester) async {
    await withDevice(tester, (mock, device) async {
    device.connect('mock');
    await settle(tester);
    expect(device.cycleState, CycleState.idle);

    device.heat();
    await tester.pump();
    // Кадр только ушёл, машина ещё ничего не сказала.
    expect(device.cycleState, CycleState.starting);
    expect(device.cycleState.isPending, isTrue);

    await settle(tester);
    expect(device.cycleState, CycleState.running);
    expect(device.cycleState.isPending, isFalse);
    });
  });

  testWidgets('потерянный кадр пуска отпускает кнопку через таймаут', (
    tester,
  ) async {
    // Машина уснула сразу после подключения: 0x02 уходит в пустоту.
    await withDevice(tester, (mock, device) async {
    device.connect('mock');
    await settle(tester);
    mock.mute = true;

    device.heat();
    await tester.pump();
    expect(device.cycleState, CycleState.starting);

    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(
      device.cycleState,
      CycleState.idle,
      reason: 'вечный спиннер хуже неотработавшей кнопки',
    );
    });
  });

  testWidgets('нет воды посреди цикла: цикл оборван, ошибка на месте', (
    tester,
  ) async {
    // Живая жалоба: «воды не было, она запикала, но в приложении ошибка не была
    // показана». Код ошибки живёт в телеметрии один пакет — если молча вернуться
    // в покой, показывать становится нечего.
    await withDevice(tester, (mock, device) async {
    device.connect('mock');
    await settle(tester);
    device.heat();
    await settle(tester);
    expect(device.cycleState, CycleState.running);

    // Пикнула и встала.
    mock.fault = MachineError.dryBurning;
    await tester.pump(const Duration(milliseconds: 600));
    mock.fault = MachineError.none;
    await settle(tester);

    expect(device.cycleState, CycleState.faulted);
    expect(device.lastFault, MachineError.dryBurning);

    // «Готово» после такого не показываем: цикла не было.
    expect(device.cycleState, isNot(CycleState.finished));

    device.clearFault();
    await tester.pump();
    expect(device.cycleState, CycleState.idle);
    });
  });

  testWidgets('обрыв связи посреди цикла возвращает экран в покой', (
    tester,
  ) async {
    await withDevice(tester, (mock, device) async {
    device.connect('mock');
    await settle(tester);
    device.heat();
    await settle(tester);
    expect(device.cycleState, CycleState.running);

    mock.dropLink();
    await tester.pump();
    expect(device.cycleState, CycleState.idle);
    expect(device.progress.phase, BrewPhase.idle);
    });
  });
}
