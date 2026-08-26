import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:k2pro/model/shot_curve.dart';
import 'package:k2pro/store/shot_store.dart';

final DateTime t0 = DateTime(2026, 1, 1, 9);

void main() {
  group('запись кривой', () {
    test('прореживает отсчёты весов до своего шага', () {
      final r = CurveRecorder(startedAt: t0);
      // Весы шлют десять раз в секунду, кривой хватает пяти.
      for (var i = 0; i <= 100; i++) {
        r.addWeight(t0.add(Duration(milliseconds: i * 100)), i / 10 * 2);
      }
      final c = r.build();
      expect(c.ms.length, closeTo(51, 1));
      expect(c.ms.first, 0);
      expect(c.grams.last, closeTo(20, 0.1));
    });

    test('температуру пишет не чаще секунды', () {
      final r = CurveRecorder(startedAt: t0);
      for (var i = 0; i <= 50; i++) {
        r.addTemperature(t0.add(Duration(milliseconds: i * 200)), 92 - i ~/ 10);
      }
      expect(r.build().tempC.length, closeTo(11, 1));
    });

    test('момент останова запоминается один раз', () {
      final r = CurveRecorder(startedAt: t0)
        ..markStop(t0.add(const Duration(seconds: 18)))
        ..markStop(t0.add(const Duration(seconds: 25)));
      expect(r.build().stopMs, 18000);
    });

    test('отсчёт до пуска не попадает в кривую', () {
      final r = CurveRecorder(startedAt: t0)
        ..addWeight(t0.subtract(const Duration(seconds: 1)), 5);
      expect(r.build().ms, isEmpty);
    });
  });

  group('поток по кривой', () {
    test('ровный пролив даёт свой наклон', () {
      final r = CurveRecorder(startedAt: t0);
      for (var i = 0; i <= 100; i++) {
        r.addWeight(t0.add(Duration(milliseconds: i * 100)), i / 10 * 2);
      }
      final c = r.build();
      expect(c.flowAt(c.ms.length ~/ 2), closeTo(2.0, 0.1));
    });
  });

  group('файл кривой', () {
    test('десятые грамма переживают запись и чтение', () {
      final r = CurveRecorder(startedAt: t0);
      for (var i = 0; i <= 20; i++) {
        r.addWeight(t0.add(Duration(milliseconds: i * 200)), i * 1.7);
        r.addTemperature(t0.add(Duration(milliseconds: i * 200)), 93 - i);
      }
      r.markStop(t0.add(const Duration(seconds: 3)));

      final back = ShotCurve.decode(r.build().encode())!;
      expect(back.ms.length, r.build().ms.length);
      expect(back.grams[5], closeTo(8.5, 0.05));
      expect(back.stopMs, 3000);
      expect(back.tempC.first, 93);
    });

    test('мусор не роняет разбор', () {
      expect(ShotCurve.decode('не json'), isNull);
      expect(ShotCurve.decode('{"ms":[1],"g":[10]}'), isNull, reason: 'слишком коротко');
    });
  });

  group('хранилище', () {
    late Directory dir;
    late ShotStore store;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('k2shots');
      store = ShotStore(dir: dir);
    });

    tearDown(() => dir.deleteSync(recursive: true));

    ShotCurve sample() {
      final r = CurveRecorder(startedAt: t0);
      for (var i = 0; i <= 20; i++) {
        r.addWeight(t0.add(Duration(milliseconds: i * 200)), i * 1.5);
      }
      return r.build();
    }

    test('записанное читается обратно', () async {
      await store.save('1000', sample());
      final back = await store.load('1000');
      expect(back, isNotNull);
      expect(back!.peakGrams, closeTo(30, 0.1));
    });

    test('чужого пролива нет — и это не ошибка', () async {
      expect(await store.load('404'), isNull);
    });

    test('имя файла собирается только из цифр', () async {
      // Идентификатор приходит из записи журнала, но пусть путь всё равно не
      // собирается из чего попало.
      await store.save('../beда', sample());
      expect(dir.listSync(recursive: true).whereType<File>(), isEmpty);
    });

    test('уборка оставляет только нужные кривые', () async {
      for (final id in ['1', '2', '3']) {
        await store.save(id, sample());
      }
      await store.prune({'2'});
      expect(await store.load('1'), isNull);
      expect(await store.load('2'), isNotNull);
      expect(await store.load('3'), isNull);
    });

    test('очистка убирает всё', () async {
      await store.save('7', sample());
      await store.clear();
      expect(dir.listSync(recursive: true).whereType<File>(), isEmpty);
    });
  });
}
