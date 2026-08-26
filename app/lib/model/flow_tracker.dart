/// Поток по отсчётам весов: сколько граммов в секунду прибывает прямо сейчас.
///
/// Весы, вероятно, считают поток и сами — четыре неопознанных байта в кадре
/// измерения названы в драйвере-источнике «поток и время». Но чужому числу
/// доверять нельзя: у его фильтра неизвестная задержка, а контуру останова
/// нужна известная, иначе упреждение считается от чего попало. Поэтому счёт
/// свой, и вся его инерция — ровно [FlowTracker.window].
library;

import 'dart:math' as math;

/// Один отсчёт весов.
class WeightSample {
  const WeightSample({required this.at, required this.grams});

  /// Когда кадр дошёл до нас, а не когда взвесилось. Разницу между этими
  /// двумя моментами мы всё равно не знаем, но именно от этой отметки
  /// считается упреждение — значит она и есть та, с которой надо работать.
  final DateTime at;

  final double grams;
}

/// Скачок между соседними отсчётами, после которого поток считать нельзя.
///
/// При десяти кадрах в секунду пять граммов между соседними — это 50 г/с,
/// на порядок больше любого настоящего пролива. Так выглядит не вода, а
/// поставленная чашка или задетые весы.
const double kBumpGrams = 5;

/// Ниже этого весы считаются стоящими.
const double kSettledFlow = 0.05;

/// Столько поток должен держаться около нуля, чтобы вес считался устоявшимся.
const Duration kSettleTime = Duration(milliseconds: 1500);

/// Выше этого — вода действительно идёт.
const double kPouringFlow = 0.3;

/// Столько поток должен держаться, чтобы пролив считался начавшимся. Без этой
/// выдержки автостоп можно взвести случайным касанием.
const Duration kPouringTime = Duration(seconds: 1);

class FlowTracker {
  FlowTracker({this.window = const Duration(milliseconds: 800)});

  /// Окно, по которому считается наклон. Короче — дёрганый поток и ложные
  /// срабатывания; длиннее — упреждение опаздывает ровно на эту разницу.
  final Duration window;

  final List<WeightSample> _w = [];

  double _flow = 0;
  DateTime? _pouringSince;
  DateTime? _settledSince;
  DateTime? _bumpAt;

  /// Граммов в секунду. Отрицательный, если с весов снимают.
  double get flow => _flow;

  /// Последний известный вес.
  double get grams => _w.isEmpty ? 0 : _w.last.grams;

  bool get hasSamples => _w.isNotEmpty;

  /// Вес устоялся — можно записывать число и учиться на нём.
  bool get isSettled {
    final since = _settledSince;
    final last = _w.isEmpty ? null : _w.last.at;
    if (since == null || last == null) return false;
    return last.difference(since) >= kSettleTime;
  }

  /// Вода действительно идёт.
  bool get isPouring {
    final since = _pouringSince;
    final last = _w.isEmpty ? null : _w.last.at;
    if (since == null || last == null) return false;
    return last.difference(since) >= kPouringTime;
  }

  /// Когда весы последний раз дёрнули. Нужно тому, кто решает, годится ли
  /// пролив в обучение: толкнули посреди — считать по нему нечего.
  DateTime? get lastBumpAt => _bumpAt;

  void add(WeightSample s) {
    final prev = _w.isEmpty ? null : _w.last;

    // Разрыв. Новый вес настоящий — что-то поставили или сняли, — а вот окно
    // через разрыв не считается: наклон получился бы фантастическим. Поэтому
    // не выбрасываем отсчёт, а начинаем окно заново с него.
    if (prev != null && (s.grams - prev.grams).abs() > kBumpGrams) {
      _w.clear();
      _flow = 0;
      _pouringSince = null;
      _settledSince = null;
      _bumpAt = s.at;
    }

    _w.add(s);
    final edge = s.at.subtract(window);
    while (_w.length > 2 && _w.first.at.isBefore(edge)) {
      _w.removeAt(0);
    }

    _flow = _slope();

    if (_flow >= kPouringFlow) {
      _pouringSince ??= s.at;
    } else {
      _pouringSince = null;
    }

    if (_flow.abs() <= kSettledFlow) {
      _settledSince ??= s.at;
    } else {
      _settledSince = null;
    }
  }

  /// Забыть всё: новый пролив, новое взвешивание, оборванная связь.
  void reset() {
    _w.clear();
    _flow = 0;
    _pouringSince = null;
    _settledSince = null;
    _bumpAt = null;
  }

  /// Наклон по методу наименьших квадратов. Меньше трёх точек или слишком
  /// короткий пролёт по времени — считать нечего: разрешение весов 0.1 г, и
  /// на двух соседних отсчётах шум даёт наклон в целый грамм в секунду.
  double _slope() {
    if (_w.length < 3) return 0;
    final t0 = _w.first.at;
    final span = _w.last.at.difference(t0).inMicroseconds / 1e6;
    if (span < 0.2) return 0;

    var sx = 0.0, sy = 0.0, sxx = 0.0, sxy = 0.0;
    for (final s in _w) {
      final x = s.at.difference(t0).inMicroseconds / 1e6;
      sx += x;
      sy += s.grams;
      sxx += x * x;
      sxy += x * s.grams;
    }
    final n = _w.length.toDouble();
    final den = n * sxx - sx * sx;
    if (den.abs() < 1e-9) return 0;
    final k = (n * sxy - sx * sy) / den;
    return k.isFinite ? k : 0;
  }

  /// Сколько ещё лить до цели при нынешнем потоке. null — поток стоит.
  Duration? timeTo(double target) {
    if (_flow <= kSettledFlow) return null;
    final left = target - grams;
    if (left <= 0) return Duration.zero;
    return Duration(microseconds: math.min(left / _flow * 1e6, 3.6e9).round());
  }
}
