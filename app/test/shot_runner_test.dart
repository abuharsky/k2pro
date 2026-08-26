import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k2pro/ble/k2_device.dart';
import 'package:k2pro/ble/mock_transport.dart';
import 'package:k2pro/ble/protocol.dart';
import 'package:k2pro/ble/scale/mock_scale_transport.dart';
import 'package:k2pro/ble/scale/scale_device.dart';
import 'package:k2pro/model/gravimetric_stop.dart';
import 'package:k2pro/model/shot_runner.dart';
import 'package:k2pro/store/prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Сквозной пролив на симуляторах: машина льёт, вода стекает через корзину с
/// задержкой, весы шлют настоящие кадры DOT, контур считает поток и даёт стоп
/// с упреждением.
///
/// Это единственное место, где вся цепочка проверяется разом. Кодек, счёт
/// потока и сам контур проверены по отдельности; здесь важно, что они
/// сходятся: команда доходит до машины, вода перестаёт течь, дотёк попадает в
/// чашку — и в поправку.
///
/// В симуляторе задержки команды нет вовсе, а в корзине висит около грамма.
/// Модель раскладывает этот грамм на «упреждение × поток» и остаток, так что
/// сойтись поправка должна не к грамму, а к 1.0 − 2 г/с × 0.4 с = 0.2 г. Важно
/// не само число, а что предсказание после этого попадает в цель.
void main() {
  late Prefs prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await Prefs.load();
  });

  /// Один пролив целиком, от подключения до записи в журнал.
  ///
  /// [drip] = null — взять поправку, выученную прошлыми проливами: только так
  /// и проверяется сходимость.
  ({
    K2Device device,
    ScaleDevice scale,
    ShotRunner runner,
    MockTransport machine,
    MockScaleTransport scaleLink,
  })
  brew(
    FakeAsync async, {
    double target = 36,
    bool autoStop = true,
    double? drip = kSeedDrip,
    Duration run = const Duration(seconds: 60),
    bool connectScale = true,
    WorkMode mode = WorkMode.brew,
  }) {
    var clock = DateTime(2026, 1, 1, 9);
    DateTime now() => clock;

    prefs.gravimetry = prefs.gravimetry.copyWith(
      targetG: target,
      stopOnYield: autoStop,
      drip: drip,
      doseG: 18,
    );

    final machine = MockTransport(now: now);
    final scaleT = MockScaleTransport(pourFlow: () => machine.pourFlow);
    final device = K2Device(machine, now: now);
    final scale = ScaleDevice(scaleT, now: now);
    final runner = ShotRunner(
      device: device,
      scale: scale,
      prefs: prefs,
      now: now,
    );

    void advance(Duration total) {
      const step = Duration(milliseconds: 50);
      for (var t = Duration.zero; t < total; t += step) {
        clock = clock.add(step);
        async.elapse(step);
      }
    }

    device.connect('mock-k2pro');
    if (connectScale) scale.connect('mock-dot');
    advance(const Duration(seconds: 3));

    switch (mode) {
      case WorkMode.brew:
        device.brew();
      case WorkMode.heat:
        device.heat();
      case WorkMode.heatAndBrew:
        device.heatAndBrew();
    }
    // Смачивание 5 с, выстаивание 5 с, дальше вода; плюс осадка и запас.
    advance(run);

    // Гасим симуляторы: иначе их таймеры тикают до конца теста и мешают
    // следующему проливу.
    device.disconnect();
    scale.disconnect();
    advance(const Duration(seconds: 1));

    return (
      device: device,
      scale: scale,
      runner: runner,
      machine: machine,
      scaleLink: scaleT,
    );
  }

  test('первый пролив недоливает, а не переливает', () {
    fakeAsync((async) {
      final shot = brew(async).runner.lastShot!;
      expect(shot.reason, StopReason.weight);
      // Начальная поправка меньше настоящего дотёка, так что первый пролив
      // обязан промахнуться — и промахнуться в безопасную сторону: недолитый
      // эспрессо можно долить, перелитый уже никуда не деть.
      expect(shot.miss, lessThanOrEqualTo(0));
      expect(shot.miss, greaterThan(-1.5));
    });
  });

  test('за несколько проливов контур пристреливается', () {
    fakeAsync((async) {
      brew(async);
      final misses = <double>[
        for (var i = 0; i < 3; i++)
          brew(async, drip: null).runner.lastShot!.miss!,
      ];
      expect(
        misses.last.abs(),
        lessThan(0.4),
        reason: 'промахи по проливам: $misses',
      );
    });
  });

  test('машина действительно получила стоп, а не досидела до конца', () {
    fakeAsync((async) {
      final r = brew(async);
      final stops = r.machine.sent.where(
        (f) => f[4] == Cmd.setWorkState && f.length > 6 && f[6] == 0,
      );
      expect(stops, isNotEmpty);
      // Экстракции в симуляторе 70 секунд; 36 г при 2 г/с набираются за 18.
      expect(r.runner.lastShot!.elapsed.inSeconds, lessThan(45));
    });
  });

  test('весы тарируются на пуске сами', () {
    fakeAsync((async) {
      final r = brew(async);
      // Руками перед проливом тарить не надо — это и есть тот шаг, который
      // автоматика убирает.
      expect(r.scaleLink.sent.where((f) => f[3] == 0x0D), isNotEmpty);
    });
  });

  test('без автостопа пролив доживает до своего таймаута', () {
    fakeAsync((async) {
      // Симулятор кончает сам через 5 + 5 + 70 секунд.
      final r = brew(
        async,
        autoStop: false,
        run: const Duration(seconds: 110),
      );
      final shot = r.runner.lastShot!;
      expect(shot.reason, StopReason.timeout);
      expect(
        shot.finalG,
        greaterThan(40),
        reason: 'никто не останавливал — налилось больше цели',
      );
    });
  });

  test('на проливе по таймауту поправка не портится', () {
    fakeAsync((async) {
      brew(
        async,
        autoStop: false,
        drip: 0.7,
        run: const Duration(seconds: 110),
      );
      expect(prefs.gravimetry.drip, 0.7);
    });
  });

  test('без весов в журнал попадают время и температура', () {
    fakeAsync((async) {
      // Весы не подключаем вовсе: журнал ведётся всё равно — он про машину.
      brew(async, connectScale: false, run: const Duration(seconds: 110));

      expect(prefs.shots, hasLength(1));
      final s = prefs.shots.first;
      expect(s.weighed, isFalse, reason: 'весить было нечем');
      expect(s.finalG, isNull);
      expect(s.targetG, isNull);
      expect(s.miss, isNull, reason: 'цели не было — промаха тоже');
      expect(s.temperatureC, 92);
      expect(s.elapsed.inSeconds, greaterThan(60));
      expect(s.reason, StopReason.timeout);
    });
  });

  test('один нагрев в журнал не попадает', () {
    fakeAsync((async) {
      brew(
        async,
        connectScale: false,
        mode: WorkMode.heat,
        run: const Duration(seconds: 40),
      );
      expect(prefs.shots, isEmpty, reason: 'пролива не было');
    });
  });

  test('у взвешенного пролива собирается кривая', () {
    fakeAsync((async) {
      final r = brew(async);
      final c = r.runner.lastCurve!;

      // Точек столько, сколько влезло в шаг кривой: писать все десять кадров
      // в секунду незачем, а форму пятикратное прореживание не портит.
      expect(c.ms.length, greaterThan(30));
      expect(c.grams.first, lessThan(1), reason: 'начали с пустой чашки');
      expect(c.peakGrams, closeTo(36, 1.5));
      expect(c.tempC, isNotEmpty, reason: 'температура машины тоже на кривой');

      // Момент спуска стоит раньше конца: справа от него — дотёк.
      expect(c.stopMs, isNotNull);
      expect(c.stopMs, lessThan(c.durationMs));
      expect(c.flowAt(c.ms.length ~/ 2), closeTo(2.0, 0.4));
    });
  });

  test('без весов кривой не остаётся', () {
    fakeAsync((async) {
      final r = brew(
        async,
        connectScale: false,
        run: const Duration(seconds: 110),
      );
      expect(r.runner.lastShot, isNotNull);
      expect(r.runner.lastCurve, isNull, reason: 'рисовать было нечего');
    });
  });

  test('пролив попадает в журнал', () {
    fakeAsync((async) {
      brew(async);
      brew(async, drip: null);
      expect(prefs.shots, hasLength(2));
      expect(prefs.shots.first.targetG, 36);
      expect(prefs.shots.first.doseG, 18);
      expect(prefs.shots.first.ratio, closeTo(2.0, 0.1));
    });
  });
}
