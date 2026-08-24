import 'package:flutter/material.dart';

import '../theme.dart';
import 'k_icons.dart';

/// Круглая стеклянная кнопка со значком.
///
/// Одна и та же в шапке, у будильника и над нижней панелью: меню, связь,
/// таймер, режим — это углы экрана, и они должны выглядеть одинаково, иначе
/// читаются как разные сущности.
class RoundIconButton extends StatelessWidget {
  const RoundIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.color = K.icon,
    this.border,
    this.glow,
    this.size = 44,
    this.iconSize = 18,
    this.disabled = false,
    this.badge,
    this.child,
    this.semanticLabel,
  });

  final KIcon icon;
  final VoidCallback? onTap;

  final Color color;

  /// Своя обводка вместо glassBorder — обычно светлый акцент режима.
  final Color? border;

  /// Свечение вокруг кнопки: 0 0 16 {glow}.
  final Color? glow;

  final double size;
  final double iconSize;

  /// Кнопка не нажимается: opacity .45, значок textDisabled, свечения нет.
  final bool disabled;

  /// Горящая точка на кромке — «что-то подключено». Кнопка при этом остаётся
  /// обычным стеклом: цветная рамка кричала бы, а точка просто светится.
  final Color? badge;

  /// Своё содержимое вместо значка (например, спираль с каплей).
  final Widget? child;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final g = disabled ? null : glow;
    final dot = disabled ? null : badge;
    return AnimatedOpacity(
      opacity: disabled ? 0.45 : 1,
      duration: const Duration(milliseconds: 220),
      child: KTap(
        onTap: disabled ? null : onTap,
        semanticLabel: semanticLabel,
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Glass(
                shape: BoxShape.circle,
                radius: size,
                blur: K.blurCell,
                border: disabled ? null : border,
                shadow: g == null
                    ? null
                    : [BoxShadow(color: g, blurRadius: 16)],
                child: Center(
                  child:
                      child ??
                      KIconView(
                        icon,
                        size: iconSize,
                        color: disabled ? K.textDisabled : color,
                        stroke: 1.8,
                      ),
                ),
              ),
              if (dot != null)
                Positioned(
                  // Точка сидит на самой кромке под 45°: снаружи её половина
                  // выходит за круг, оттого и читается как огонёк на ободе.
                  right: size * 0.5 - size * 0.354 - 3.5,
                  top: size * 0.5 - size * 0.354 - 3.5,
                  child: _Dot(color: dot),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Огонёк на кромке круглой кнопки.
class _Dot extends StatelessWidget {
  const _Dot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 7,
    height: 7,
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      // Тёмный поясок отрезает точку от кромки — иначе она сливается с ней
      // в одно светлое пятно.
      border: Border.all(color: K.bg0.withValues(alpha: 0.75), width: 1.2),
      boxShadow: [
        BoxShadow(color: color.withValues(alpha: 0.9), blurRadius: 8),
        BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 16),
      ],
    ),
  );
}
