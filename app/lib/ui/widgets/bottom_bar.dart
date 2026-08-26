import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ble/protocol.dart';
import '../../model/pipeline.dart' show CtaKind;
import '../theme.dart';
import 'spinner.dart';

/// Главная кнопка: подключиться, старт, стоп, готово, отменить таймер.
class BarCta {
  const BarCta({
    required this.kind,
    required this.label,
    required this.mode,
    this.busy = false,
    this.slideToConfirm = false,
    this.onTap,
  });

  final CtaKind kind;
  final String label;

  /// Каким режимом красить кнопку старта.
  final WorkMode mode;

  /// Команда ушла, ответа ещё нет.
  final bool busy;

  /// Потенциально опасный запуск с нагревом требует направленного жеста.
  final bool slideToConfirm;

  final VoidCallback? onTap;
}

/// Нижний ряд: одна кнопка во всю ширину.
///
/// Больше внизу ничего нет. Режим, таймер и все времена цикла — карточки
/// таймлайна: там у каждого числа есть имя и свой лист. Внизу остаётся ровно
/// одно действие — то, ради которого экран и открыли.
class BottomBar extends StatelessWidget {
  const BottomBar({super.key, required this.cta, this.leading});

  final BarCta cta;

  /// Кнопка слева от пуска — весы. Той же высоты и того же скругления: это
  /// один ряд управления, а не кнопка, приткнутая рядом.
  final Widget? leading;

  /// Высота ряда вместе с полями: 12 сверху, 52 сама, 14 снизу.
  static const double cell = 52;
  static const double height = cell + 12 + 14;

  /// Ширина кнопки задана в пикселях, а не долей экрана: нажимают её одним
  /// пальцем, и на планшете или на Mac растягивать её через весь экран
  /// незачем — она просто стоит по центру. На узком телефоне сожмётся по
  /// доступному месту.
  static const double buttonWidth = 300;

  /// Ширина кнопки слева и зазор до пуска. Зазор заметно больше, чем между
  /// элементами внутри кнопок: это две разные команды, и слипаться им нельзя —
  /// пуск нащупывают не глядя.
  static const double leadingWidth = 76;
  static const double gap = 18;

  @override
  Widget build(BuildContext context) {
    final side = leading;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: side == null
                ? buttonWidth
                : buttonWidth + leadingWidth + gap,
          ),
          child: Row(
            children: [
              if (side != null) ...[
                SizedBox(width: leadingWidth, height: cell, child: side),
                const SizedBox(width: gap),
              ],
              Expanded(child: _Cta(cta: cta)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Главная кнопка: заливка режима в покое, красная в работе, зелёная в конце.
class _Cta extends StatefulWidget {
  const _Cta({required this.cta});

  final BarCta cta;

  @override
  State<_Cta> createState() => _CtaState();
}

class _CtaState extends State<_Cta> with SingleTickerProviderStateMixin {
  late final AnimationController _slide = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  );

  bool _triggered = false;

  @override
  void didUpdateWidget(_Cta oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cta.kind != widget.cta.kind ||
        oldWidget.cta.slideToConfirm != widget.cta.slideToConfirm ||
        oldWidget.cta.busy != widget.cta.busy) {
      _resetSlide();
    }
  }

  @override
  void dispose() {
    _slide.dispose();
    super.dispose();
  }

  void _beginSlide(DragStartDetails _) {
    if (widget.cta.onTap == null) return;
    // Каждый жест начинается от левого края: иначе доехавший и не сброшенный
    // ползунок превратил бы случайный микро-свайп в пуск нагревателя.
    _resetSlide();
    HapticFeedback.selectionClick();
  }

  void _updateSlide(DragUpdateDetails details, double travel) {
    if (widget.cta.onTap == null || travel <= 0) return;
    _slide.value = (_slide.value + details.delta.dx / travel).clamp(0.0, 1.0);
  }

  void _endSlide(DragEndDetails _) {
    if (_slide.value < 0.82 || widget.cta.onTap == null) {
      _slide.reverse();
      return;
    }
    if (_triggered) return;
    _triggered = true;
    _slide.animateTo(1, duration: const Duration(milliseconds: 80));
    HapticFeedback.mediumImpact();
    widget.cta.onTap!();
    // Пуск могли отменить в диалоге — тогда вид кнопки не меняется и ползунок
    // остался бы доехавшим, без подписи. Возвращаем его сами.
    Future<void>.delayed(const Duration(milliseconds: 500), () {
      if (!mounted || !_triggered) return;
      _triggered = false;
      _slide.reverse();
    });
  }

  void _cancelSlide() {
    if (!_triggered) _slide.reverse();
  }

  void _resetSlide() {
    _triggered = false;
    _slide.stop();
    _slide.value = 0;
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.cta;
    final style = ModeStyle.of(c.mode);
    final enabled = c.onTap != null;
    final red =
        c.kind == CtaKind.stop ||
        c.kind == CtaKind.cancelAlarm ||
        c.kind == CtaKind.blocked;

    final (List<Color> colors, Color fg, Color glow) = switch (c.kind) {
      // Отмена — тоже остановка ожидания, и она всегда красная.
      CtaKind.stop ||
      CtaKind.cancelAlarm ||
      // Ошибка держит кнопку красной: пока её не прочли, пуск недоступен.
      CtaKind.blocked => (K.stopGrad, K.stopText, const Color(0x73D63B2F)),
      CtaKind.done => (K.doneGrad, K.doneText, const Color(0x663DA452)),
      _ => (style.gradient, style.onColor, style.glow),
    };

    Widget surface(double slideProgress, {double slideTravel = 0}) =>
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          height: BottomBar.cell,
          clipBehavior: Clip.antiAlias,
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
            border: red || c.slideToConfirm
                ? Border.all(color: const Color(0x2EFFFFFF))
                : null,
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
              if (c.slideToConfirm && !c.busy)
                Positioned(
                  left: 52,
                  right: 8,
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: (1 - slideProgress * 1.5).clamp(0.0, 1.0),
                      child: Text(
                        c.label,
                        maxLines: 1,
                        textAlign: TextAlign.center,
                        style: K.ctaLabel.copyWith(fontSize: 15, color: fg),
                      ),
                    ),
                  ),
                ),
              if (c.slideToConfirm && !c.busy)
                Positioned(
                  left: 4 + slideTravel * slideProgress,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xEBFFFFFF),
                      shape: BoxShape.circle,
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x33000000),
                          blurRadius: 8,
                          offset: Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.arrow_forward_rounded,
                      size: 27,
                      color: colors.last,
                    ),
                  ),
                ),
              if (!c.slideToConfirm || c.busy)
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
        );

    if (!c.slideToConfirm) {
      return KTap(onTap: _tap, semanticLabel: c.label, child: surface(0));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final travel = constraints.maxWidth - 52;
        return Semantics(
          button: true,
          enabled: enabled,
          label: c.label,
          onTap: enabled ? _tap : null,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: enabled ? _beginSlide : null,
            onHorizontalDragUpdate: enabled
                ? (details) => _updateSlide(details, travel)
                : null,
            onHorizontalDragEnd: enabled ? _endSlide : null,
            onHorizontalDragCancel: enabled ? _cancelSlide : null,
            child: AnimatedBuilder(
              animation: _slide,
              builder: (context, _) =>
                  surface(_slide.value, slideTravel: travel),
            ),
          ),
        );
      },
    );
  }

  VoidCallback? get _tap {
    final onTap = widget.cta.onTap;
    if (onTap == null) return null;
    return () {
      HapticFeedback.selectionClick();
      onTap();
    };
  }
}
