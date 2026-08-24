import 'package:flutter/material.dart';

import '../../model/brew_phase.dart';

/// Радиальное свечение позади машины. Цвет — по фазе цикла; пока цикл идёт,
/// пятно «дышит»: 1 → 1.06 по размеру и .7 → 1 по прозрачности за 2.4 с.
class PhaseAura extends StatefulWidget {
  const PhaseAura({
    super.key,
    required this.phase,
    required this.running,
    this.size = 340,
  });

  final BrewPhase phase;
  final bool running;
  final double size;

  /// Цвет ауры фазы. Наружу торчит и для подсветки секции разреза, чтобы
  /// пятно и работающий узел были одного цвета.
  static Color colorOf(BrewPhase phase) => switch (phase) {
    BrewPhase.heating => const Color(0x2BFF8C00),
    BrewPhase.preInfusion => const Color(0x2B4DA3FF),
    BrewPhase.standstill => const Color(0x244DA3FF),
    BrewPhase.extraction => const Color(0x30FFB000),
    BrewPhase.done => const Color(0x265EC26A),
    _ => const Color(0x1A4DA3FF),
  };

  /// Плотный цвет фазы — им подсвечивается работающая секция разреза.
  static Color solidOf(BrewPhase phase) => switch (phase) {
    BrewPhase.heating => const Color(0xFFFF9E70),
    BrewPhase.preInfusion || BrewPhase.standstill => const Color(0xFF7CBBFF),
    BrewPhase.extraction => const Color(0xFFFFB000),
    BrewPhase.done => const Color(0xFF5EC26A),
    _ => const Color(0xFF4DA3FF),
  };

  @override
  State<PhaseAura> createState() => _PhaseAuraState();
}

class _PhaseAuraState extends State<PhaseAura>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(PhaseAura old) {
    super.didUpdateWidget(old);
    _sync();
  }

  /// В покое анимацию гасим: она тут только чтобы показать, что идёт работа.
  void _sync() {
    if (widget.running && !_breath.isAnimating) {
      _breath.repeat(reverse: true);
    } else if (!widget.running && _breath.isAnimating) {
      _breath
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = PhaseAura.colorOf(widget.phase);
    return IgnorePointer(
      child: Center(
        child: AnimatedBuilder(
          animation: CurvedAnimation(parent: _breath, curve: Curves.easeInOut),
          builder: (context, child) {
            final t = Curves.easeInOut.transform(_breath.value);
            return Transform.scale(
              scale: widget.running ? 1 + 0.06 * t : 1,
              child: Opacity(
                opacity: widget.running ? 0.7 + 0.3 * t : 1,
                child: child,
              ),
            );
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 600),
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [color, color.withValues(alpha: 0)],
                stops: const [0, 0.72],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
