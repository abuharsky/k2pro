import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/l10n_ext.dart';
import '../theme.dart';
import '../widgets/k_icons.dart';

/// Общая обвязка модальных листов: затемнение, стекло, ручка, заголовок.
///
/// Лист выезжает снизу за 0.35 с; фон — sheetBg с размытием 30 и скруглением
/// 30 сверху. От краёв экрана он отодвинут на [SheetShell.inset]: лист,
/// упирающийся в самые бортики, читается как второй экран, а отступ оставляет
/// его тем, что он есть, — карточкой, лежащей поверх. Вширь лист не
/// растягивается дальше [SheetShell.maxWidth] и держится по центру.
Future<T?> showAppSheet<T>(
  BuildContext context, {
  required String title,
  Widget? trailing,
  required WidgetBuilder builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: K.overlay,
    isScrollControlled: true,
    sheetAnimationStyle: AnimationStyle(
      duration: const Duration(milliseconds: 350),
      reverseDuration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    ),
    builder: (ctx) =>
        SheetShell(title: title, trailing: trailing, child: builder(ctx)),
  );
}

/// Корпус листа. Вынесен отдельно, чтобы им пользовались и листы со своим
/// состоянием (поиск устройств).
class SheetShell extends StatelessWidget {
  const SheetShell({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
  });

  final String title;
  final Widget child;

  /// Контрол справа от заголовка — переключатель или счётчик.
  final Widget? trailing;

  /// Зазор до бортиков экрана.
  static const double inset = 8;

  /// Предел ширины. На телефоне лист и так уже — ограничение не работает;
  /// на планшете и на маке оно не даёт ряду настроек разъехаться на всю
  /// ширину, где кнопки уезжают от значений на пол-экрана.
  static const double maxWidth = 460;

  /// Предел высоты — доля экрана. Лист, дошедший до самого верха, перестаёт
  /// быть листом и читается как второй экран; полоска фона над ним держит
  /// связь с тем, откуда его открыли. Длинное содержимое внутри прокручивается.
  static const double maxHeightFactor = 0.8;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      // heightFactor, чтобы обвязка не растянулась на весь экран: лист внутри
      // модалки высоту не задаёт, и без этого тап мимо него не долетел бы до
      // затемнения.
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth + inset * 2,
          maxHeight: MediaQuery.sizeOf(context).height * maxHeightFactor,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: inset),
          child: ClipRSuperellipse(
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(K.rSheet),
            ),
            child: BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: K.blurSheet,
                sigmaY: K.blurSheet,
              ),
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [K.sheetTop, K.sheetBottom],
                  ),
                  border: Border(
                    top: BorderSide(color: K.sheetBorder),
                    left: BorderSide(color: K.sheetBorder),
                    right: BorderSide(color: K.sheetBorder),
                  ),
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(K.rSheet),
                  ),
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: EdgeInsets.only(
                      top: 10,
                      left: 18,
                      right: 18,
                      bottom: 36 + MediaQuery.of(context).viewInsets.bottom,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Container(
                            width: 36,
                            height: 4,
                            decoration: BoxDecoration(
                              color: K.grabber,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            Expanded(child: Text(title, style: K.title)),
                            ?trailing,
                          ],
                        ),
                        const SizedBox(height: 18),
                        Flexible(child: SingleChildScrollView(child: child)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Мелкая подпись под блоком.
class SheetCaption extends StatelessWidget {
  const SheetCaption(this.text, {super.key, this.align = TextAlign.center});

  final String text;
  final TextAlign align;

  @override
  Widget build(BuildContext context) => Text(
    text,
    textAlign: align,
    style: const TextStyle(color: K.textDim, fontSize: 12, height: 1.4),
  );
}

/// Небольшой заголовок группы внутри длинной шторки.
class SheetSectionTitle extends StatelessWidget {
  const SheetSectionTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 10, bottom: 6),
    child: Text(text.toUpperCase(), style: K.cap.copyWith(color: K.textDim)),
  );
}

/// Круглая кнопка шага: [−] и [+].
class StepButton extends StatefulWidget {
  const StepButton({
    super.key,
    required this.plus,
    required this.enabled,
    required this.onTap,
    this.onHold,
    this.size = 46,
  });

  final bool plus;
  final bool enabled;
  final VoidCallback onTap;

  /// Шаг при удержании. Если задан, зажатая кнопка идёт им, а не [onTap]: так
  /// одиночный тап делает мелкий шаг, а удержание — крупный, и широкий диапазон
  /// проходится быстро. Не задан — удержание просто повторяет [onTap].
  final VoidCallback? onHold;
  final double size;

  @override
  State<StepButton> createState() => _StepButtonState();
}

class _StepButtonState extends State<StepButton> {
  Timer? _repeat;

  /// Сколько шагов уже сделано за это удержание. От него зависит разгон.
  int _ticks = 0;

  /// Пауза до следующего шага. Первые идут неспешно — палец должен успеть
  /// отпустить на нужном числе, — дальше отсчёт разгоняется, иначе весь
  /// диапазон приходится держать кнопку добрую минуту.
  static Duration _pause(int done) => Duration(
    milliseconds: done < 3
        ? 190
        : done < 9
        ? 110
        : done < 18
        ? 60
        : 34,
  );

  @override
  void dispose() {
    _repeat?.cancel();
    super.dispose();
  }

  void _startRepeat(LongPressStartDetails _) {
    if (!widget.enabled) return;
    _ticks = 0;
    _step();
  }

  /// Шаг удержания и заводка следующего.
  ///
  /// Обработчик берём из [widget] заново на каждом шаге, а не запоминаем при
  /// нажатии. Он замкнут на значение, с которым ряд собирали: «цель минус
  /// грамм» считается от того числа, что было на экране в тот момент.
  /// Запомненный однажды, он на каждом тике возвращал бы одно и то же —
  /// зажатый минус уводил вес на грамм вниз и там вставал.
  void _step() {
    _repeat?.cancel();
    if (!mounted || !widget.enabled) {
      _repeat = null;
      return;
    }
    (widget.onHold ?? widget.onTap)();
    // Отклик на каждый шаг, пока шаги редкие; на разгоне — через один, иначе
    // вместо отсчёта в пальце сплошная вибрация.
    if (_ticks < 9 || _ticks.isEven) HapticFeedback.selectionClick();
    _ticks++;
    _repeat = Timer(_pause(_ticks), _step);
  }

  void _stopRepeat([Object? _]) {
    _repeat?.cancel();
    _repeat = null;
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.plus ? context.t.increase : context.t.decrease;
    final visual = widget.size;
    final target = visual < 44 ? 44.0 : visual;
    return Semantics(
      button: true,
      enabled: widget.enabled,
      label: label,
      onTap: widget.enabled ? widget.onTap : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTap: widget.enabled ? widget.onTap : null,
        onLongPressStart: widget.enabled ? _startRepeat : null,
        onLongPressEnd: widget.enabled ? _stopRepeat : null,
        onLongPressCancel: widget.enabled ? _stopRepeat : null,
        child: SizedBox.square(
          dimension: target,
          child: Center(
            child: Glass(
              shape: BoxShape.circle,
              radius: visual,
              blur: K.blurButton,
              // Кнопка мелкая и лежит внутри листа: густая тень под ней читается
              // грязью, а не объёмом.
              lifted: false,
              child: SizedBox(
                width: visual,
                height: visual,
                child: Center(
                  child: KIconView(
                    widget.plus ? KIcon.plus : KIcon.minus,
                    size: visual * 0.42,
                    color: widget.enabled ? K.text : K.textDisabled,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Крупный регулятор: значение 52/300 между двумя кнопками 46.
class BigStepper extends StatelessWidget {
  const BigStepper({
    super.key,
    this.text,
    this.child,
    required this.canDown,
    required this.canUp,
    required this.onDown,
    required this.onUp,
    this.fontSize = 52,
    this.buttonSize = 46,
  }) : assert(text != null || child != null);

  final String? text;

  /// Своё содержимое вместо строки — например, время с выбором части.
  final Widget? child;
  final bool canDown;
  final bool canUp;
  final VoidCallback onDown;
  final VoidCallback onUp;
  final double fontSize;
  final double buttonSize;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      StepButton(
        plus: false,
        enabled: canDown,
        onTap: onDown,
        size: buttonSize,
      ),
      Expanded(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child:
              child ??
              Text(
                text!,
                maxLines: 1,
                style: K.bigValue.copyWith(
                  fontSize: fontSize,
                  color: K.amber,
                  shadows: [
                    const Shadow(color: Color(0x73FFB000), blurRadius: 24),
                  ],
                ),
              ),
        ),
      ),
      StepButton(plus: true, enabled: canUp, onTap: onUp, size: buttonSize),
    ],
  );
}

/// Ряд параметра: название с пояснением слева, [− значение +] справа.
class SheetStepperRow extends StatelessWidget {
  const SheetStepperRow({
    super.key,
    required this.label,
    required this.value,
    required this.canDown,
    required this.canUp,
    required this.onDown,
    required this.onUp,
    this.onDownHold,
    this.onUpHold,
    this.description,
    this.unit,
  });

  final String label;
  final String value;

  /// Зачем этот параметр нужен — строка 11 dim под названием.
  final String? description;

  /// Мелкая единица рядом с числом.
  final String? unit;
  final bool canDown;
  final bool canUp;
  final VoidCallback onDown;
  final VoidCallback onUp;

  /// Крупный шаг по удержанию. Тап идёт [onDown]/[onUp], зажатая кнопка — этими.
  final VoidCallback? onDownHold;
  final VoidCallback? onUpHold;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: K.rowTitle.copyWith(color: K.text)),
              if (description != null) ...[
                const SizedBox(height: 3),
                Text(description!, style: K.rowDesc),
              ],
            ],
          ),
        ),
        const SizedBox(width: 8),
        StepButton(
          plus: false,
          enabled: canDown,
          onTap: onDown,
          onHold: onDownHold,
          size: 38,
        ),
        // Число не должно липнуть к кнопкам: по 14 воздуха с каждой стороны,
        // иначе «70 сек» и «7 / 15» упираются в плюс.
        Container(
          // 64 под само число плюс по 14 воздуха с каждой стороны.
          width: 92,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(value, style: K.rowValue.copyWith(color: K.amber)),
                if (unit != null) ...[
                  const SizedBox(width: 2),
                  Text(
                    unit!,
                    style: TextStyle(
                      color: K.amber.withValues(alpha: 0.55),
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        StepButton(
          plus: true,
          enabled: canUp,
          onTap: onUp,
          onHold: onUpHold,
          size: 38,
        ),
      ],
    ),
  );
}

/// Ряд-карточка листа r18: значок в круге 38, название 14/500, описание 11 и
/// галочка у выбранного. Из таких рядов собраны листы режима и подключения.
class SheetTile extends StatelessWidget {
  const SheetTile({
    super.key,
    required this.title,
    required this.onTap,
    this.description,
    this.icon,
    this.iconColor = K.textMuted,
    this.accent,
    this.selected = false,
    this.trailing,
  });

  final String title;
  final String? description;

  /// Своё содержимое кружка — например, значок режима.
  final Widget? icon;
  final Color iconColor;

  /// Цвет выбранного ряда: подложка .08, обводка .55, галочка.
  final Color? accent;

  final bool selected;
  final Widget? trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final a = accent ?? K.amber;
    return KTap(
      onTap: onTap,
      scale: 0.98,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: ShapeDecoration(
          color: selected ? a.withValues(alpha: 0.08) : K.rowBg,
          shape: kSquircle(
            K.rRow,
            side: BorderSide(
              color: selected ? a.withValues(alpha: 0.55) : K.glassBorder,
            ),
          ),
        ),
        child: Row(
          children: [
            if (icon != null) ...[
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: K.rowDial,
                  shape: BoxShape.circle,
                ),
                child: icon,
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: K.rowTitle.copyWith(color: K.text),
                  ),
                  if (description != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      description!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: K.rowDesc.copyWith(
                        color: selected ? a.withValues(alpha: 0.75) : K.textDim,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            ?trailing,
            if (selected) ...[
              const SizedBox(width: 8),
              Icon(Icons.check_rounded, size: 18, color: a),
            ],
          ],
        ),
      ),
    );
  }
}

/// Пресет в ряду из трёх равных карточек.
class PresetTile extends StatelessWidget {
  const PresetTile({
    super.key,
    required this.title,
    required this.value,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String value;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => KTap(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(
        color: selected ? const Color(0x14FFB000) : const Color(0x08FFFFFF),
        borderRadius: BorderRadius.circular(K.rPreset),
        border: Border.all(
          color: selected ? K.amber.withValues(alpha: 0.7) : K.glassBorder,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: selected ? K.amber : K.text2,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: K.numbers.copyWith(
              color: selected ? K.amber : K.textMuted,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    ),
  );
}

/// Небольшой чип-кнопка: «−15 мин», «+15 мин».
class SheetChip extends StatelessWidget {
  const SheetChip({
    super.key,
    required this.label,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) => KTap(
    onTap: enabled ? onTap : null,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: K.chipBg,
        borderRadius: BorderRadius.circular(K.rChip),
        border: Border.all(color: K.amber.withValues(alpha: 0.35)),
      ),
      child: Text(label, style: K.menuChip.copyWith(color: K.amber)),
    ),
  );
}

/// Строка выбора в листе: подпись, значение справа, галочка у активного.
class SheetOption extends StatelessWidget {
  const SheetOption({
    super.key,
    required this.title,
    required this.onTap,
    this.trailing,
    this.selected = false,
    this.danger = false,
  });

  final String title;
  final VoidCallback onTap;
  final String? trailing;
  final bool selected;
  final bool danger;

  @override
  Widget build(BuildContext context) => KTap(
    onTap: onTap,
    semanticLabel: title,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 13),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: danger ? const Color(0xFFFF7052) : K.text,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (trailing != null)
            Text(
              trailing!,
              style: K.numbers.copyWith(color: K.textMuted, fontSize: 14),
            ),
          if (selected) ...[
            const SizedBox(width: 8),
            const Icon(Icons.check_rounded, size: 18, color: K.amber),
          ],
        ],
      ),
    ),
  );
}

/// Строка-переключатель в листе.
class SheetSwitch extends StatelessWidget {
  const SheetSwitch({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: onChanged == null ? K.textDisabled : K.text,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        KSwitch(value: value, onChanged: onChanged, semanticLabel: title),
      ],
    ),
  );
}
