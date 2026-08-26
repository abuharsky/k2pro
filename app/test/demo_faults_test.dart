import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k2pro/ble/demo.dart';
import 'package:k2pro/ble/k2_device.dart';
import 'package:k2pro/ble/mock_transport.dart';
import 'package:k2pro/ble/protocol.dart';
import 'package:k2pro/ble/scale/mock_scale_transport.dart';
import 'package:k2pro/ble/scale/scale_device.dart';
import 'package:k2pro/model/gravimetric_stop.dart';
import 'package:k2pro/model/gravimetry.dart';
import 'package:k2pro/model/shot_runner.dart';
import 'package:k2pro/store/prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Демо не должно быть вечно исправным: половина того, что приложение умеет,
/// показывается только на сорванном цикле.
void main() {
  late Prefs prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await Prefs.load();
  });

  /// Прогон подряд нескольких проливов на одном симуляторе.
  ///
  /// Возвращает по одной записи на пролив: чем он кончился и сколько
  /// натекло. Симулятор один на все прогоны — именно так и живёт демо.
  List<({MachineError fault, double grams, ShotRecord? shot})> run(
    FakeAsync async, {
    required List<MachineError> faults,
    required int times,
    bool autoStop = false,
  }) {
    var clock = DateTime(2026, 1, 1, 9);
    DateTime now() => clock;

    prefs.gravimetry = prefs.gravimetry.copyWith(
      targetG: 36,
      stopOnYield: autoStop,
      doseG: 18,
    );

    final machine = MockTransport(now: now, faultCycle: faults);
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

    device.connect(kMockMachineId);
    scale.connect(kMockScaleId);
    advance(const Duration(seconds: 3));

    final out = <({MachineError fault, double grams, ShotRecord? shot})>[];
    for (var i = 0; i < times; i++) {
      device.clearFault();
      device.brew();
      advance(const Duration(seconds: 100));
      out.add((
        fault: device.lastFault,
        grams: scale.grams,
        shot: runner.lastShot,
      ));
    }

    device.disconnect();
    scale.disconnect();
    advance(const Duration(seconds: 1));
    runner.dispose();
    device.dispose();
    scale.dispose();
    return out;
  }

  test('ошибки чередуются: чистый, нет воды, чистый, перегрев', () {
    fakeAsync((async) {
      final runs = run(async, faults: kDemoFaults, times: 4);

      expect(runs[0].fault, MachineError.none);
      expect(runs[1].fault, MachineError.dryBurning);
      expect(runs[2].fault, MachineError.none);
      expect(runs[3].fault, MachineError.batteryOverheating);
    });
  });

  test('ошибка рвёт цикл, а не просто красит баннер', () {
    fakeAsync((async) {
      final runs = run(async, faults: kDemoFaults, times: 2);

      // Чистый прогон льёт весь рецепт: 5 с смачивания по 0.8 г/с и
      // 70 с экстракции по 2 г/с.
      expect(runs[0].grams, greaterThan(120));
      // Сорванный встаёт на середине экстракции — воды заметно меньше.
      // Вес у каждого пролива свой: тара уходит на пуске.
      expect(runs[1].grams, lessThan(runs[0].grams * 0.8));
      expect(runs[1].grams, greaterThan(10), reason: 'но налить успел');
    });
  });

  test('второй пролив подряд считается от своего нуля', () {
    fakeAsync((async) {
      // Без ошибок: два одинаковых чистых пролива подряд.
      final runs = run(async, faults: const [], times: 2);

      // Итог второго — про второй, а не про сумму. Пока бегунок застревал в
      // `done` до закрытия баннера, тара на второй пуск не уходила, и вес шёл
      // от чужого нуля: под триста граммов вместо полутора сотен.
      expect(runs[1].grams, closeTo(runs[0].grams, runs[0].grams * 0.1));
      expect(runs[1].grams, lessThan(200));
      expect(runs[1].shot, isNotNull);
      expect(runs[1].shot!.finalG, closeTo(runs[0].shot!.finalG!, 15));
    });
  });

  test('после ручного стопа итог есть — значит, есть о чём спросить', () {
    fakeAsync((async) {
      var clock = DateTime(2026, 1, 1, 9);
      DateTime now() => clock;

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

      device.connect(kMockMachineId);
      scale.connect(kMockScaleId);
      advance(const Duration(seconds: 3));

      device.brew();
      // Дать воде пойти и оборвать пролив руками на середине.
      advance(const Duration(seconds: 20));
      device.stop();
      advance(const Duration(seconds: 15));

      // Машина после ручного стопа встаёт в покой, а не в «готово» — раньше
      // баннер про вкус на это не выходил вовсе. Признак теперь другой:
      // записанный итог.
      expect(device.status?.state.isDone ?? false, isFalse);
      expect(runner.lastShot, isNotNull);
      expect(runner.lastShot!.reason, StopReason.manual);
      expect(runner.lastShot!.finalG, greaterThan(1));

      // Закрыли баннер — итог ушёл, бегунок в покое.
      runner.dismiss();
      expect(runner.lastShot, isNull);
      expect(runner.phase, ShotPhase.idle);

      device.disconnect();
      scale.disconnect();
      advance(const Duration(seconds: 1));
      runner.dispose();
      device.dispose();
      scale.dispose();
    });
  });

  test('код ошибки гаснет сам, как на живой машине', () {
    fakeAsync((async) {
      final runs = run(async, faults: const [MachineError.dryBurning], times: 1);
      // В приложении ошибка остаётся, пока не нажали «Проверить»…
      expect(runs[0].fault, MachineError.dryBurning);
    });
  });
}
