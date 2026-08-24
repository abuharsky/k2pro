import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:k2pro/ble/protocol.dart';

Uint8List rxFrame(
  int cmd,
  List<int> payload, {
  FragStatus frag = FragStatus.none,
}) {
  final total = kHeaderLen + payload.length;
  final lenHi = (frag.index << 6) | ((total >> 8) & 0x3F);
  final lenLo = total & 0xFF;
  final cs = frameChecksum(kStartRx, lenHi, lenLo, cmd, payload);
  return Uint8List.fromList([kStartRx, lenHi, lenLo, cs, cmd, ...payload]);
}

void main() {
  _tempLimitsSanity();
  group('кадр', () {
    test('пустой запрос состояния', () {
      expect(buildFrame(Cmd.deviceState), [0x7F, 0x00, 0x05, 0x84, 0x00]);
    });

    test('длина считается по всему кадру, а не по нагрузке', () {
      final f = buildFrame(Cmd.setWorkState, [1, 1]);
      expect(f.length, 7);
      expect(((f[1] & 0x3F) << 8) | f[2], 7);
    });

    test('контрольная сумма покрывает заголовок, команду и нагрузку', () {
      final f = buildFrame(Cmd.setWorkState, [1, 1]);
      expect(f[3], (0x7F + 0x00 + 0x07 + 0x02 + 1 + 1) & 0xFF);
    });

    test('приём проверяет стартовый байт, длину и сумму', () {
      final raw = rxFrame(Cmd.deviceState, [0, 100, 0, 90, 1, 0]);
      final f = parseFrame(raw);
      expect(f.cmd, Cmd.deviceState);
      expect(f.payload.length, 6);

      final bad = Uint8List.fromList(raw)..[3] = raw[3] ^ 0xFF;
      expect(() => parseFrame(bad), throwsA(isA<FrameFormatException>()));

      final wrongStart = Uint8List.fromList(raw)..[0] = 0x7F;
      expect(
        () => parseFrame(wrongStart),
        throwsA(isA<FrameFormatException>()),
      );
    });
  });

  group('декодер потока', () {
    test('склеивает кадр из чанков и отбрасывает мусор', () {
      final raw = rxFrame(Cmd.deviceState, [0, 100, 0, 90, 1, 0]);
      final d = FrameDecoder();
      expect(d.push([0xAA, 0xBB, ...raw.take(4)]), isEmpty);
      final out = d.push(raw.skip(4).toList());
      expect(out.single, raw);
    });

    test('два кадра в одном чанке', () {
      final a = rxFrame(Cmd.todayCups, [3]);
      final b = rxFrame(Cmd.getTempSetting, [60, 100, 92]);
      final out = FrameDecoder().push([...a, ...b]);
      expect(out.length, 2);
      expect(parseFrame(out[0]).cmd, Cmd.todayCups);
      expect(parseFrame(out[1]).cmd, Cmd.getTempSetting);
    });
  });

  group('фрагменты', () {
    test('собираются только на lastPack', () {
      final asm = FragmentAssembler();
      expect(
        asm.feed(
          parseFrame(rxFrame(Cmd.deviceInfo, [1, 2], frag: FragStatus.first)),
        ),
        isNull,
      );
      expect(
        asm.feed(
          parseFrame(rxFrame(Cmd.deviceInfo, [3], frag: FragStatus.middle)),
        ),
        isNull,
      );
      final done = asm.feed(
        parseFrame(rxFrame(Cmd.deviceInfo, [4], frag: FragStatus.last)),
      );
      expect(done, [1, 2, 3, 4]);
    });
  });

  group('команды', () {
    test(
      '0x18 идёт в порядке [давление, замачивание, выстаивание, экстракция]',
      () {
        final f = cmdSetWorkParams(
          pressure: 2,
          preInfusionSeconds: 30,
          standstillSeconds: 15,
          extractionSeconds: 60,
        );
        expect(f.sublist(4), [0x18, 2, 30, 15, 60]);
      },
    );

    test('без времени экстракции отбрасывается последний байт', () {
      final f = cmdSetWorkParams(
        pressure: 2,
        preInfusionSeconds: 30,
        standstillSeconds: 15,
      );
      expect(f.sublist(4), [0x18, 2, 30, 15]);
    });

    test('0x02 использует WorkMode, а таймер — ScheduleMode', () {
      expect(WorkMode.heat.code, 0);
      expect(WorkMode.heatAndBrew.code, 1);
      expect(ScheduleMode.heatAndBrew.code, 0);
      expect(ScheduleMode.heat.code, 1);
      // Сначала режим, потом флаг пуска — порядок снят с живой машины.
      expect(cmdSetWorkState(true, WorkMode.brew).sublist(4), [0x02, 2, 1]);
      expect(cmdSetWorkState(true, WorkMode.heat).sublist(4), [0x02, 0, 1]);
      expect(cmdStop().sublist(4), [0x02, 0, 0]);
    });

    test('время: [день недели, месяц, число, год-2020, ч, м, с]', () {
      final f = cmdSetTime(DateTime(2026, 8, 23, 9, 41, 5)); // воскресенье
      expect(f.sublist(4), [0x04, 7, 8, 23, 6, 9, 41, 5]);
    });
  });

  group('разбор ответов', () {
    test('состояние', () {
      final s = parseDeviceStatus(
        Uint8List.fromList([0, 0xE4, 0x80, 0x5A, 1, 0]),
      );
      expect(s.batteryRaw, 100);
      expect(s.batteryLevel, 4);
      expect(s.charge, ChargeState.charging);
      expect(s.temperatureC, 0x5A);
      expect(s.state, MachineState.heatBrewing);
      expect(s.state.isBusy, isTrue);
      expect(s.error, MachineError.none);
    });

    test('флаг 0x40 — заряд окончен, батарея полная', () {
      // Живой пакет с зарядки: сырое число 85, но 0x40 говорит «заряжена».
      final s = parseDeviceStatus(
        Uint8List.fromList([0, 0x55, 0xC4, 0x1E, 0, 0]),
      );
      expect(s.batteryLevel, 4);
      expect(s.charge, ChargeState.full);
    });

    test('флаг 0x20 сажает уровень в ноль', () {
      final s = parseDeviceStatus(
        Uint8List.fromList([0, 0x55, 0x20, 0x1E, 0, 0]),
      );
      expect(s.batteryLevel, 0);
    });

    test('деления считаются по порогам оригинала', () {
      int lvl(int raw) =>
          parseDeviceStatus(Uint8List.fromList([0, raw, 0, 0, 0, 0]))
              .batteryLevel;
      expect(lvl(0), 0);
      expect(lvl(10), 1);
      expect(lvl(24), 1);
      expect(lvl(25), 2);
      expect(lvl(35), 2);
      expect(lvl(50), 2);
      expect(lvl(51), 3);
      expect(lvl(60), 3);
      expect(lvl(75), 3);
      expect(lvl(76), 4);
      expect(lvl(85), 4);
    });

    test('рабочие параметры', () {
      final p = parseWorkParams(
        Uint8List.fromList([7, 5, 3, 30, 5, 0, 60, 70, 20, 120, 1, 15]),
      );
      expect(p.pressure.value, 7);
      expect(p.pressure.min, 1);
      expect(p.pressure.max, 15);
      expect(p.preInfusion.value, 5);
      expect(p.extraction.max, 120);
    });

    test('короткий ответ 0x17 даёт запасной диапазон скорости', () {
      final p = parseWorkParams(
        Uint8List.fromList([1, 5, 3, 30, 5, 0, 60, 70, 20, 120]),
      );
      expect(p.pressure.min, 0);
      expect(p.pressure.max, 2);
    });

    test('эхо 0x18 и 0x20 разного формата', () {
      final e4 = parseWorkParamEcho(Uint8List.fromList([2, 30, 15, 60]));
      expect(e4.extraction, 60);
      expect(e4.targetTemperature, isNull);

      // Установка и в этом эхе приходит в °F.
      final e5 = parseWorkParamEcho(Uint8List.fromList([2, 30, 15, 198, 60]));
      expect(e5.targetTemperature, 92);
      expect(e5.extraction, 60);
    });

    test('таймер', () {
      final a = parseAppointment(Uint8List.fromList([1, 7, 30, 1, 2, 1]));
      expect(a.mode, ScheduleMode.heat);
      expect(a.hour, 7);
      expect(a.minute, 30);
      expect(a.reminder, ReminderMode.sound);
      expect(a.beep, BeepSound.buGu);
      expect(a.enabled, isTrue);
      expect(a.spent, isFalse);
    });

    test('флаг будильника не булев: 0 выключен, 1 взведён, 2 отработал', () {
      // Кадр снят с живой машины: взвели на 16:28 «только пролив», будильник
      // сработал, и на следующем 0x24 она вернула в последнем байте двойку.
      final done = parseAppointment(
        Uint8List.fromList([2, 0x10, 0x1c, 1, 0, 2]),
      );
      expect(done.hour, 16);
      expect(done.minute, 28);
      // Двойка — не «включён». Оригинал сравнивает ровно с единицей, и мы тоже.
      expect(done.enabled, isFalse);
      expect(done.spent, isTrue);

      final off = parseAppointment(Uint8List.fromList([2, 7, 0, 1, 0, 0]));
      expect(off.enabled, isFalse);
      expect(off.spent, isFalse);
    });

    test('своя запись снимает отметку «отработал»', () {
      final done = parseAppointment(
        Uint8List.fromList([2, 0x10, 0x1c, 1, 0, 2]),
      );
      // Взводим заново — отметка уходит, иначе она пережила бы новый завод.
      expect(done.copyWith(enabled: true).spent, isFalse);
      // А правка времени её не трогает: будильник всё ещё отработавший.
      expect(done.copyWith(minute: 30).spent, isTrue);
      // Наружу третьего значения не пишем никогда: только 0 или 1.
      expect(cmdSetAppointment(done)[10], 0);
      expect(cmdSetAppointment(done.copyWith(enabled: true))[10], 1);
    });

    test('история: payload[2] — сегодня', () {
      final today = DateTime(2026, 8, 23);
      final h = parseCupsHistory(
        Uint8List.fromList([0, 0, 4, 2, 0, 1]),
        today: today,
      );
      expect(h[today], 4);
      expect(h[today.subtract(const Duration(days: 1))], 2);
      expect(h[today.subtract(const Duration(days: 3))], 1);
    });

    test('информация об устройстве: три строки с префиксом длины', () {
      const a = 'HW1.0';
      const b = 'SW2.1';
      const m = 'PCM03SPRO';
      final info = parseDeviceInfo(
        Uint8List.fromList([
          0,
          a.length,
          ...a.codeUnits,
          b.length,
          ...b.codeUnits,
          m.length,
          ...m.codeUnits,
        ]),
      );
      expect(info.versionA, a);
      expect(info.versionB, b);
      expect(info.model, m);
    });

    test('пустая третья строка означает PCM03', () {
      final info = parseDeviceInfo(Uint8List.fromList([0, 1, 65, 1, 66, 0]));
      expect(info.model, 'PCM03');
    });
  });
}

void _tempLimitsSanity() {
  group('границы заданной температуры', () {
    test('живой ответ PCM03SMAX 64 cc 5b читается как °F', () {
      // 100…204 °F = 37.8…95.6 °C, установка 91 °F = 32.8 °C. Границы
      // округляются внутрь, чтобы обратный перевод не вышел за диапазон.
      final t = parseTempLimits(Uint8List.fromList([0x64, 0xcc, 0x5b]));
      expect(t.min, 38);
      expect(t.max, 95);
      expect(t.target, 33);
      expect(celsiusToWire(t.min), greaterThanOrEqualTo(0x64));
      expect(celsiusToWire(t.max), lessThanOrEqualTo(0xcc));
    });

    test('°C уезжает в кадр Фаренгейтами', () {
      expect(cmdSetTargetTemperature(92).sublist(4), [0x16, 198]);
      expect(celsiusFromWire(198), 92);
    });

    test('перевёрнутый диапазон подменяется запасным', () {
      final t = parseTempLimits(Uint8List.fromList([204, 100, 198]));
      expect(t.min, kFallbackTempMin);
      expect(t.max, kFallbackTempMax);
    });
  });

  test('лесенка ожидания: быстрый первый повтор, растущее окно, потолок', () {
    // Штатный ответ машины — 89 мс медианы, 239 мс p99 по живой трассе.
    // Первая попытка не должна ждать дольше полусекунды с хвостиком: кадра,
    // который не долетел, ждать нечего.
    expect(retryTimeout(1, 3), const Duration(milliseconds: 600));
    expect(retryTimeout(2, 3), const Duration(milliseconds: 1200));
    expect(retryTimeout(3, 3), const Duration(milliseconds: 2400));

    // Вся серия укладывается в 4.2 с. Раньше было 0.6 + 4 + 4 = 8.6 с.
    final total = [for (var i = 1; i <= 3; i++) retryTimeout(i, 3)]
        .fold(Duration.zero, (a, b) => a + b);
    expect(total, lessThan(const Duration(seconds: 5)));

    // Потолок не пробивается, сколько бы попыток ни было.
    expect(retryTimeout(9, 9), kMaxTryTimeout);

    // Одиночная попытка ждёт весь срок: повторять некому.
    expect(retryTimeout(1, 1), kMaxTryTimeout);
    expect(
      retryTimeout(1, 1, const Duration(seconds: 9)),
      const Duration(seconds: 9),
    );
  });
}
