import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n/app_l10n.dart';
import '../l10n/l10n_ext.dart';
import '../model/gravimetric_stop.dart';
import '../model/gravimetry.dart';
import '../model/shot_curve.dart';
import '../store/prefs.dart';
import '../store/shot_store.dart';
import 'sheets/sheet.dart';
import 'theme.dart';
import 'widgets/k_icons.dart';
import 'widgets/round_button.dart';

/// Один пролив: график, если он есть, и его параметры.
///
/// Кривая лежит отдельным файлом и читается только здесь — оттого экран и
/// нужен: держать четыреста точек на пролив в общем списке значило бы платить
/// за них при каждом открытии журнала.
///
/// Кривой нет у проливов без весов. Тогда экран показывает то, что известно:
/// сколько лилось и при какой температуре. Это не заглушка вместо графика —
/// это всё, что про такой пролив вообще можно знать.
Future<void> openShot(
  BuildContext context, {
  required ShotRecord shot,
  required Prefs prefs,
  required ShotStore store,
}) => Navigator.of(context).push<void>(
  MaterialPageRoute(
    builder: (_) => ShotPage(shot: shot, prefs: prefs, store: store),
  ),
);

class ShotPage extends StatefulWidget {
  const ShotPage({
    super.key,
    required this.shot,
    required this.prefs,
    required this.store,
  });

  final ShotRecord shot;
  final Prefs prefs;
  final ShotStore store;

  @override
  State<ShotPage> createState() => _ShotPageState();
}

class _ShotPageState extends State<ShotPage> {
  ShotCurve? _curve;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final c = await widget.store.load(curveIdOf(widget.shot));
    if (!mounted) return;
    setState(() {
      _curve = c;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final s = widget.shot;
    final safe = MediaQuery.paddingOf(context);
    final curve = _curve;

    return Scaffold(
      body: AppBackground(
        child: Column(
          children: [
            SizedBox(height: math.max(safe.top, 20) + 4),
            _Header(title: shotStamp(t, s.at)),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  18,
                  6,
                  18,
                  math.max(safe.bottom, 12) + 20,
                ),
                children: [
                  if (curve != null) ...[
                    ShotChart(curve: curve),
                    const SizedBox(height: 18),
                  ] else if (!_loading) ...[
                    SheetCaption(t.shotNoCurve, align: TextAlign.start),
                    const SizedBox(height: 16),
                  ],
                  SheetSectionTitle(t.shotParams),
                  ..._facts(t, s),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _facts(AppL10n t, ShotRecord s) {
    final f = widget.prefs.fahrenheit;
    return [
      if (s.finalG != null)
        _Fact(
          label: t.shotYield,
          value: '${s.finalG!.toStringAsFixed(1)} ${t.gramsUnit}',
        ),
      if (s.doseG != null)
        _Fact(
          label: t.weightDose,
          value: '${s.doseG!.toStringAsFixed(1)} ${t.gramsUnit}',
        ),
      if (s.ratio != null)
        _Fact(label: t.shotRatio, value: '1:${s.ratio!.toStringAsFixed(1)}'),
      if (s.targetG != null)
        _Fact(
          label: t.weightTarget,
          value: '${s.targetG!.toStringAsFixed(1)} ${t.gramsUnit}',
        ),
      if (s.miss != null)
        _Fact(
          label: t.journalAvgMiss,
          value: s.miss! >= 0
              ? t.weightMissOver(s.miss!.toStringAsFixed(1))
              : t.weightMissUnder(s.miss!.toStringAsFixed(1)),
        ),
      _Fact(label: t.shotTime, value: t.seconds(s.elapsed.inSeconds)),
      _Fact(
        label: t.temperature,
        value: '${toDisplayTemp(s.temperatureC, f)}${f ? '°F' : '°C'}',
      ),
      _Fact(label: t.shotEnded, value: reasonLabel(t, s.reason)),
    ];
  }
}

/// Отметка времени пролива — она же его имя в списке и в шапке.
String shotStamp(AppL10n t, DateTime at) {
  final hm =
      '${at.hour.toString().padLeft(2, '0')}:'
      '${at.minute.toString().padLeft(2, '0')}';
  final now = DateTime.now();
  final sameDay =
      at.year == now.year && at.month == now.month && at.day == now.day;
  if (sameDay) return '${t.today}, $hm';
  return '${at.day.toString().padLeft(2, '0')}.'
      '${at.month.toString().padLeft(2, '0')}, $hm';
}

String reasonLabel(AppL10n t, StopReason r) => switch (r) {
  StopReason.weight => t.reasonWeight,
  StopReason.timeout => t.reasonTimeout,
  StopReason.manual => t.reasonManual,
  StopReason.linkLost => t.reasonLinkLost,
};

class _Header extends StatelessWidget {
  const _Header({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 44,
    child: Row(
      children: [
        const SizedBox(width: 8),
        RoundIconButton(
          icon: KIcon.chevronRight,
          flipped: true,
          onTap: () => Navigator.of(context).maybePop(),
          semanticLabel: MaterialLocalizations.of(context).backButtonTooltip,
        ),
        Expanded(
          child: Text(title, textAlign: TextAlign.center, style: K.title),
        ),
        const SizedBox(width: 52),
      ],
    ),
  );
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      children: [
        Expanded(child: Text(label, style: K.rowDesc)),
        Text(value, style: K.rowTitle.copyWith(color: K.text)),
      ],
    ),
  );
}

/// График пролива: вес, поток и температура на одной оси времени.
///
/// Три линии, и каждая отвечает за своё. Вес — что получилось. Поток — как оно
/// шло: провал в начале это забитая таблетка, горка в конце — размытый канал.
/// Температура — как машина держала нагрев, а падает она за пролив на добрый
/// десяток градусов.
///
/// Давления здесь нет и не будет: машина обратной связи по нему не даёт.
class ShotChart extends StatelessWidget {
  const ShotChart({super.key, required this.curve});

  final ShotCurve curve;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 210,
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
          decoration: BoxDecoration(
            color: K.rowBg,
            borderRadius: BorderRadius.circular(K.rRow),
            border: Border.all(color: K.glassBorder),
          ),
          child: CustomPaint(
            painter: _ChartPainter(curve),
            child: const SizedBox.expand(),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _Legend(color: K.water, label: t.chartWeight),
            const SizedBox(width: 14),
            _Legend(color: K.amber, label: t.chartFlow),
            const SizedBox(width: 14),
            _Legend(color: _ChartPainter.heat, label: t.chartTemperature),
          ],
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 10,
        height: 2.5,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(width: 6),
      Text(label, style: K.caption.copyWith(color: K.textDim)),
    ],
  );
}

class _ChartPainter extends CustomPainter {
  _ChartPainter(this.curve);

  final ShotCurve curve;

  static const Color heat = Color(0xFFFF9E70);

  @override
  void paint(Canvas canvas, Size size) {
    final n = curve.ms.length;
    if (n < 3) return;

    final total = curve.durationMs.toDouble();
    if (total <= 0) return;
    double x(num ms) => ms / total * size.width;

    // Вес занимает всю высоту, поток — нижние две трети: так линии реже
    // налезают друг на друга, а форма потока остаётся читаемой.
    final peak = math.max(curve.peakGrams, 1);
    double yWeight(double g) => size.height * (1 - g / peak * 0.92);

    var maxFlow = 0.0;
    for (var i = 0; i < n; i++) {
      final f = curve.flowAt(i);
      if (f > maxFlow) maxFlow = f;
    }
    maxFlow = math.max(maxFlow, 0.5);
    double yFlow(double f) => size.height * (1 - f / maxFlow * 0.62);

    // Дотёк: всё, что правее команды останова. Полоса объясняет хвост кривой
    // лучше любой подписи — видно, сколько натекло уже после стопа.
    final stop = curve.stopMs;
    if (stop != null && stop < total) {
      canvas.drawRect(
        Rect.fromLTRB(x(stop), 0, size.width, size.height),
        Paint()..color = const Color(0x0FFFFFFF),
      );
      canvas.drawLine(
        Offset(x(stop), 0),
        Offset(x(stop), size.height),
        Paint()
          ..color = const Color(0x38FFFFFF)
          ..strokeWidth = 1,
      );
    }

    Paint stroke(Color c, double w) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = c;

    // Температура — своей шкалой, под весом: её абсолютные градусы к граммам
    // отношения не имеют, важна только форма.
    if (curve.tempC.length >= 2) {
      final lo = curve.tempC.reduce(math.min).toDouble();
      final hi = curve.tempC.reduce(math.max).toDouble();
      final span = math.max(hi - lo, 4);
      final path = Path();
      for (var i = 0; i < curve.tempC.length; i++) {
        final p = Offset(
          x(curve.tempMs[i]),
          size.height * (0.12 + (1 - (curve.tempC[i] - lo) / span) * 0.3),
        );
        i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, stroke(heat.withValues(alpha: 0.65), 1.4));
    }

    // Поток.
    final flow = Path();
    for (var i = 0; i < n; i++) {
      final p = Offset(x(curve.ms[i]), yFlow(curve.flowAt(i)));
      i == 0 ? flow.moveTo(p.dx, p.dy) : flow.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(flow, stroke(K.amber.withValues(alpha: 0.8), 1.5));

    // Вес — последним и с заливкой: это главная линия.
    final weight = Path();
    for (var i = 0; i < n; i++) {
      final p = Offset(x(curve.ms[i]), yWeight(curve.grams[i]));
      i == 0 ? weight.moveTo(p.dx, p.dy) : weight.lineTo(p.dx, p.dy);
    }
    final fill = Path.from(weight)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(fill, Paint()..color = K.water.withValues(alpha: 0.10));
    canvas.drawPath(weight, stroke(K.water, 2));
  }

  @override
  bool shouldRepaint(_ChartPainter old) => old.curve != curve;
}
