import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n/l10n_ext.dart';
import '../model/gravimetry.dart';
import '../store/prefs.dart';
import '../store/shot_store.dart';
import 'shot_page.dart';
import 'sheets/sheet.dart';
import 'theme.dart';
import 'widgets/k_icons.dart';
import 'widgets/round_button.dart';

/// Журнал проливов — отдельным экраном.
///
/// Отдельным, потому что в диалог весов он не влезает и не должен: диалог про
/// то, что лежит на весах сейчас, а журнал про то, что было. И потому что
/// графики требуют места: на четверти экрана они превращаются в украшение.
///
/// Главное здесь не список, а график промахов: по нему видно, пристрелялся
/// контур или гуляет. Промах считаем только у проливов, которые вели по весу —
/// если цель никто не заказывал, разница с ней не промах, а совпадение.
Future<void> openJournal(
  BuildContext context, {
  required Prefs prefs,
  required ShotStore store,
}) => Navigator.of(context).push<void>(
  MaterialPageRoute(
    builder: (_) => JournalPage(prefs: prefs, store: store),
  ),
);

class JournalPage extends StatelessWidget {
  const JournalPage({super.key, required this.prefs, required this.store});

  final Prefs prefs;
  final ShotStore store;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final safe = MediaQuery.paddingOf(context);

    return Scaffold(
      body: AppBackground(
        child: ListenableBuilder(
          listenable: prefs,
          builder: (context, _) {
            final shots = prefs.shots;
            // Статистика и графики — только по взвешенным проливам. Без весов
            // журнал остаётся журналом: что и сколько лилось, при какой
            // температуре. Рисовать графики по времени можно, но время само по
            // себе ничего не значит — оно значит что-то рядом с весом.
            final weighed = [
              for (final s in shots)
                if (s.weighed) s,
            ];
            final aimed = [
              for (final s in weighed)
                if (s.miss != null) s,
            ];

            return Column(
              children: [
                SizedBox(height: math.max(safe.top, 20) + 4),
                _Header(title: t.weightJournal),
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(
                      18,
                      6,
                      18,
                      math.max(safe.bottom, 12) + 20,
                    ),
                    children: [
                      if (shots.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 28),
                          child: SheetCaption(t.weightJournalEmpty),
                        )
                      else ...[
                        if (weighed.isNotEmpty) ...[
                          SheetSectionTitle(t.journalStats),
                          _Summary(shots: shots, aimed: aimed),
                        ],
                        if (aimed.length >= 2) ...[
                          const SizedBox(height: 18),
                          SheetSectionTitle(t.journalAccuracy),
                          _MissChart(shots: aimed),
                        ],
                        if (weighed.length >= 2) ...[
                          const SizedBox(height: 14),
                          SheetSectionTitle(t.journalTiming),
                          SheetCaption(
                            t.journalTimingHint,
                            align: TextAlign.start,
                          ),
                          const SizedBox(height: 8),
                          _TimeChart(shots: weighed),
                        ],
                        const SizedBox(height: 18),
                        SheetSectionTitle(t.journalPours),
                        for (final s in shots.take(60))
                          _Row(
                            shot: s,
                            fahrenheit: prefs.fahrenheit,
                            onTap: () => openShot(
                              context,
                              shot: s,
                              prefs: prefs,
                              store: store,
                            ),
                          ),
                        const SizedBox(height: 20),
                        Center(
                          child: SheetChip(
                            label: t.weightJournalClear,
                            onTap: () {
                              prefs.clearShots();
                              // Кривые без итогов — мусор, который никто уже
                              // не откроет.
                              store.clear();
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Шапка экрана: назад и название. Своя, а не AppBar: у приложения нет ни
/// одной полосы Material, и заводить её ради одного экрана незачем.
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
          // Стрелки назад в наборе нет, а разворачивать «вперёд» честнее, чем
          // тащить ради одного экрана чужой значок.
          icon: KIcon.chevronRight,
          flipped: true,
          onTap: () => Navigator.of(context).maybePop(),
          semanticLabel: MaterialLocalizations.of(context).backButtonTooltip,
        ),
        Expanded(
          child: Text(title, textAlign: TextAlign.center, style: K.title),
        ),
        // Уравновешивает кнопку слева, чтобы заголовок стоял по центру.
        const SizedBox(width: 52),
      ],
    ),
  );
}

/// Три числа, ради которых журнал и открывают.
class _Summary extends StatelessWidget {
  const _Summary({required this.shots, required this.aimed});

  final List<ShotRecord> shots;

  /// Проливы, у которых была цель: только по ним промах и имеет смысл.
  final List<ShotRecord> aimed;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    // Средний промах — по модулю: недолив на грамм и перелив на грамм в сумме
    // дали бы ноль и красивую ложь.
    final miss = aimed.isEmpty
        ? null
        : aimed.map((s) => s.miss!.abs()).reduce((a, b) => a + b) /
              aimed.length;
    final time = shots.isEmpty
        ? null
        : shots.map((s) => s.elapsed.inSeconds).reduce((a, b) => a + b) /
              shots.length;

    return Row(
      children: [
        _Stat(label: t.journalCount, value: '${shots.length}'),
        _Stat(
          label: t.journalAvgMiss,
          value: miss == null ? '—' : '±${miss.toStringAsFixed(1)}',
          unit: miss == null ? null : t.gramsUnit,
        ),
        _Stat(
          label: t.journalAvgTime,
          value: time == null ? '—' : time.round().toString(),
          unit: time == null ? null : t.secondsUnit,
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.unit});

  final String label;
  final String value;
  final String? unit;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              value,
              style: const TextStyle(
                color: K.textBright,
                fontSize: 26,
                fontWeight: FontWeight.w300,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            if (unit != null) ...[
              const SizedBox(width: 3),
              Text(unit!, style: K.caption.copyWith(color: K.textDim2)),
            ],
          ],
        ),
        const SizedBox(height: 3),
        Text(label, style: K.caption.copyWith(color: K.textDim)),
      ],
    ),
  );
}

/// График промахов: точка на пролив, ноль посередине, полоса допуска вокруг.
///
/// Показывает ровно то, ради чего весь контур: пристрелялся он или гуляет.
/// Точки идут слева направо от старых к свежим, так что обучение видно как
/// сходящийся к нулю хвост.
class _MissChart extends StatelessWidget {
  const _MissChart({required this.shots});

  final List<ShotRecord> shots;

  /// Промах, который считается попаданием: разрешение весов 0.1 г, а
  /// квантование потока даёт ещё столько же — точнее не бывает.
  static const double tolerance = 0.5;

  @override
  Widget build(BuildContext context) {
    // Свежие справа: в журнале они первые, здесь порядок обратный.
    final data = shots.take(24).toList().reversed.toList();
    return Container(
      height: 132,
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
      decoration: BoxDecoration(
        color: K.rowBg,
        borderRadius: BorderRadius.circular(K.rRow),
        border: Border.all(color: K.glassBorder),
      ),
      child: CustomPaint(
        painter: _MissPainter(
          misses: [for (final s in data) s.miss!],
          tolerance: tolerance,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _MissPainter extends CustomPainter {
  _MissPainter({required this.misses, required this.tolerance});

  final List<double> misses;
  final double tolerance;

  @override
  void paint(Canvas canvas, Size size) {
    if (misses.isEmpty) return;

    // Шкалу держим не меньше ±1.5 г: иначе на череде идеальных проливов
    // микроскопический разброс растянется во всю высоту и напугает.
    final peak = math.max(
      1.5,
      misses.map((m) => m.abs()).reduce(math.max) * 1.15,
    );
    final mid = size.height / 2;
    double y(double g) => mid - g / peak * mid;

    // Полоса допуска — то, во что мы вообще способны попасть.
    canvas.drawRect(
      Rect.fromLTRB(0, y(tolerance), size.width, y(-tolerance)),
      Paint()..color = K.success.withValues(alpha: 0.08),
    );
    canvas.drawLine(
      Offset(0, mid),
      Offset(size.width, mid),
      Paint()
        ..color = const Color(0x33FFFFFF)
        ..strokeWidth = 1,
    );

    final n = misses.length;
    final step = n == 1 ? 0.0 : size.width / (n - 1);
    final dx = n == 1 ? size.width / 2 : 0.0;

    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..color = K.water.withValues(alpha: 0.5);

    final path = Path();
    for (var i = 0; i < n; i++) {
      final p = Offset(dx + step * i, y(misses[i].clamp(-peak, peak)));
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    canvas.drawPath(path, line);

    for (var i = 0; i < n; i++) {
      final m = misses[i];
      final p = Offset(dx + step * i, y(m.clamp(-peak, peak)));
      canvas.drawCircle(
        p,
        3,
        Paint()..color = m.abs() <= tolerance ? K.success : K.amber,
      );
    }
  }

  @override
  bool shouldRepaint(_MissPainter old) =>
      old.misses.length != misses.length || old.tolerance != tolerance;
}

/// Длительность проливов. Отвечает не за контур, а за помол: при одной дозе и
/// одной цели ровное время значит ровный помол, а уползающее — что пора
/// подкрутить. Ни одна другая цифра в журнале про это не говорит.
class _TimeChart extends StatelessWidget {
  const _TimeChart({required this.shots});

  final List<ShotRecord> shots;

  @override
  Widget build(BuildContext context) {
    final data = shots.take(24).toList().reversed.toList();
    return Container(
      height: 92,
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
      decoration: BoxDecoration(
        color: K.rowBg,
        borderRadius: BorderRadius.circular(K.rRow),
        border: Border.all(color: K.glassBorder),
      ),
      child: CustomPaint(
        painter: _TimePainter([for (final s in data) s.elapsed.inSeconds]),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _TimePainter extends CustomPainter {
  _TimePainter(this.seconds);

  final List<int> seconds;

  @override
  void paint(Canvas canvas, Size size) {
    if (seconds.length < 2) return;

    final avg = seconds.reduce((a, b) => a + b) / seconds.length;
    // Шкала вокруг среднего, но не уже ±5 с: на ровной серии микроскопический
    // разброс растянулся бы во всю высоту и выглядел бы бедой.
    final spread = math.max(
      5.0,
      seconds.map((s) => (s - avg).abs()).reduce(math.max) * 1.2,
    );
    final mid = size.height / 2;
    double y(num s) => mid - (s - avg) / spread * mid;

    canvas.drawLine(
      Offset(0, mid),
      Offset(size.width, mid),
      Paint()
        ..color = const Color(0x33FFFFFF)
        ..strokeWidth = 1,
    );

    final step = size.width / (seconds.length - 1);
    final path = Path();
    for (var i = 0; i < seconds.length; i++) {
      final p = Offset(step * i, y(seconds[i]));
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = K.amber.withValues(alpha: 0.75),
    );
  }

  @override
  bool shouldRepaint(_TimePainter old) => old.seconds.length != seconds.length;
}

class _Row extends StatelessWidget {
  const _Row({
    required this.shot,
    required this.fahrenheit,
    required this.onTap,
  });

  final ShotRecord shot;
  final bool fahrenheit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final miss = shot.miss;
    final temp =
        '${toDisplayTemp(shot.temperatureC, fahrenheit)}'
        '${fahrenheit ? '°F' : '°C'}';

    // Наверху дата и время: пролив опознают по ним, а не по весу — весов
    // могло и не быть. Итог уходит строкой ниже.
    final details = [
      if (shot.weighed) '${shot.finalG!.toStringAsFixed(1)} ${t.gramsUnit}',
      if (shot.ratio != null) '1:${shot.ratio!.toStringAsFixed(1)}',
      t.seconds(shot.elapsed.inSeconds),
      temp,
    ].join('  ·  ');

    return KTap(
      onTap: onTap,
      scale: 0.99,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    shotStamp(t, shot.at),
                    style: K.rowTitle.copyWith(color: K.text),
                  ),
                  const SizedBox(height: 3),
                  Text(details, style: K.rowDesc),
                ],
              ),
            ),
            // Промах имеет смысл только там, где цель заказывали.
            if (miss != null) ...[
              Text(
                miss >= 0
                    ? t.weightMissOver(miss.toStringAsFixed(1))
                    : t.weightMissUnder(miss.toStringAsFixed(1)),
                style: K.rowTitle.copyWith(
                  color: miss.abs() <= _MissChart.tolerance
                      ? K.success
                      : K.amber,
                ),
              ),
              const SizedBox(width: 8),
            ],
            const KIconView(KIcon.chevronRight, size: 15, color: K.textMuted),
          ],
        ),
      ),
    );
  }
}
