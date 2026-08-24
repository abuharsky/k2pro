import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Кольцо ожидания: дуга, у которой хвост уходит в прозрачность, и вся она
/// равномерно крутится.
///
/// Материаловский CircularProgressIndicator сюда не годится: он рисует дугу
/// постоянной плотности и сам меняет её длину рывками — на стеклянной кнопке
/// это выглядит чужим. Здесь длина дуги постоянна, меняется только угол, а
/// прозрачный хвост даёт то самое ощущение скольжения.
class KSpinner extends StatefulWidget {
  const KSpinner({
    super.key,
    required this.color,
    this.size = 18,
    this.stroke = 2.2,
    this.period = const Duration(milliseconds: 900),
  });

  final Color color;
  final double size;
  final double stroke;
  final Duration period;

  @override
  State<KSpinner> createState() => _KSpinnerState();
}

class _KSpinnerState extends State<KSpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _turn = AnimationController(
    vsync: this,
    duration: widget.period,
  )..repeat();

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: widget.size,
    height: widget.size,
    child: AnimatedBuilder(
      animation: _turn,
      builder: (context, _) => CustomPaint(
        painter: _SpinnerPainter(
          turn: _turn.value,
          color: widget.color,
          stroke: widget.stroke,
        ),
      ),
    ),
  );
}

class _SpinnerPainter extends CustomPainter {
  _SpinnerPainter({
    required this.turn,
    required this.color,
    required this.stroke,
  });

  /// 0..1 — полный оборот.
  final double turn;
  final Color color;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final circle = rect.deflate(stroke / 2);
    final angle = turn * 2 * math.pi;

    // Хвост дуги гаснет: SweepGradient идёт от прозрачного к полному цвету и
    // вращается вместе с ней.
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: 2 * math.pi,
        transform: GradientRotation(angle - math.pi / 2),
        colors: [
          color.withValues(alpha: 0),
          color.withValues(alpha: 0.15),
          color,
        ],
        stops: const [0, 0.45, 0.92],
      ).createShader(rect);

    // Дуга чуть короче полного круга: разрыв и делает вращение заметным.
    canvas.drawArc(circle, angle - math.pi / 2, math.pi * 1.72, false, paint);
  }

  @override
  bool shouldRepaint(_SpinnerPainter o) =>
      o.turn != turn || o.color != color || o.stroke != stroke;
}
