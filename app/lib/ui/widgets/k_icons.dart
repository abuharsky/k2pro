import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Свой набор значков вместо иконочного шрифта.
///
/// Material-глифы выбивались из остального: другая толщина, другие срезы,
/// другая оптическая плотность. Здесь всё нарисовано в одной сетке 24×24
/// обводкой 1.5 со скруглёнными концами, поэтому значки читаются как семья.
enum KIcon {
  thermometer,
  timer,
  alarm,
  coil,
  streams,
  pause,
  flame,
  droplet,
  pump,
  preinfusion,
  cup,
  menu,
  chevronDown,
  chevronRight,
  speedometer,
  heatBrew,
  play,
  stop,
  bluetooth,
  plus,
  minus,
}

class KIconView extends StatelessWidget {
  const KIconView(
    this.icon, {
    super.key,
    this.size = 22,
    required this.color,
    this.stroke = 1.7,
  });

  final KIcon icon;
  final double size;
  final Color color;
  final double stroke;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: CustomPaint(
      painter: _KIconPainter(icon: icon, color: color, stroke: stroke),
    ),
  );
}

class _KIconPainter extends CustomPainter {
  _KIconPainter({
    required this.icon,
    required this.color,
    required this.stroke,
  });

  final KIcon icon;
  final Color color;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    // Рисуем в сетке 24×24 и масштабируем — толщина обводки тоже.
    final k = size.width / 24;
    canvas.save();
    canvas.scale(k);

    // Толщина задаётся в конечных пикселях: делим на масштаб, иначе обводка
    // росла бы вместе со значком и мелкие иконки выглядели бы жирнее крупных.
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke / k
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    final fill = Paint()..color = color;

    switch (icon) {
      case KIcon.thermometer:
        _thermometer(canvas, line, fill, k);
      case KIcon.timer:
        _timer(canvas, line);
      case KIcon.alarm:
        _alarm(canvas, line);
      case KIcon.coil:
        _coil(canvas, line);
      case KIcon.streams:
        _streams(canvas, line);
      case KIcon.pause:
        _pause(canvas, fill);
      case KIcon.flame:
        _flame(canvas, line);
      case KIcon.droplet:
        _droplet(canvas, line);
      case KIcon.pump:
        _pump(canvas, line);
      case KIcon.preinfusion:
        _preinfusion(canvas, line);
      case KIcon.cup:
        _cup(canvas, line);
      case KIcon.menu:
        _menu(canvas, line);
      case KIcon.chevronDown:
        _chevronDown(canvas, line);
      case KIcon.chevronRight:
        _chevronRight(canvas, line);
      case KIcon.speedometer:
        _speedometer(canvas, line);
      case KIcon.heatBrew:
        _heatBrew(canvas, line);
      case KIcon.play:
        _play(canvas, fill);
      case KIcon.stop:
        _stop(canvas, fill);
      case KIcon.bluetooth:
        _bluetooth(canvas, line);
      case KIcon.plus:
        _plus(canvas, line);
      case KIcon.minus:
        _minus(canvas, line);
    }
    canvas.restore();
  }

  /// Колба со столбиком и делениями справа.
  void _thermometer(Canvas canvas, Paint line, Paint fill, double k) {
    final tube = Path()
      ..moveTo(9.6, 14.2)
      ..lineTo(9.6, 5.6)
      ..arcToPoint(const Offset(13.4, 5.6), radius: const Radius.circular(1.9))
      ..lineTo(13.4, 14.2);
    canvas.drawPath(tube, line);
    canvas.drawCircle(const Offset(11.5, 17.4), 3.9, line);
    // Ртуть: залитая колба и столбик до середины трубки.
    canvas.drawCircle(const Offset(11.5, 17.4), 2.1, fill);
    canvas.drawLine(
      const Offset(11.5, 17.4),
      const Offset(11.5, 10.4),
      Paint()
        ..color = color
        ..strokeWidth = 2.0 / k
        ..strokeCap = StrokeCap.round,
    );
    for (var i = 0; i < 3; i++) {
      final y = 7.8 + i * 2.6;
      canvas.drawLine(Offset(15.2, y), Offset(17.6, y), line);
    }
  }

  /// Секундомер: корпус, заводная головка сверху и стрелка.
  void _timer(Canvas canvas, Paint line) {
    canvas.drawCircle(const Offset(12, 13.8), 6.6, line);
    canvas.drawLine(const Offset(9.6, 3.4), const Offset(14.4, 3.4), line);
    canvas.drawLine(const Offset(12, 3.4), const Offset(12, 7.2), line);
    canvas.drawLine(const Offset(12, 13.8), const Offset(12, 9.9), line);
    canvas.drawLine(const Offset(12, 13.8), const Offset(15.4, 13.8), line);
  }

  void _flame(Canvas canvas, Paint line) {
    final p = Path()
      ..moveTo(12, 3.2)
      ..cubicTo(15.4, 7.2, 17.6, 9.6, 17.6, 13.4)
      ..cubicTo(17.6, 17.4, 15.1, 20.2, 12, 20.2)
      ..cubicTo(8.9, 20.2, 6.4, 17.4, 6.4, 13.4)
      ..cubicTo(6.4, 10.6, 8.2, 8.4, 9.6, 6.6)
      ..cubicTo(10.2, 8.6, 11.1, 9.8, 12.2, 10.6)
      ..cubicTo(12.2, 8.2, 11.6, 5.6, 12, 3.2)
      ..close();
    canvas.drawPath(p, line);
  }

  void _droplet(Canvas canvas, Paint line) {
    final p = Path()
      ..moveTo(12, 3.4)
      ..cubicTo(12, 3.4, 5.6, 10.6, 5.6, 14.6)
      ..arcToPoint(
        const Offset(18.4, 14.6),
        radius: const Radius.circular(6.4),
        clockwise: false,
      )
      ..cubicTo(18.4, 10.6, 12, 3.4, 12, 3.4)
      ..close();
    canvas.drawPath(p, line);
  }

  /// Помпа: корпус с ротором и двумя патрубками по бокам.
  void _pump(Canvas canvas, Paint line) {
    canvas.drawCircle(const Offset(12, 12.4), 7.2, line);
    canvas.drawCircle(const Offset(12, 12.4), 2.6, line);
    canvas.drawLine(const Offset(4.8, 12.4), const Offset(2.6, 12.4), line);
    canvas.drawLine(const Offset(19.2, 12.4), const Offset(21.4, 12.4), line);
    canvas.drawLine(const Offset(12, 5.2), const Offset(12, 3.2), line);
  }

  /// Предсмачивание: корзина с каплями над ней.
  void _preinfusion(Canvas canvas, Paint line) {
    final basket = Path()
      ..moveTo(5.6, 11.4)
      ..lineTo(18.4, 11.4)
      ..lineTo(16.2, 19.4)
      ..lineTo(7.8, 19.4)
      ..close();
    canvas.drawPath(basket, line);
    for (var i = 0; i < 3; i++) {
      final x = 8.6 + i * 3.4;
      canvas.drawLine(Offset(x, 4.4), Offset(x, 8.2), line);
    }
  }

  /// Чашка на блюдце.
  void _cup(Canvas canvas, Paint line) {
    final body = Path()
      ..moveTo(5.4, 7.6)
      ..lineTo(16.6, 7.6)
      ..lineTo(15.2, 16.2)
      ..cubicTo(15.0, 17.4, 14.0, 18.2, 12.8, 18.2)
      ..lineTo(9.2, 18.2)
      ..cubicTo(8.0, 18.2, 7.0, 17.4, 6.8, 16.2)
      ..close();
    canvas.drawPath(body, line);
    // Ручка.
    final handle = Path()
      ..moveTo(16.4, 9.6)
      ..cubicTo(19.6, 9.6, 19.6, 14.2, 16.0, 14.2);
    canvas.drawPath(handle, line);
    canvas.drawLine(const Offset(4.4, 20.8), const Offset(17.6, 20.8), line);
  }

  void _chevronDown(Canvas canvas, Paint line) {
    final p = Path()
      ..moveTo(6.6, 9.4)
      ..lineTo(12, 15)
      ..lineTo(17.4, 9.4);
    canvas.drawPath(p, line);
  }

  void _chevronRight(Canvas canvas, Paint line) {
    final p = Path()
      ..moveTo(9.4, 5.6)
      ..lineTo(15.6, 12)
      ..lineTo(9.4, 18.4);
    canvas.drawPath(p, line);
  }

  /// Спидометр: дуга со шкалой и стрелка — ступень подачи воды.
  void _speedometer(Canvas canvas, Paint line) {
    const center = Offset(12, 14.6);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: 7.4),
      math.pi * 0.98,
      math.pi * 1.04,
      false,
      line,
    );
    // Стрелка смотрит вправо-вверх: «ступень выше средней».
    canvas.drawLine(center, const Offset(16.2, 10.4), line);
    canvas.drawCircle(center, 1.3, Paint()..color = color);
  }

  void _menu(Canvas canvas, Paint line) {
    // Две линии: гамбургер в шапке нарисован ровно так.
    for (var i = 0; i < 2; i++) {
      final y = 9.4 + i * 5.2;
      canvas.drawLine(Offset(5.4, y), Offset(18.6, y), line);
    }
  }

  /// Треугольник со скруглёнными углами: острый угол в такой мелкой кнопке
  /// выглядел бы занозой.
  void _play(Canvas canvas, Paint fill) {
    const pts = [Offset(8.2, 5.4), Offset(18.4, 12), Offset(8.2, 18.6)];
    final p = Path();
    const r = 1.7;
    for (var i = 0; i < 3; i++) {
      final prev = pts[(i + 2) % 3];
      final cur = pts[i];
      final next = pts[(i + 1) % 3];
      final toPrev = (prev - cur);
      final toNext = (next - cur);
      final dp = toPrev / toPrev.distance;
      final dn = toNext / toNext.distance;
      final a = cur + dp * r;
      final b = cur + dn * r;
      if (i == 0) {
        p.moveTo(a.dx, a.dy);
      } else {
        p.lineTo(a.dx, a.dy);
      }
      p.quadraticBezierTo(cur.dx, cur.dy, b.dx, b.dy);
    }
    p.close();
    canvas.drawPath(p, fill);
  }

  void _stop(Canvas canvas, Paint fill) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: const Offset(12, 12), width: 11, height: 11),
        const Radius.circular(2.6),
      ),
      fill,
    );
  }

  void _bluetooth(Canvas canvas, Paint line) {
    final p = Path()
      ..moveTo(7.4, 8.2)
      ..lineTo(16.6, 15.8)
      ..lineTo(12, 20)
      ..lineTo(12, 4)
      ..lineTo(16.6, 8.2)
      ..lineTo(7.4, 15.8);
    canvas.drawPath(p, line);
  }

  /// Будильник: циферблат со стрелками и двумя «ушами» сверху.
  void _alarm(Canvas canvas, Paint line) {
    canvas.drawCircle(const Offset(12, 13.4), 7.2, line);
    canvas.drawLine(const Offset(12, 9.6), const Offset(12, 13.4), line);
    canvas.drawLine(const Offset(12, 13.4), const Offset(15, 14.8), line);
    canvas.drawLine(const Offset(4.6, 5.4), const Offset(7.4, 7.6), line);
    canvas.drawLine(const Offset(19.4, 5.4), const Offset(16.6, 7.6), line);
  }

  /// Нагрев — спираль: две волнистые линии одна под другой.
  void _coil(Canvas canvas, Paint line) {
    for (var i = 0; i < 2; i++) {
      final y = 9.4 + i * 5.2;
      final p = Path()
        ..moveTo(4.2, y)
        ..cubicTo(6.2, y - 3.2, 9.8, y + 3.2, 12, y)
        ..cubicTo(14.2, y - 3.2, 17.8, y + 3.2, 19.8, y);
      canvas.drawPath(p, line);
    }
  }

  /// «Нагрев и пролив» одним значком: спираль и капля рядом.
  void _heatBrew(Canvas canvas, Paint line) {
    for (var i = 0; i < 2; i++) {
      final y = 9.8 + i * 4.6;
      final p = Path()
        ..moveTo(2.2, y)
        ..cubicTo(3.8, y - 2.6, 6.6, y + 2.6, 8.2, y)
        ..cubicTo(9.8, y - 2.6, 12.6, y + 2.6, 14.2, y);
      canvas.drawPath(p, line);
    }
    final drop = Path()
      ..moveTo(19, 6.4)
      ..cubicTo(19, 6.4, 15.4, 10.6, 15.4, 13.2)
      ..arcToPoint(
        const Offset(22.6, 13.2),
        radius: const Radius.circular(3.6),
        clockwise: false,
      )
      ..cubicTo(22.6, 10.6, 19, 6.4, 19, 6.4)
      ..close();
    canvas.drawPath(drop, line);
  }

  /// Пролив — три падающие струи разной длины.
  void _streams(Canvas canvas, Paint line) {
    const tops = [5.6, 3.6, 5.6];
    const bottoms = [16.4, 18.4, 16.4];
    for (var i = 0; i < 3; i++) {
      final x = 7.2 + i * 4.8;
      canvas.drawLine(Offset(x, tops[i]), Offset(x, bottoms[i]), line);
    }
    // Донышко: капли уже сорвались со струй.
    canvas.drawCircle(const Offset(7.2, 19.6), 0.9, Paint()..color = color);
    canvas.drawCircle(const Offset(16.8, 19.6), 0.9, Paint()..color = color);
  }

  /// Пауза: две скобы. Ждать — это не значок узла машины, а знак остановки.
  void _pause(Canvas canvas, Paint fill) {
    for (var i = 0; i < 2; i++) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(8.2 + i * 5.2, 6.4, 2.4, 11.2),
          const Radius.circular(1.2),
        ),
        fill,
      );
    }
  }

  void _plus(Canvas canvas, Paint line) {
    canvas.drawLine(const Offset(12, 5.6), const Offset(12, 18.4), line);
    canvas.drawLine(const Offset(5.6, 12), const Offset(18.4, 12), line);
  }

  void _minus(Canvas canvas, Paint line) {
    canvas.drawLine(const Offset(5.6, 12), const Offset(18.4, 12), line);
  }

  @override
  bool shouldRepaint(_KIconPainter o) =>
      o.icon != icon || o.color != color || o.stroke != stroke;
}
