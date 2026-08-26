import 'package:flutter_test/flutter_test.dart';
import 'package:k2pro/model/flow_tracker.dart';
import 'package:k2pro/model/gravimetric_stop.dart';

final DateTime t0 = DateTime(2026, 1, 1, 12);

DateTime at(double seconds) =>
    t0.add(Duration(microseconds: (seconds * 1e6).round()));

/// Весы шлют десять кадров в секунду и округляют до 0.1 г — считаем так же,
/// иначе тест проверяет идеальный поток, которого в жизни нет.
WeightSample sample(double seconds, double grams) =>
    WeightSample(at: at(seconds), grams: (grams * 10).roundToDouble() / 10);

void main() {
  group('поток', () {
    test('ровный пролив даёт свой наклон', () {
      final f = FlowTracker();
      for (var i = 0; i <= 30; i++) {
        f.add(sample(i / 10, i / 10 * 2.0));
      }
      expect(f.flow, closeTo(2.0, 0.15));
      expect(f.grams, closeTo(6.0, 0.05));
    });

    test('меньше трёх отсчётов — потока нет', () {
      final f = FlowTracker();
      f.add(sample(0, 0));
      f.add(sample(0.1, 0.2));
      expect(f.flow, 0);
    });

    test('пролив признаётся начавшимся не раньше секунды', () {
      final f = FlowTracker();
      // Наклон появляется с третьего отсчёта — раньше по двум точкам шум
      // даёт целый грамм в секунду. Отсюда и отсчитывается выдержка.
      for (var i = 0; i <= 11; i++) {
        f.add(sample(i / 10, i / 10 * 2.0));
        expect(f.isPouring, isFalse, reason: 'на ${i / 10} с ещё рано');
      }
      f.add(sample(1.2, 2.4));
      expect(f.isPouring, isTrue);
    });

    test('стоящий вес признаётся устоявшимся через полторы секунды', () {
      final f = FlowTracker();
      for (var i = 0; i <= 20; i++) {
        f.add(sample(i / 10, 41.3));
      }
      expect(f.isSettled, isTrue);
      expect(f.flow, closeTo(0, 0.01));
    });

    test('толчок обрывает окно, а не отсчёт', () {
      final f = FlowTracker();
      for (var i = 0; i <= 20; i++) {
        f.add(sample(i / 10, i / 10 * 2.0));
      }
      expect(f.isPouring, isTrue);

      // Поставили рядом ложку: плюс двадцать граммов за один кадр.
      f.add(sample(2.1, 24.0));
      expect(f.grams, 24.0, reason: 'новый вес настоящий');
      expect(f.flow, 0, reason: 'через разрыв наклон не считается');
      expect(f.isPouring, isFalse);
      expect(f.lastBumpAt, at(2.1));
    });

    test('снятие с весов даёт отрицательный поток', () {
      final f = FlowTracker();
      for (var i = 0; i <= 10; i++) {
        f.add(sample(i / 10, 4.0 - i / 10 * 1.0));
      }
      expect(f.flow, closeTo(-1.0, 0.15));
      expect(f.isPouring, isFalse);
    });
  });

  group('спуск', () {
    /// Пролив с постоянным потоком. Возвращает момент спуска и вес на нём.
    (double, double)? runShot({
      required GravimetricStop stop,
      double flow = 2.0,
      double until = 40,
    }) {
      final f = FlowTracker();
      for (var i = 0; ; i++) {
        final t = i / 10;
        final w = t * flow;
        if (w > until) return null;
        final s = sample(t, w);
        f.add(s);
        if (stop.onSample(s, f)) return (t, f.grams);
      }
    }

    test('спуск раньше цели ровно на упреждение и дотёк', () {
      final stop = GravimetricStop(target: 40, drip: 0.6);
      final fired = runShot(stop: stop)!;
      // 40 − 2 г/с × 0.4 с − 0.6 г = 38.6
      expect(fired.$2, closeTo(38.6, 0.35));
      expect(stop.hasFired, isTrue);
      expect(stop.triggerFlow, closeTo(2.0, 0.2));
    });

    test('быстрый поток спускается раньше медленного', () {
      final fast = GravimetricStop(target: 40, drip: 0.6);
      final slow = GravimetricStop(target: 40, drip: 0.6);
      final a = runShot(stop: fast, flow: 3.0)!.$2;
      final b = runShot(stop: slow, flow: 1.0)!.$2;
      expect(a, lessThan(b));
      expect(b - a, closeTo(2.0 * 0.4, 0.4));
    });

    test('спуск однократный', () {
      final stop = GravimetricStop(target: 10, drip: 0.6);
      final f = FlowTracker();
      var count = 0;
      for (var i = 0; i <= 100; i++) {
        final s = sample(i / 10, i / 10 * 2.0);
        f.add(s);
        if (stop.onSample(s, f)) count++;
      }
      expect(count, 1);
    });

    test('поставленная чашка тяжелее цели не запускает спуск', () {
      final stop = GravimetricStop(target: 40, drip: 0.6);
      final f = FlowTracker();
      var fired = false;
      for (var i = 0; i <= 30; i++) {
        // Ровно стоящие 120 г: пролива не было, потока нет.
        final s = sample(i / 10, 120);
        f.add(s);
        fired |= stop.onSample(s, f);
      }
      expect(fired, isFalse);
      expect(stop.isArmed, isFalse);
    });

    test('толчок посреди пролива не спускает контур', () {
      final stop = GravimetricStop(target: 40, drip: 0.6);
      final f = FlowTracker();
      var firedAt = -1.0;
      for (var i = 0; i <= 25; i++) {
        final t = i / 10;
        // Пролив идёт от нуля, а на 2.0 с чашку задели — сразу 45 г.
        final w = t < 2.0 ? t * 2.0 : 45.0;
        final s = sample(t, w);
        f.add(s);
        if (stop.onSample(s, f) && firedAt < 0) firedAt = t;
      }
      expect(firedAt, -1.0, reason: 'после разрыва предсказывать не по чему');
    });
  });

  group('обучение', () {
    ShotResult shot({
      required double trigger,
      required double flow,
      required double finalGrams,
      StopReason reason = StopReason.weight,
    }) => ShotResult(
      reason: reason,
      target: 40,
      triggerGrams: trigger,
      triggerFlow: flow,
      finalGrams: finalGrams,
      elapsed: const Duration(seconds: 28),
    );

    test('из перелёта вычитается временная часть', () {
      // Перелёт 1.8 г при потоке 2 г/с: 0.8 г — это упреждение, дотёк — 1.0 г.
      final next = learnedDrip(
        drip: 0.6,
        shot: shot(trigger: 38.6, flow: 2.0, finalGrams: 40.4),
      );
      expect(next, closeTo(0.6 + 0.3 * (1.0 - 0.6), 0.001));
    });

    test('за несколько проливов сходится к настоящему дотёку', () {
      var drip = kSeedDrip;
      for (var i = 0; i < 6; i++) {
        drip = learnedDrip(
          drip: drip,
          shot: shot(trigger: 38.6, flow: 2.0, finalGrams: 38.6 + 0.8 + 1.2),
        )!;
      }
      expect(drip, closeTo(1.2, 0.15));
    });

    test('на проливе, который встал по времени, не учимся', () {
      expect(
        learnedDrip(
          drip: 0.6,
          shot: shot(
            trigger: 34.1,
            flow: 0,
            finalGrams: 34.1,
            reason: StopReason.timeout,
          ),
        ),
        isNull,
      );
    });

    test('чушь отбрасывается', () {
      // С весов сняли чашку — итог меньше, чем был на спуске.
      expect(
        learnedDrip(
          drip: 0.6,
          shot: shot(trigger: 38.6, flow: 2.0, finalGrams: 12.0),
        ),
        isNull,
      );
      // Двадцать граммов после останова — это не дотёк.
      expect(
        learnedDrip(
          drip: 0.6,
          shot: shot(trigger: 38.6, flow: 2.0, finalGrams: 58.6),
        ),
        isNull,
      );
    });

    test('поправка не уходит за потолок', () {
      var drip = kDripMax;
      drip = learnedDrip(
        drip: drip,
        shot: shot(trigger: 30, flow: 2.0, finalGrams: 39.9),
      )!;
      expect(drip, lessThanOrEqualTo(kDripMax));
      expect(drip, greaterThanOrEqualTo(0));
    });
  });

  group('итог пролива', () {
    test('промах считается от цели, перелёт — от спуска', () {
      final stop = GravimetricStop(target: 40, drip: 0.6);
      final f = FlowTracker();
      for (var i = 0; ; i++) {
        final s = sample(i / 10, i / 10 * 2.0);
        f.add(s);
        if (stop.onSample(s, f)) break;
      }
      final r = stop.finish(
        reason: StopReason.weight,
        finalGrams: 40.4,
        elapsed: const Duration(seconds: 28),
      );
      expect(r.miss, closeTo(0.4, 0.001));
      expect(r.overshoot, closeTo(40.4 - stop.triggerGrams, 0.001));
    });

    test('без спуска перелёта нет', () {
      final stop = GravimetricStop(target: 40, drip: 0.6);
      final r = stop.finish(
        reason: StopReason.timeout,
        finalGrams: 34.1,
        elapsed: const Duration(seconds: 70),
      );
      expect(r.overshoot, 0);
      expect(r.miss, closeTo(-5.9, 0.001));
    });
  });
}
