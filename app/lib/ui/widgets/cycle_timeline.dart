import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme.dart';
import 'k_icons.dart';

/// Из чего складывается колонка.
///
/// Первые две карточки — не шаги цикла, а его условия: когда запускать и чем.
/// Дальше идут сами шаги, и их набор зависит от режима. Пролив — один шаг:
/// смачивание, пауза и экстракция живут внутри него и по очереди показываются
/// на самой карточке, пока он идёт. Три отдельные плашки под одну настройку
/// только загромождали колонку.
enum StepKind { alarm, mode, heat, pour }

/// Шаг стоит в очереди фаз, а не описывает условие запуска.
bool _inSequence(StepKind kind) =>
    kind == StepKind.heat || kind == StepKind.pour;

/// Как шаг выглядит прямо сейчас.
///
/// [setting] — карточка-условие (режим, выключенный таймер): она не стоит в
/// очереди фаз, поэтому не бывает ни пройденной, ни активной.
enum StepMark { setting, upcoming, active, passed, error }

/// Готовый к отрисовке шаг. Собирается на домашнем экране: таймлайн ничего не
/// знает ни про BLE, ни про рецепт.
class CycleStep {
  const CycleStep({
    required this.kind,
    required this.label,
    required this.icon,
    required this.tone,
    required this.mark,
    required this.value,
    this.progress,
    this.onTap,
  });

  final StepKind kind;

  /// Подпись капсом над значением: ТАЙМЕР, НАГРЕВ, ЭКСТРАКЦИЯ…
  final String label;

  /// Значок шага. Сама карточка его не рисует — подпись справляется без него,
  /// — но шаг остаётся полным описанием: значок нужен листам и часам.
  final KIcon icon;

  /// Цвет фазы: им светится активная карточка и её кольцо.
  final PhaseTone tone;

  final StepMark mark;

  /// Число под подписью: уставка в покое, живое значение в работе.
  final String value;

  /// 0..1 — сколько шага пройдено. null — прогресса нет, кольцо ровное.
  final double? progress;

  /// Открыть настройку шага. null — сейчас не редактируется.
  final VoidCallback? onTap;
}

/// Вертикальный таймлайн цикла: колонка живых карточек-настроек слева от
/// машины.
///
/// Он же и настройки: тап по карточке открывает её лист. Пока машина работает,
/// карточки показывают живые значения и не нажимаются — уставки на ходу
/// менять нельзя.
class CycleTimeline extends StatefulWidget {
  const CycleTimeline({super.key, required this.steps, required this.running});

  final List<CycleStep> steps;

  /// Цикл идёт — кольцо активной карточки пульсирует.
  final bool running;

  /// Чуть шире прежнего: «36/92°C» и подсказка по ошибке должны читаться,
  /// а не ужиматься до нечитаемого кегля.
  static const double width = 120;
  static const double cardWidth = 112;

  @override
  State<CycleTimeline> createState() => _CycleTimelineState();
}

class _CycleTimelineState extends State<CycleTimeline>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    // Каждая карточка размывает фон под собой. Поодиночке это четыре
    // отдельных прохода по одной и той же картинке; BackdropGroup считает их
    // за один — штатный способ не платить за стекло четырежды.
    return SizedBox(
      width: CycleTimeline.width,
      child: BackdropGroup(
        child: AnimatedSize(
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          alignment: Alignment.centerLeft,
          child: AnimatedBuilder(
            animation: _pulse,
            builder: (context, _) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (i, step) in widget.steps.indexed) ...[
                  // Линия связывает только то, что действительно идёт друг за
                  // другом во времени. Таймер и режим — условия запуска, они
                  // просто стоят выше, отделённые воздухом.
                  if (i > 0)
                    _inSequence(step.kind) &&
                            _inSequence(widget.steps[i - 1].kind)
                        ? _Connector(mark: step.mark)
                        : const SizedBox(height: 9),
                  _Card(
                    key: ValueKey(step.kind),
                    step: step,
                    pulse: widget.running || step.mark == StepMark.error
                        ? disableAnimations
                              ? 0
                              : _pulse.value
                        : 0,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Отрезок между карточками: 1.5×16 по центру колонки карточек.
class _Connector extends StatelessWidget {
  const _Connector({required this.mark});

  final StepMark mark;

  @override
  Widget build(BuildContext context) {
    final reached = mark == StepMark.active || mark == StepMark.passed;
    return Padding(
      padding: const EdgeInsets.only(left: CycleTimeline.cardWidth / 2 - 0.5),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 500),
        width: 1,
        height: 14,
        color: reached ? const Color(0x3DFFFFFF) : const Color(0x14FFFFFF),
      ),
    );
  }
}

/// Карточка шага: кольцо-обводка снаружи, стеклянная плашка внутри.
class _Card extends StatelessWidget {
  const _Card({super.key, required this.step, required this.pulse});

  final CycleStep step;

  /// 0..1 — фаза пульсации свечения активного шага.
  final double pulse;

  /// Толщина кольца-обводки.
  static const double ring = 1.5;

  @override
  Widget build(BuildContext context) {
    final failed = step.mark == StepMark.error;
    final active = step.mark == StepMark.active || failed;
    final passed = step.mark == StepMark.passed;
    final tone = failed ? PhaseTone.error : step.tone;
    // Карточка-условие (режим, выключенный таймер) стоит вне очереди фаз.
    final setting = step.mark == StepMark.setting;
    final multilineValue = step.value.contains('\n');

    // Яркость показывает не «включено/выключено», а место шага во времени:
    // впереди — белым, сейчас — цветом фазы, позади — приглушённо. Серым
    // остаётся только то, чего действительно не будет: выключенный таймер.
    final capColor = active
        ? tone.color
        : passed
        ? K.textDisabled
        : K.textDim;
    final valueColor = active || setting
        ? tone.color
        : passed
        ? K.textMuted
        : K.textBright;

    return KTap(
      onTap: step.onTap,
      scale: 0.97,
      child: DecoratedBox(
        // Свечение живёт отдельным слоем: оно пульсирует каждый кадр, и внутри
        // AnimatedContainer каждый кадр перезапускало бы анимацию кольца.
        decoration: ShapeDecoration(
          shape: kSquircle(K.rCell),
          shadows: active
              ? [BoxShadow(color: tone.glow, blurRadius: 8 + 10 * pulse)]
              : null,
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOutCubic,
          width: CycleTimeline.cardWidth,
          padding: const EdgeInsets.all(ring),
          decoration: ShapeDecoration(
            shape: kSquircle(K.rCell),
            // Кольцо есть только у активного шага: это единственное место в
            // колонке, где вообще нужна обводка. У остальных её нет — шесть
            // обведённых плашек забивали собой всю картинку.
            gradient: active ? _ringGradient(tone.color, step.progress) : null,
          ),
          child: ClipRSuperellipse(
            borderRadius: BorderRadius.circular(K.rInner),
            child: BackdropFilter.grouped(
              filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeOutCubic,
                width: double.infinity,
                constraints: BoxConstraints(minHeight: active ? 64 : 58),
                padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
                decoration: ShapeDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: active
                        ? const [Color(0x2E10141B), Color(0xB3080B10)]
                        : const [Color(0x1FFFFFFF), Color(0x0AFFFFFF)],
                  ),
                  shape: kSquircle(
                    K.rInner,
                    side: active
                        ? BorderSide.none
                        : const BorderSide(color: Color(0x14FFFFFF)),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Значка в карточке нет. Их было четыре — по одному на
                    // шаг, — и на одиннадцати пикселях каждый читался пятном,
                    // а не рисунком. Слово «ТАЙМЕР» объясняет шаг лучше любого
                    // будильника такого размера, а фазу и без того держит цвет.
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: KText(
                        step.label,
                        style: K.cap,
                        color: capColor,
                        maxLines: 1,
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 6),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: KText(
                        step.value,
                        style: K.stepValue.copyWith(
                          fontSize: active
                              ? 18
                              : multilineValue
                              ? 15
                              : 16,
                          height: multilineValue ? 1.05 : null,
                          // Активное значение светится своим цветом: цифра на
                          // тёмном стекле должна быть неоном, а не просто
                          // цветным текстом.
                          shadows: active
                              ? [
                                  Shadow(
                                    color: tone.color.withValues(alpha: 0.5),
                                    blurRadius: 12,
                                  ),
                                ]
                              : null,
                        ),
                        color: valueColor,
                        textAlign: TextAlign.center,
                        maxLines: multilineValue ? 2 : 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Кольцо: цвет идёт от двенадцати часов до доли шага, дальше — обычная
  /// обводка. Без доли кольцо ровное.
  ///
  /// Цвета непрозрачны нарочно: под кольцом лежит пульсирующее свечение фазы,
  /// и полупрозрачная обводка просто светилась бы насквозь — доля шага стала
  /// бы не видна.
  static Gradient _ringGradient(Color color, double? progress) {
    final p = (progress ?? 1).clamp(0.0, 1.0);
    const rest = Color(0xFF363A41); // rgba(255,255,255,.14) поверх #151A22
    return SweepGradient(
      startAngle: 0,
      endAngle: 2 * math.pi,
      transform: const GradientRotation(-math.pi / 2),
      colors: [color, color, rest, rest],
      stops: [0, p, p, 1],
    );
  }
}
