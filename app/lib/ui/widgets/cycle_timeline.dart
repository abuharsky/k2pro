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
enum StepKind { alarm, mode, heat, pour, weight }

/// Шаг стоит в очереди фаз, а не описывает условие запуска.
///
/// Вес попадает сюда, хотя во времени он не следует за проливом, а идёт вместе
/// с ним: карточка веса — это то, чем пролив кончается, и линия между ними
/// нужна именно поэтому. Гаснет она последней — пока идёт осадка, пролив уже
/// пройден, а вес ещё доползает.
///
/// Но только когда весом действительно рубят. Весы, лежащие на столе сами по
/// себе, показывают число и в очереди фаз не стоят — у такой карточки
/// [StepMark.setting], и линия к ней не тянется.
bool _inSequence(CycleStep s) =>
    s.mark != StepMark.setting &&
    (s.kind == StepKind.heat ||
        s.kind == StepKind.pour ||
        s.kind == StepKind.weight);

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
    this.accent = false,
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

  /// Показать значение цветом шага, не дожидаясь его очереди.
  ///
  /// Обычно цвет означает «сейчас», и заранее его никто не носит. Но у веса
  /// цвет значит другое: этой цифрой пролив и кончится. Различить «весы просто
  /// показывают» и «весом рубим» надо с одного взгляда, до всякого пуска, — а
  /// кроме цвета для этого в колонке ничего нет.
  final bool accent;

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
          // Без обрезки. Пока колонка едет в новую высоту, содержимое в неё не
          // помещается, и штатная обрезка резала бы по краю бокса: свечение
          // активной карточки на эти кадры превращалось в квадрат со срезанным
          // верхом. Тени и так висят за пределами колонки — обрезать тут нечего.
          clipBehavior: Clip.none,
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
                    _inSequence(step) && _inSequence(widget.steps[i - 1])
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

/// Кольцо активного шага: серая дорожка по контуру карточки и цветная дуга
/// поверх неё — от двенадцати часов по часовой стрелке на долю пройденного.
///
/// Дугу вырезаем из самого контура ([PathMetric.extractPath]), а не рисуем
/// градиентом по кругу: у градиента концы дуги — радиальные срезы, всегда
/// прямые, а штриху можно задать круглые заглушки. Заодно граница остаётся
/// резкой при любой доле.
class _ProgressRing extends CustomPainter {
  _ProgressRing({required this.color, required this.progress});

  final Color color;
  final double progress;

  /// Цвет непрозрачен нарочно: под кольцом лежит пульсирующее свечение фазы,
  /// и полупрозрачная дорожка просто светилась бы насквозь — доля шага стала
  /// бы не видна.
  static const Color _track = Color(0xFF363A41);

  /// Откуда начинается контур, знает только сам контур, а начинать дугу надо
  /// сверху по центру. Расстояние до этой точки ищем перебором и запоминаем:
  /// размер карточки за прогон не меняется.
  static final Map<Size, double> _startCache = {};

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final shape = kSquircle(K.rCell);
    // Непрозрачная подложка под всей карточкой. Стекло шага полупрозрачно, и
    // без неё сквозь него светило бы пульсирующее свечение фазы — карточка
    // изнутри наливалась бы цветом вместо того, чтобы оставаться тёмной.
    canvas.drawPath(shape.getOuterPath(rect), Paint()..color = _track);

    final path = shape.getOuterPath(rect.deflate(_Card.ring / 2));
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _Card.ring
      ..strokeCap = StrokeCap.round
      ..color = _track;
    canvas.drawPath(path, stroke);

    final p = progress.clamp(0.0, 1.0);
    if (p <= 0) return;
    stroke.color = color;
    if (p >= 0.999) {
      canvas.drawPath(path, stroke);
      return;
    }

    final metric = path.computeMetrics().first;
    final len = metric.length;
    final start = _startCache[size] ??= _offsetOf(
      metric,
      Offset(size.width / 2, _Card.ring / 2),
    );
    final end = start + len * p;
    final arc = Path()
      ..addPath(metric.extractPath(start, end.clamp(0, len)), Offset.zero);
    // Хвост, перешедший через начало контура: вторым куском с его начала.
    if (end > len) {
      arc.addPath(metric.extractPath(0, end - len), Offset.zero);
    }
    canvas.drawPath(arc, stroke);
  }

  /// Ближайшая к [target] точка контура — в единицах длины пути.
  static double _offsetOf(PathMetric metric, Offset target) {
    const samples = 360;
    var best = 0.0;
    var bestDistance = double.infinity;
    for (var i = 0; i < samples; i++) {
      final at = metric.length * i / samples;
      final point = metric.getTangentForOffset(at)?.position;
      if (point == null) continue;
      final d = (point - target).distanceSquared;
      if (d < bestDistance) {
        bestDistance = d;
        best = at;
      }
    }
    return best;
  }

  @override
  bool shouldRepaint(_ProgressRing old) =>
      old.progress != progress || old.color != color;
}

/// Значение шага. Обычно это просто строка, но пара «сейчас → куда греем»
/// приезжает со стрелкой посередине, и стрелку мы рисуем сами: в Roboto,
/// который Flutter несёт с собой, знака U+2192 нет — в тексте он обернулся бы
/// пустым квадратом.
class _Value extends StatelessWidget {
  const _Value({
    required this.text,
    required this.style,
    required this.color,
    required this.maxLines,
  });

  final String text;
  final TextStyle style;
  final Color color;
  final int maxLines;

  static const String arrow = '\u2192';

  @override
  Widget build(BuildContext context) {
    final at = text.indexOf(arrow);
    if (at < 0) {
      return KText(
        text,
        style: style,
        color: color,
        textAlign: TextAlign.center,
        maxLines: maxLines,
      );
    }

    // Тонкие пробелы вокруг стрелки уже заложены в строку — здесь они лишние.
    final left = text.substring(0, at).trim();
    final right = text.substring(at + arrow.length).trim();
    final size = style.fontSize ?? 16;
    // Слева — живой отсчёт машины, справа — уставка. Разводим их по цвету:
    // отсчёт приглушён и обесцвечен, чтобы цвет фазы остался за целью, но
    // читался как та же строка, а не как подпись.
    final leadColor = Color.lerp(color, K.textDim, 0.5)!;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        KText(
          left,
          // Свечение — только у цели: неон на служебном числе спорил бы с ней.
          style: style.copyWith(shadows: const []),
          color: leadColor,
          maxLines: 1,
        ),
        // Воздух с обеих сторон: стрелка разделяет числа, а не липнет к ним.
        SizedBox(width: size * 0.3),
        CustomPaint(
          size: Size(size * 0.5, size * 0.44),
          painter: _ArrowGlyph(
            // Стрелка тише цифр: она служебная, читаются по-прежнему числа.
            color: leadColor.withValues(alpha: 0.6),
          ),
        ),
        SizedBox(width: size * 0.3),
        KText(right, style: style, color: color, maxLines: 1),
      ],
    );
  }
}

/// Стрелка вправо: черта с раскрытым уголком на конце.
class _ArrowGlyph extends CustomPainter {
  _ArrowGlyph({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final head = size.height * 0.42;
    final path = Path()
      ..moveTo(0, y)
      ..lineTo(size.width, y)
      ..moveTo(size.width - head, y - head)
      ..lineTo(size.width, y)
      ..lineTo(size.width - head, y + head);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.height * 0.19
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ArrowGlyph old) => old.color != color;
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
    final valueColor = active || setting || step.accent
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
          // Дышащая тень — то, чем активный шаг отличается от остальных
          // издалека: цвет и кольцо видно, только если смотреть на карточку, а
          // пульс ловится боковым зрением. Ходит и размытие, и насыщенность:
          // одно размытие на глаз почти не читается.
          shadows: active
              ? [
                  BoxShadow(
                    color: tone.glow.withValues(alpha: 0.35 + 0.45 * pulse),
                    blurRadius: 10 + 16 * pulse,
                    spreadRadius: -1 + 3 * pulse,
                  ),
                ]
              : null,
        ),
        // Долю шага ведём числом, а не декорацией. AnimatedContainer сводил бы
        // два градиента целиком, а у кольца граница цвета — жёсткий стык двух
        // стопов в одной точке: при сведении он на полсекунды расплывается в
        // растяжку, и каждый пришедший градус запускал это заново — обводка
        // моргала. Здесь же плавно едет само число, а стык остаётся резким.
        //
        // Ключ по active сбрасывает тween при смене состояния: иначе на входе
        // в шаг кольцо отматывалось бы с полного круга до начала.
        child: TweenAnimationBuilder<double>(
          key: ValueKey(active),
          tween: Tween<double>(end: step.progress ?? 1),
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOut,
          builder: (context, value, child) => CustomPaint(
            // Кольцо есть только у активного шага: это единственное место в
            // колонке, где вообще нужна обводка. У остальных её нет — шесть
            // обведённых плашек забивали собой всю картинку.
            painter: active
                ? _ProgressRing(color: tone.color, progress: value)
                : null,
            child: SizedBox(
              width: CycleTimeline.cardWidth,
              child: Padding(padding: const EdgeInsets.all(ring), child: child),
            ),
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
                      child: _Value(
                        text: step.value,
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
}
