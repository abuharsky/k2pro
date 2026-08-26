/// Кривая пролива: вес и температура по времени.
///
/// Итог пролива — семь чисел, и они лежат рядом с остальными настройками. А
/// кривая — четыре сотни точек, и держать её там же нельзя: настройки читаются
/// целиком при запуске, и полсотни проливов превратили бы старт приложения в
/// разбор двухсот килобайт JSON. Поэтому кривые живут отдельными файлами и
/// читаются, только когда открыли конкретный пролив.
///
/// Точки хранятся параллельными массивами, а не списком объектов: так JSON
/// вдвое компактнее и читается заметно быстрее, а смысла в объекте на каждую
/// десятую секунды нет.
library;

import 'dart:convert';
import 'dart:math' as math;

/// Отсчёты весов идут десять раз в секунду. Для кривой этого больше, чем
/// нужно: на графике шириной в триста точек лишнее всё равно не видно, а файл
/// растёт вдвое. Пишем каждый второй.
const Duration kCurveStep = Duration(milliseconds: 200);

/// Сколько проливов держим с кривыми. Итоги живут дольше — они дешёвые.
const int kCurveHistory = 50;

class ShotCurve {
  const ShotCurve({
    required this.ms,
    required this.grams,
    required this.tempMs,
    required this.tempC,
    this.stopMs,
  });

  /// Время от пуска, мс. Параллелен [grams].
  final List<int> ms;
  final List<double> grams;

  /// Температура приходит своим темпом — раз в секунду, — поэтому у неё своя
  /// ось времени.
  final List<int> tempMs;
  final List<int> tempC;

  /// Когда ушла команда останова. Всё, что правее, — дотёк.
  final int? stopMs;

  bool get isEmpty => ms.length < 3;

  /// Сколько длилась кривая, мс.
  int get durationMs => ms.isEmpty ? 0 : ms.last;

  double get peakGrams =>
      grams.isEmpty ? 0 : grams.reduce((a, b) => a > b ? a : b);

  /// Поток в точке [i], г/с. Центральная разность по паре соседей с каждой
  /// стороны, а не по одному шагу.
  ///
  /// Ширина окна тут не вкусовщина. Весы различают 0.1 г, и на тонкой струе
  /// смачивания за один шаг кривой набегает одно-два деления: разность по
  /// соседям превращает ровную струю в пилу, где зубцы — это не поток, а
  /// округление. Пять точек (около секунды) закрывают вопрос и форму
  /// экстракции при этом не сглаживают.
  double flowAt(int i) {
    if (ms.length < 5) return 0;
    final a = math.max(0, i - 2);
    final b = math.min(ms.length - 1, i + 2);
    final dt = (ms[b] - ms[a]) / 1000;
    if (dt <= 0) return 0;
    return (grams[b] - grams[a]) / dt;
  }

  Map<String, Object?> toJson() => {
    'ms': ms,
    // Десятые грамма целыми: вдвое короче в файле и ровно та точность,
    // которую весы и дают.
    'g': [for (final v in grams) (v * 10).round()],
    'tms': tempMs,
    't': tempC,
    if (stopMs != null) 'stop': stopMs,
  };

  static ShotCurve fromJson(Map<String, Object?> j) => ShotCurve(
    ms: [for (final v in (j['ms'] as List? ?? const [])) (v as num).toInt()],
    grams: [
      for (final v in (j['g'] as List? ?? const [])) (v as num).toDouble() / 10,
    ],
    tempMs: [
      for (final v in (j['tms'] as List? ?? const [])) (v as num).toInt(),
    ],
    tempC: [for (final v in (j['t'] as List? ?? const [])) (v as num).toInt()],
    stopMs: (j['stop'] as num?)?.toInt(),
  );

  String encode() => jsonEncode(toJson());

  static ShotCurve? decode(String raw) {
    try {
      final j = jsonDecode(raw);
      if (j is! Map<String, Object?>) return null;
      final c = fromJson(j);
      return c.isEmpty ? null : c;
    } catch (_) {
      return null;
    }
  }
}

/// Копит кривую по ходу пролива.
class CurveRecorder {
  CurveRecorder({required this.startedAt});

  final DateTime startedAt;

  final List<int> _ms = [];
  final List<double> _g = [];
  final List<int> _tms = [];
  final List<int> _t = [];
  int? _stopMs;
  int _lastMs = -1000000;
  int _lastTempMs = -1000000;

  int _at(DateTime now) => now.difference(startedAt).inMilliseconds;

  void addWeight(DateTime at, double grams) {
    final t = _at(at);
    if (t < 0 || t - _lastMs < kCurveStep.inMilliseconds) return;
    _lastMs = t;
    _ms.add(t);
    _g.add(grams);
  }

  /// Температуру машина шлёт раз в секунду; чаще секунды не пишем даже если
  /// пришло чаще.
  void addTemperature(DateTime at, int celsius) {
    final t = _at(at);
    if (t < 0 || t - _lastTempMs < 900) return;
    _lastTempMs = t;
    _tms.add(t);
    _t.add(celsius);
  }

  void markStop(DateTime at) => _stopMs ??= _at(at);

  ShotCurve build() => ShotCurve(
    ms: List.unmodifiable(_ms),
    grams: List.unmodifiable(_g),
    tempMs: List.unmodifiable(_tms),
    tempC: List.unmodifiable(_t),
    stopMs: _stopMs,
  );
}
