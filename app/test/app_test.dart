import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k2pro/ble/k2_device.dart';
import 'package:k2pro/ble/mock_transport.dart';
import 'package:k2pro/ble/scale/mock_scale_transport.dart';
import 'package:k2pro/ble/scale/scale_device.dart';
import 'package:k2pro/ble/protocol.dart';
import 'package:k2pro/main.dart';
import 'package:k2pro/model/recipe.dart';
import 'package:k2pro/store/prefs.dart';
import 'package:k2pro/store/recipe_editor.dart';
import 'package:k2pro/ui/sheets/sheet.dart';
import 'package:k2pro/ui/widgets/cycle_timeline.dart';
import 'package:k2pro/ui/widgets/bottom_bar.dart';
import 'package:k2pro/ui/widgets/round_button.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// В testWidgets время фальшивое: Future.delayed внутри транспорта
/// продвигается только через tester.pump, поэтому device-вызовы не await-им.
void main() {
  late Prefs prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await Prefs.load();
  });

  /// Прогнать сценарий на симуляторе машины и погасить таймеры до конца теста.
  Future<void> withApp(
    WidgetTester tester,
    Future<void> Function(K2Device device) body, {
    MockTransport? transport,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final device = K2Device(transport ?? MockTransport());
    final scale = ScaleDevice(MockScaleTransport());
    final editor = RecipeEditor(device: device, prefs: prefs);
    await tester.pumpWidget(
      K2App(device: device, scale: scale, prefs: prefs, editor: editor),
    );
    await tester.pump();
    try {
      await body(device);
    } finally {
      device.dispose();
      await tester.pump();
    }
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  /// Провести по главной кнопке. Ею подтверждают и пуск с нагревом, и стоп.
  Future<void> slideCta(WidgetTester tester) async {
    final bar = tester.getRect(find.byType(BottomBar));
    final gesture = await tester.startGesture(
      Offset(bar.left + 48, bar.center.dy),
    );
    await gesture.moveBy(const Offset(250, 0));
    await gesture.up();
    await tester.pump();
  }

  testWidgets('главный экран рисуется до подключения', (tester) async {
    await withApp(tester, (device) async {
      // Ни заголовка, ни подписи статуса на экране нет: состояние показывает
      // сама сцена, а из текста внизу — только кнопка.
      expect(find.text('Connect'), findsOneWidget);
    });
  });

  testWidgets('поиск, подключение и рукопожатие', (tester) async {
    await withApp(tester, (device) async {
      await tester.tap(find.text('Connect'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.textContaining(kNamePrefix), findsOneWidget);
      await tester.tap(find.textContaining(kNamePrefix));
      await settle(tester);

      expect(device.isConnected, isTrue);
      expect(device.tempLimits.target, 92);
      expect(device.workParams.pressure.max, 15);
      expect(device.info?.model, 'PCM03SPRO');

      expect(find.text('Slide to start'), findsOneWidget);
      // Таймлайн показывает то, что лежит в машине: 92 °C и весь пролив
      // одной строкой — 5 смачивания, 5 паузы и 70 экстракции.
      expect(find.text('92\u00b0C'), findsOneWidget);
      expect(find.text('80 sec'), findsOneWidget);
    });
  });

  testWidgets('диапазоны машины переживают перезапуск', (tester) async {
    await withApp(tester, (device) async {
      await tester.tap(find.text('Connect'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.textContaining(kNamePrefix));
      await settle(tester);
      expect(device.rangesFromDevice, isTrue);
    });

    // Следующий запуск начинается с того, чем машина отозвалась в прошлый:
    // ждать её ответа, чтобы открыть правку, больше не нужно.
    final saved = prefs.ranges;
    expect(saved, isNotNull);
    expect(saved!.params.pressure.max, 15);

    final fresh = K2Device(MockTransport());
    addTearDown(fresh.dispose);
    RecipeEditor(device: fresh, prefs: prefs);
    expect(fresh.isConnected, isFalse);
    expect(fresh.workParams.pressure.max, 15);
    expect(fresh.tempLimits.max, saved.limits.max);
    // Но это именно кэш: настоящим он станет, только когда машина ответит.
    expect(fresh.rangesFromDevice, isFalse);
  });

  testWidgets('оборванная связь восстанавливается сама', (tester) async {
    final mock = MockTransport();
    await withApp(tester, (device) async {
      await tester.tap(find.text('Connect'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.textContaining(kNamePrefix));
      await settle(tester);
      expect(device.isConnected, isTrue);

      // Машину унесли: обрыв не по нашей воле.
      mock.dropLink();
      await tester.pump();
      expect(device.isConnected, isFalse);
      // Но намерение остаётся: к этой машине мы подключались и не отказывались.
      expect(device.connectedId, isNotNull);

      // Первая попытка идёт через kReconnectFirstDelay, плюс время самого
      // подключения в симуляторе.
      await tester.pump(kReconnectFirstDelay);
      await tester.pump(const Duration(seconds: 1));
      expect(device.isConnected, isTrue);
      // Рукопожатие после переподключения идёт заново — дать ему добежать,
      // иначе тест закончится с висящими таймерами записи.
      await settle(tester);
    }, transport: mock);
  });

  testWidgets('после ручного отключения никто не переподключается', (
    tester,
  ) async {
    final mock = MockTransport();
    await withApp(tester, (device) async {
      await tester.tap(find.text('Connect'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.textContaining(kNamePrefix));
      await settle(tester);
      expect(device.isConnected, isTrue);

      await device.disconnect();
      await tester.pump();
      expect(device.connectedId, isNull);

      await tester.pump(kReconnectFirstDelay * 4);
      await tester.pump(const Duration(seconds: 1));
      expect(device.isConnected, isFalse);
    }, transport: mock);
  });

  test('без кэша диапазоны всё равно есть — иначе нечем ограничить правку', () {
    final d = K2Device(MockTransport());
    addTearDown(d.dispose);
    expect(d.tempLimits.min, kFallbackLimits.min);
    expect(d.workParams.extraction.max, kFallbackParams.extraction.max);
  });

  testWidgets('добавленная машина остаётся в списке и без эфира', (
    tester,
  ) async {
    await withApp(tester, (device) async {
      await tester.tap(find.text('Connect'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.textContaining(kNamePrefix));
      await settle(tester);

      expect(prefs.devices.single.id, 'mock-k2pro');
      // Рекламное имя живёт в списке; в шапке, пока машину не назвали
      // своими словами, стоит «K2 Pro».
      expect(find.text('K2 Pro'), findsOneWidget);

      // Разрыв связи не выкидывает машину из списка: она стоит на своём
      // месте с пометкой, что сейчас её не слышно.
      await device.disconnect();
      await settle(tester);
      await tester.tap(find.text('Connect'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('MY DEVICES'), findsOneWidget);
      expect(find.text('Not in range'), findsOneWidget);
      expect(find.text('Disconnect'), findsNothing);

      // Как только машина отозвалась, тот же ряд снова зовёт подключиться —
      // и дублем в «рядом» не появляется.
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Not in range'), findsNothing);
      expect(find.text('-47 dBm'), findsOneWidget);
    });
  });

  testWidgets('забыть машину можно только из меню', (tester) async {
    SharedPreferences.setMockInitialValues({
      'devices':
          '[{"id":"mock-k2pro","name":"BL_PCM03_SIM","alias":"Kitchen"}]',
      'last_device_id': 'mock-k2pro',
    });
    prefs = await Prefs.load();

    await withApp(tester, (device) async {
      await settle(tester);
      expect(device.isConnected, isTrue);
      expect(find.text('Kitchen'), findsOneWidget);

      await tester.tap(find.byType(RoundIconButton).first);
      await settle(tester);
      await tester.ensureVisible(find.text('Forget device'));
      await tester.tap(find.text('Forget device'));
      await settle(tester);
      await tester.tap(find.text('Forget'));
      await settle(tester);

      expect(prefs.devices, isEmpty);
      expect(prefs.lastDeviceId, isNull);
      expect(device.isConnected, isFalse);
    });
  });

  testWidgets('время будильника уезжает одним кадром, а не каждым шагом', (
    tester,
  ) async {
    final mock = MockTransport();
    await withApp(tester, (device) async {
      device.connect('mock');
      await settle(tester);

      int writes() => mock.sent.where((f) => f[4] == Cmd.setAppointment).length;
      final before = writes();

      // Так выглядит прокрутка колеса: шаг за шагом, быстрее паузы записи.
      for (var i = 1; i <= 6; i++) {
        device.setSchedule(device.appointment.copyWith(hour: 6 + i));
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(writes(), before, reason: 'пока крутят — не пишем');

      await settle(tester);
      expect(writes(), before + 1, reason: 'уезжает только последнее значение');
      expect(mock.sent.last[6], 12, reason: 'и это шесть плюс шесть часов');
    }, transport: mock);
  });

  testWidgets('кнопки «применить» на экране нет', (tester) async {
    await withApp(tester, (device) async {
      device.connect('mock');
      await settle(tester);
      expect(find.text('Apply to machine'), findsNothing);
    });
  });

  testWidgets('панель показывает параметры машины, а не пресет', (
    tester,
  ) async {
    await withApp(tester, (device) async {
      device.connect('mock');
      await settle(tester);

      expect(find.text('92\u00b0C'), findsOneWidget);
      expect(find.text('80 sec'), findsOneWidget);
      // Смачивание и пауза — фазы внутри пролива, отдельных карточек у них
      // нет: в колонке всего четыре шага.
      expect(find.text('5 sec'), findsNothing);
      // Пресетов на экране нет вообще.
      expect(find.text('Medium-dark'), findsNothing);
    });
  });

  testWidgets('правка температуры уходит в машину и оседает в кэше', (
    tester,
  ) async {
    await withApp(tester, (device) async {
      device.connect('mock');
      await settle(tester);

      final before = device.deviceRecipe.temperatureC;
      // Тап по ячейке открывает лист, шаг делает уже «плюс» внутри него.
      await tester.tap(find.text('$before\u00b0C'));
      await settle(tester);
      await tester.tap(find.byType(StepButton).last);
      await settle(tester);

      expect(device.deviceRecipe.temperatureC, before + 1);
      expect(prefs.recipe.temperatureC, before + 1);
    });
  });

  testWidgets('правка пролива меняет экстракцию шагом 5 с', (tester) async {
    await withApp(tester, (device) async {
      device.connect('mock');
      await settle(tester);

      final before = device.deviceRecipe.extractionSeconds;
      final whole =
          before +
          device.deviceRecipe.preInfusionSeconds +
          device.deviceRecipe.standstillSeconds;
      // Тап по карточке пролива открывает лист со всеми временами цикла.
      await tester.tap(find.text('$whole sec'));
      await settle(tester);
      // Ряды идут смачивание → пауза → экстракция: «плюс» экстракции —
      // шестая кнопка листа.
      await tester.tap(find.byType(StepButton).at(5));
      await settle(tester);

      expect(device.deviceRecipe.extractionSeconds, before + 5);
    });
  });

  testWidgets('запуск цикла включает «Стоп»', (tester) async {
    await withApp(tester, (device) async {
      device.connect('mock');
      await settle(tester);

      // Обычный тап не должен случайно включать нагреватель.
      await tester.tapAt(tester.getRect(find.byType(BottomBar)).center);
      await tester.pump(const Duration(milliseconds: 200));
      expect(device.isBusy, isFalse);

      await slideCta(tester);
      await settle(tester);

      expect(device.isBusy, isTrue);
      expect(find.text('Stop'), findsOneWidget);

      // Стоп тоже жестом: тап по идущему проливу цикл не рвёт.
      await tester.tapAt(tester.getRect(find.byType(BottomBar)).center);
      await tester.pump(const Duration(milliseconds: 200));
      expect(device.isBusy, isTrue);

      await slideCta(tester);
      await settle(tester);
      expect(device.isBusy, isFalse);
    });
  });

  testWidgets('баннер разбора выключается в настройках', (tester) async {
    // Часы мока перематываемы: цикл он считает по своему времени, и без
    // перемотки готовности не дождаться — фейковый pump двигает таймеры,
    // а не часы.
    var clock = DateTime(2026, 1, 1, 8);
    await withApp(tester, (device) async {
      device.connect('mock');
      await settle(tester);
      await slideCta(tester);
      await settle(tester);

      clock = clock.add(const Duration(minutes: 5));
      for (var i = 0; i < 8; i++) {
        await settle(tester);
      }
      expect(find.text('How did it turn out?'), findsOneWidget);

      // Кто уже свёл рецепт, гасит баннер насовсем — и он не возвращается
      // ни с этой чашкой, ни со следующей.
      prefs.adviceBanner = false;
      await tester.pump();
      expect(find.text('How did it turn out?'), findsNothing);
    }, transport: MockTransport(now: () => clock));
  });

  testWidgets('ошибка блокирует пуск до явной проверки', (tester) async {
    await withApp(tester, (device) async {
      device.connect('mock');
      await settle(tester);

      device.lastFault = MachineError.dryBurning;
      device.lastFaultAt = DateTime(2026, 1, 1, 8, 12);
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('Add water'), findsWidgets);
      expect(find.text('Slide to start'), findsNothing);

      await tester.tap(find.text('Check again'));
      await tester.pump();
      expect(find.text('Slide to start'), findsOneWidget);
    });
  });

  testWidgets('единицы температуры доступны из меню машины', (tester) async {
    await withApp(tester, (device) async {
      device.connect('mock');
      await settle(tester);

      await tester.tap(find.byType(RoundIconButton).first);
      await settle(tester);
      expect(find.text('92°C'), findsWidgets);

      await tester.tap(find.text('Temperature unit'));
      await tester.pump();
      expect(prefs.fahrenheit, isTrue);
      expect(find.text('198°F'), findsWidgets);
    });
  });

  testWidgets('запуск по времени требует подтверждения', (tester) async {
    await withApp(tester, (device) async {
      device.connect('mock');
      await settle(tester);

      await tester.tap(find.byKey(const ValueKey(StepKind.alarm)));
      await settle(tester);
      // Быстрые пресеты — без диалога; подтверждение осталось на «Ко времени».
      await tester.tap(find.text('At a set time'));
      await settle(tester);
      await tester.ensureVisible(find.text('Schedule'));
      await tester.tap(find.text('Schedule'));
      await tester.pump();

      expect(find.text('Enable scheduled start?'), findsOneWidget);
      expect(device.appointment.enabled, isFalse);

      await tester.tap(find.text('Enable'));
      await settle(tester);
      expect(device.appointment.enabled, isTrue);
    });
  });

  test('каждый режим помнит свой набор уставок', () async {
    SharedPreferences.setMockInitialValues({});
    final p = await Prefs.load();

    // Эспрессо на «нагрев + пролив»: предсмачивание и паузы важны.
    p.runMode = WorkMode.heatAndBrew;
    p.recipe = Recipe.fallback.copyWith(
      preInfusionSeconds: 6,
      standstillSeconds: 7,
      extractionSeconds: 40,
    );

    // Американо на «проливе»: просто кипяток, без пауз.
    p.runMode = WorkMode.brew;
    p.recipe = Recipe.fallback.copyWith(
      preInfusionSeconds: 0,
      standstillSeconds: 0,
      extractionSeconds: 30,
    );

    // Наборы не перетёрли друг друга.
    expect(p.recipeFor(WorkMode.heatAndBrew).extractionSeconds, 40);
    expect(p.recipeFor(WorkMode.heatAndBrew).preInfusionSeconds, 6);
    expect(p.recipeFor(WorkMode.brew).extractionSeconds, 30);
    expect(p.recipeFor(WorkMode.brew).preInfusionSeconds, 0);

    // Активный рецепт следует за режимом.
    p.runMode = WorkMode.heatAndBrew;
    expect(p.recipe.extractionSeconds, 40);
    p.runMode = WorkMode.brew;
    expect(p.recipe.extractionSeconds, 30);
  });

  testWidgets('выбор режима в меню пуска запоминается', (tester) async {
    await withApp(tester, (device) async {
      device.connect('mock');
      await settle(tester);

      // Режим выбирается в листе, который открывает первая карточка колонки.
      await tester.tap(find.byKey(const ValueKey(StepKind.mode)));
      // pumpAndSettle не годится: мок постоянно шлёт телеметрию.
      await settle(tester);
      await tester.tap(find.text('Brew').last);
      await settle(tester);
      expect(prefs.runMode, WorkMode.brew);

      await tester.tap(find.textContaining('Start').last);
      await settle(tester);
      expect(device.status?.state, MachineState.brewing);
    });
  });

  testWidgets('режим выбирается и без подключения', (tester) async {
    await withApp(tester, (device) async {
      // Машина не на связи: режим живёт в телефоне, менять его это не мешает.
      expect(device.isConnected, isFalse);
      await tester.tap(find.byKey(const ValueKey(StepKind.mode)));
      await settle(tester);
      await tester.tap(find.text('Brew').last);
      await settle(tester);
      expect(prefs.runMode, WorkMode.brew);
    });
  });

  testWidgets('русская локализация подхватывается из настроек', (tester) async {
    prefs.localeCode = 'ru';
    await withApp(tester, (device) async {
      await tester.pump();
      expect(find.text('Подключиться'), findsOneWidget);
    });
  });
}
