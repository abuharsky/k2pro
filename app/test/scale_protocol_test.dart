import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:k2pro/ble/scale/timemore_dot.dart';

Uint8List bytes(List<int> b) => Uint8List.fromList(b);

void main() {
  group('кадр весов', () {
    // Векторы посчитаны независимой реализацией CRC-16/IBM, а не этим же
    // кодом: иначе тест проверял бы сам себя.
    test('тара', () {
      expect(cmdScaleTare(), [0xA5, 0x5A, 0x03, 0x0D, 0x00, 0x00, 0x64, 0xD1]);
    });

    test('пуск таймера', () {
      expect(cmdScaleTimer(ScaleTimerCommand.start), [
        0xA5, 0x5A, 0x03, 0x02, 0x00, 0x01, 0x01, 0x18, 0x67,
      ]);
    });

    test('граммы и обычный режим', () {
      expect(cmdScaleUnitGram(), [
        0xA5, 0x5A, 0x03, 0x06, 0x00, 0x01, 0x00, 0xE8, 0xA7,
      ]);
      expect(cmdScaleStandardMode(), [
        0xA5, 0x5A, 0x03, 0x08, 0x00, 0x02, 0x01, 0x00, 0xEB, 0x31,
      ]);
    });

    test('длина считается по нагрузке, а не по всему кадру', () {
      final f = buildScaleFrame(ScaleOp.command, 0x42, [1, 2, 3]);
      expect((f[4] << 8) | f[5], 3);
      expect(f.length, 3 + 8);
    });

    test('контрольная сумма старшим байтом вперёд', () {
      final f = cmdScaleTare();
      final crc = scaleCrc16(f.sublist(0, f.length - 2));
      expect(f[f.length - 2], crc >> 8);
      expect(f[f.length - 1], crc & 0xFF);
    });
  });

  group('разбор измерения', () {
    test('вес в десятых грамма', () {
      final p = parseScaleFrame(
        bytes([
          0xA5, 0x5A, 0x01, 0x01, 0x00, 0x08,
          0x00, 0x00, 0x01, 0x9D, 0x00, 0x1E, 0x00, 0x00,
          0x0A, 0xC4,
        ]),
      )!;
      expect(p.crcOk, isTrue);
      final m = p.frame as ScaleMeasurement;
      expect(m.grams, 41.3);
      expect(m.extra, [0x00, 0x1E, 0x00, 0x00]);
    });

    test('отрицательный вес остаётся отрицательным', () {
      final p = parseScaleFrame(
        bytes([
          0xA5, 0x5A, 0x02, 0x01, 0x00, 0x08,
          0xFF, 0xFF, 0xFF, 0xE7, 0x00, 0x00, 0x00, 0x00,
          0x17, 0x2C,
        ]),
      )!;
      expect(p.crcOk, isTrue);
      expect((p.frame as ScaleMeasurement).grams, -2.5);
    });

    test('заряд — второй байт нагрузки', () {
      final p = parseScaleFrame(
        bytes([0xA5, 0x5A, 0x01, 0x05, 0x00, 0x02, 0x00, 0x4E, 0x6C, 0x9C]),
      )!;
      expect(p.crcOk, isTrue);
      expect((p.frame as ScaleBattery).percent, 78);
    });
  });

  group('порченое', () {
    test('чужой заголовок — не наш кадр', () {
      expect(parseScaleFrame(bytes([0x7F, 0x00, 0x05, 0x84, 0x00, 0, 0, 0])), isNull);
    });

    test('обрезанный кадр не разбирается', () {
      expect(parseScaleFrame(bytes([0xA5, 0x5A, 0x01, 0x01, 0x00, 0x08, 0, 0])), isNull);
    });

    // Кадр разбираем, но сумму помечаем: решение выбросить принимает слой выше,
    // и в трассе видно, что весы говорят, а не молчат.
    test('несошедшаяся сумма не мешает разобрать', () {
      final p = parseScaleFrame(
        bytes([
          0xA5, 0x5A, 0x01, 0x01, 0x00, 0x08,
          0x00, 0x00, 0x01, 0x9D, 0x00, 0x1E, 0x00, 0x00,
          0xFF, 0xFF,
        ]),
      )!;
      expect(p.crcOk, isFalse);
      expect((p.frame as ScaleMeasurement).grams, 41.3);
    });

    test('незнакомая команда доезжает как непонятая', () {
      final f = buildScaleFrame(ScaleOp.push, 0x42, [7]);
      final p = parseScaleFrame(f)!;
      expect(p.crcOk, isTrue);
      expect((p.frame as ScaleUnknown).cmdId, 0x42);
    });
  });

  group('имя в эфире', () {
    test('весы узнаются по вхождению, без учёта регистра', () {
      expect(isScaleName('DOT'), isTrue);
      expect(isScaleName('TES017_A1B2'), isTrue);
      expect(isScaleName('timemore dot'), isTrue);
      expect(isScaleName('BL_PCM03'), isFalse);
    });
  });
}
