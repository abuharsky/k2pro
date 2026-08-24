import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ble/protocol.dart';
import '../theme.dart';
import 'spinner.dart';

/// Что делает главная кнопка экрана.
enum CtaKind { connect, start, stop, done, cancelAlarm }

/// Главная кнопка: подключиться, старт, стоп, готово, отменить таймер.
class BarCta {
  const BarCta({
    required this.kind,
    required this.label,
    required this.mode,
    this.busy = false,
    this.onTap,
  });

  final CtaKind kind;
  final String label;

  /// Каким режимом красить кнопку старта.
  final WorkMode mode;

  /// Команда ушла, ответа ещё нет.
  final bool busy;

  final VoidCallback? onTap;
}

/// Нижний ряд: одна кнопка во всю ширину.
///
/// Больше внизу ничего нет. Режим, таймер и все времена цикла — карточки
/// таймлайна: там у каждого числа есть имя и свой лист. Внизу остаётся ровно
/// одно действие — то, ради которого экран и открыли.
class BottomBar extends StatelessWidget {
  const BottomBar({super.key, required this.cta});

  final BarCta cta;

  /// Высота ряда вместе с полями: 12 сверху, 52 сама, 14 снизу.
  static const double cell = 52;
  static const double height = cell + 12 + 14;

  /// Ширина кнопки задана в пикселях, а не долей экрана: нажимают её одним
  /// пальцем, и на планшете или на Mac растягивать её через весь экран
  /// незачем — она просто стоит по центру. На узком телефоне сожмётся по
  /// доступному месту.
  static const double buttonWidth = 300;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: buttonWidth),
        child: _Cta(cta: cta),
      ),
    ),
  );
}

/// Главная кнопка: заливка режима в покое, красная в работе, зелёная в конце.
class _Cta extends StatelessWidget {
  const _Cta({required this.cta});

  final BarCta cta;

  @override
  Widget build(BuildContext context) {
    final c = cta;
    final style = ModeStyle.of(c.mode);
    final enabled = c.onTap != null;
    final red = c.kind == CtaKind.stop || c.kind == CtaKind.cancelAlarm;

    final (List<Color> colors, Color fg, Color glow) = switch (c.kind) {
      // Отмена — тоже остановка ожидания, и она всегда красная.
      CtaKind.stop ||
      CtaKind.cancelAlarm => (K.stopGrad, K.stopText, const Color(0x73D63B2F)),
      CtaKind.done => (K.doneGrad, K.doneText, const Color(0x663DA452)),
      _ => (style.gradient, style.onColor, style.glow),
    };

    return KTap(
      onTap: _tap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        height: BottomBar.cell,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: enabled
                ? colors
                : [
                    colors.first.withValues(alpha: 0.35),
                    colors.last.withValues(alpha: 0.35),
                  ],
          ),
          borderRadius: BorderRadius.circular(K.rPill),
          border: red ? Border.all(color: const Color(0x2EFFFFFF)) : null,
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: glow,
                    blurRadius: red ? 30 : 28,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Блик по верхней кромке: без него залитая красным кнопка
            // выглядит плоской наклейкой.
            if (red && enabled)
              const Positioned(
                left: 1,
                right: 1,
                top: 1,
                height: 1,
                child: IgnorePointer(
                  child: ColoredBox(color: Color(0x2EFFFFFF)),
                ),
              ),
            c.busy
                ? KSpinner(color: fg)
                // Значков на кнопке нет: подпись и цвет уже говорят всё.
                : FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Text(
                        c.label,
                        maxLines: 1,
                        style: K.ctaLabel.copyWith(color: fg),
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
  }

  VoidCallback? get _tap {
    final onTap = cta.onTap;
    if (onTap == null) return null;
    return () {
      HapticFeedback.selectionClick();
      onTap();
    };
  }
}
