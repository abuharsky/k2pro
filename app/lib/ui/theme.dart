import 'dart:ui';

import 'package:flutter/material.dart';

import '../ble/protocol.dart';
import '../model/brew_phase.dart';

/// Дизайн-токены. Значения — из спецификации: цвета заданы там в rgba, здесь
/// они переведены в ARGB (альфа = round(a * 255)).
abstract final class K {
  // ---- фон ----
  static const bgTop = Color(0xFF0C1016);
  static const bgMid = Color(0xFF07090C);
  static const bgBottom = Color(0xFF05070A);

  /// Тёмный низ фона: им же подкрашиваются обводки точек-индикаторов.
  static const bg0 = bgBottom;

  // ---- текст ----
  static const text = Color(0xFFE8EAEE); // textPrimary
  static const textBright = Color(0xFFF2F4F7); // значения
  static const text2 = Color(0xFFC6CAD1); // textSecondary
  static const textMuted = Color(0xFFA0A7B1);
  static const textDim = Color(0xFF89929E);
  static const textDim2 = Color(0xFF929AA5);
  static const textDisabled = Color(0xFF69727D);

  /// Совместимость со старыми вызовами: «третий» уровень текста.
  static const text3 = textDim;

  /// Значки в покое.
  static const icon = Color(0xFFB7BDC6);
  static const iconDim = Color(0xFF6B7280);

  // ---- стекло ----
  /// Ячейки и круглые кнопки: rgba(255,255,255,.08) → rgba(255,255,255,.02), 135°.
  static const glassA = [Color(0x14FFFFFF), Color(0x05FFFFFF)];

  /// Тот же градиент чуть слабее — для крупных поверхностей.
  static const glassB = [Color(0x12FFFFFF), Color(0x06FFFFFF)];

  /// rgba(255,255,255,.14).
  static const glassBorder = Color(0x24FFFFFF);

  /// Верхний внутренний блик — inset 0 1px 0 rgba(255,255,255,.08).
  static const glassHighlight = Color(0x14FFFFFF);

  /// Плоская заливка стекла там, где градиент не нужен (поля ввода, факты).
  static const glassFill = Color(0x0DFFFFFF); // .05
  static const glassStroke = Color(0x17FFFFFF); // .09
  static const hairline = Color(0x17FFFFFF);

  /// Тёмная подложка чипов и кружков — rgba(20,24,31,.85).
  static const chipBg = Color(0xD914181F);

  // ---- листы ----
  /// Лист — стекло, а не тёмная плашка: сквозь него видно размытый экран.
  /// Плотность выбрана так, чтобы текст оставался читаемым поверх машины.
  static const sheetTop = Color(0xC4181C24); // rgba(24,28,36,.77)
  static const sheetBottom = Color(0xDB0E1117); // rgba(14,17,23,.86)
  static const sheetBorder = Color(0x1FFFFFFF); // .12
  static const overlay = Color(0x8C000000); // .55

  /// Затемнение под диалогом весов. Слабее обычного нарочно: под ним машина, и
  /// сквозь стекло должно быть что видеть — иначе размытие незаметно.
  static const overlayLight = Color(0x59000000); // .35

  /// Подложка диалога весов: легче листовой. Лист закрывает нижнюю треть, где
  /// смотреть особо не на что, а диалог висит посреди картинки.
  static const dialogTop = Color(0x9E181C24); // rgba(24,28,36,.62)
  static const dialogBottom = Color(0xB80E1117); // rgba(14,17,23,.72)
  static const grabber = Color(0x38FFFFFF); // .22

  /// Подложка ряда в листе — rgba(255,255,255,.05).
  static const rowBg = Color(0x0DFFFFFF);

  /// Кружок значка в ряду листа — rgba(255,255,255,.06).
  static const rowDial = Color(0x0FFFFFFF);

  // ---- акценты ----
  static const success = Color(0xFF5EC26A);
  static const btBlue = Color(0xFF4DA3FF);

  /// Янтарь: таймер, значения в листах, экстракция.
  static const amber = Color(0xFFFFB000);
  static const accent = amber;

  /// Вода: тот же синий, что и связь.
  static const water = btBlue;

  static const danger = Color(0xFFD63B2F);

  static const stopGrad = [Color(0xFFFF7052), Color(0xFFD63B2F)];
  static const doneGrad = [Color(0xFF59C26A), Color(0xFF3DA452)];
  static const progressGrad = [Color(0xFFFFC63F), Color(0xFFFF9F00)];

  /// Текст на кнопках «Стоп» и «Готово».
  static const stopText = Color(0xFFFFF4F1);
  static const doneText = Color(0xFF0D2413);

  // ---- геометрия ----
  /// Ячейки, карточки таймлайна и главная кнопка — r16, внутренняя часть r15.
  static const rCell = 16.0;
  static const rInner = 15.0;
  static const rCta = 16.0;
  static const rCard = 16.0;
  static const rSheet = 30.0;

  /// Ряды в листах.
  static const rRow = 18.0;
  static const rPreset = 16.0;

  /// Чипы и главная кнопка — «таблетки».
  static const rChip = 999.0;
  static const rPill = 999.0;

  static const blurCell = 16.0;

  /// Размытие листа. 30 давало заметную просадку на открытии — вся площадь
  /// экрана пересчитывается каждый кадр выезда; 24 визуально то же самое.
  static const blurSheet = 24.0;

  /// Размытие всего экрана под модальным прибором. Совсем слабое: машина
  /// должна остаться узнаваемой — человек не ушёл с экрана, он открыл над ним
  /// прибор. На тройке силуэт ещё читается, на семёрке от него остаётся пятно.
  static const blurBackdrop = 3.0;

  /// Совместимость: раньше размытие звалось по месту применения.
  static const blurButton = blurCell;
  static const blurChip = blurCell;

  // ---- типографика ----
  /// Заголовки листов и имя машины.
  static const title = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.3,
    color: text,
  );

  /// Микро-подпись капсом: ТАЙМЕР, НАГРЕВ, ЭКСТРАКЦИЯ…
  static const cap = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.3,
    height: 1.1,
  );

  /// Значение в карточке таймлайна.
  static const stepValue = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1,
    letterSpacing: -0.2,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  /// Значение в ячейке нижнего ряда.
  static const cellValue = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    height: 1,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  /// Крупное значение листа: 52 — температура, 44 — время таймера.
  static const bigValue = TextStyle(
    fontSize: 52,
    fontWeight: FontWeight.w300,
    height: 1,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static const ctaLabel = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.3,
  );

  /// Название ряда в листе.
  static const rowTitle = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1.2,
  );

  /// Пояснение под названием ряда.
  static const rowDesc = TextStyle(fontSize: 12, height: 1.25, color: textDim);

  /// Значение в ряду-степпере.
  static const rowValue = TextStyle(
    fontSize: 19,
    fontWeight: FontWeight.w500,
    height: 1,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static const menuChip = TextStyle(fontSize: 11, fontWeight: FontWeight.w600);

  static const caption = TextStyle(fontSize: 11, height: 1.2);

  static const statValue = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w500,
    height: 1,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  /// Табличные цифры для любого места, где число меняется на месте.
  static const numbers = TextStyle(
    fontFeatures: [FontFeature.tabularFigures()],
    height: 1,
  );

  static ThemeData theme() {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: bgBottom,
      colorScheme: base.colorScheme.copyWith(
        primary: amber,
        surface: bgTop,
        error: danger,
      ),
      textTheme: base.textTheme.apply(bodyColor: text, displayColor: text),
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
    );
  }
}

/// Цвет фазы: им красится карточка таймлайна, кольцо прогресса и его свечение.
class PhaseTone {
  const PhaseTone(this.color, this.glow);

  final Color color;

  /// Пульсирующее свечение вокруг кольца — тот же цвет с альфой .45.
  final Color glow;

  static const heat = PhaseTone(Color(0xFFFF9E70), Color(0x73F06A2E));
  static const water = PhaseTone(Color(0xFF7CBBFF), Color(0x734DA3FF));
  static const amber = PhaseTone(Color(0xFFFFB000), Color(0x73FFB000));
  static const done = PhaseTone(K.success, Color(0x735EC26A));

  /// Выключенный таймер: карточка на месте, но гореть ей нечем.
  static const muted = PhaseTone(K.textMuted, Color(0x00000000));
  static const error = PhaseTone(Color(0xFFFF7052), Color(0x73FF7052));

  static PhaseTone of(BrewPhase phase) => switch (phase) {
    BrewPhase.heating => heat,
    BrewPhase.preInfusion || BrewPhase.standstill => water,
    BrewPhase.extraction => amber,
    BrewPhase.done => done,
    BrewPhase.error => error,
    BrewPhase.idle => water,
  };
}

/// Акцент режима. Красит всё, что относится к запуску: кнопку пуска и ячейку
/// режима в нижнем ряду.
enum ModeStyle {
  heat(
    Color(0xFFFF9E6B),
    Color(0xFFF06A2E),
    Color(0x66F06A2E),
    Color(0xFF2A1206),
    Color(0xFFFF9E70),
  ),
  both(
    Color(0xFFFFC63F),
    Color(0xFFFF9F00),
    Color(0x66FF9F00),
    Color(0xFF1A1205),
    Color(0xFFFFB000),
  ),
  water(
    Color(0xFF5FB0FF),
    Color(0xFF2276E0),
    Color(0x663482E6),
    Color(0xFF071527),
    Color(0xFF7CBBFF),
  );

  const ModeStyle(this.from, this.to, this.glow, this.onColor, this.light);

  /// Верх и низ градиента кнопки (180°).
  final Color from;
  final Color to;

  /// Свечение вокруг кнопки.
  final Color glow;

  /// Тёмный текст и значок на залитой кнопке.
  final Color onColor;

  /// Светлый акцент: контуры, значки на стекле, текст чипов.
  final Color light;

  List<Color> get gradient => [from, to];

  /// Тон карточки режима: светлый акцент и его же свечение.
  PhaseTone get tone => PhaseTone(light, glow);

  static ModeStyle of(WorkMode mode) => switch (mode) {
    WorkMode.heat => ModeStyle.heat,
    WorkMode.heatAndBrew => ModeStyle.both,
    WorkMode.brew => ModeStyle.water,
  };
}

/// Скругление в духе iOS: суперэллипс, а не дуга окружности.
///
/// Обычный радиус ломает контур в двух точках — глаз ловит стык прямой и дуги,
/// и угол выглядит «надутым». Суперэллипс переходит в прямую плавно, поэтому
/// им скруглено всё: ячейки, карточки, ряды листов и сами листы.
ShapeBorder kSquircle(double radius, {BorderSide side = BorderSide.none}) =>
    RoundedSuperellipseBorder(
      borderRadius: BorderRadius.circular(radius),
      side: side,
    );

/// Фон приложения: вертикальный градиент плюс цветные пятна.
///
/// Чистый чёрный под стеклом выглядит дёшево — размывать нечего, и панели
/// читаются как серые прямоугольники. Пятна дают стеклу что подхватывать:
/// тёплое кофейное сверху справа, синее снизу слева и янтарное за кнопкой
/// пуска. Все они на грани заметности — это воздух, а не декор.
class AppBackground extends StatelessWidget {
  const AppBackground({super.key, required this.child, this.tint});

  final Widget child;

  /// Цвет текущей фазы: им чуть подкрашиваются пятна, пока машина работает.
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final t = tint;
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [K.bgTop, K.bgMid, K.bgBottom],
              stops: [0, 0.5, 1],
            ),
          ),
        ),
        _Blob(
          center: const Alignment(0.95, -0.85),
          radius: 0.95,
          color: t == null
              ? const Color(0x38B2723C) // кофе
              : Color.lerp(
                  const Color(0x1FB2723C),
                  t.withValues(alpha: 0.16),
                  0.6,
                )!,
        ),
        const _Blob(
          center: Alignment(-0.95, 0.3),
          radius: 0.95,
          color: Color(0x2E4DA3FF),
        ),
        _Blob(
          center: const Alignment(0.1, 1.05),
          radius: 0.75,
          color: t?.withValues(alpha: 0.20) ?? const Color(0x26FFB000),
        ),
        const _Blob(
          center: Alignment(-0.6, -1),
          radius: 0.65,
          color: Color(0x1A6E5A8C),
        ),
        // Виньетка собирает взгляд к центру и глушит углы, где пятна
        // подходят к самому краю.
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              radius: 1,
              colors: [Color(0x00000000), Color(0x40000000)],
              stops: [0.6, 1],
            ),
          ),
        ),
        child,
      ],
    );
  }
}

/// Мягкое цветное пятно во весь экран.
class _Blob extends StatelessWidget {
  const _Blob({
    required this.center,
    required this.radius,
    required this.color,
  });

  final Alignment center;
  final double radius;
  final Color color;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: center,
          radius: radius,
          colors: [color, color.withValues(alpha: 0)],
        ),
      ),
    ),
  );
}

/// Какой из двух стеклянных градиентов взять.
enum GlassTone { button, panel }

/// Стеклянная поверхность.
///
/// Стекло здесь — не просто размытие с обводкой: у него есть форма. Обводка
/// сделана градиентным кольцом (сверху слева ярче, снизу справа почти нет) —
/// так кромка ловит свет; поверх заливки лежит косой блик, снизу — слабый
/// отсвет отражённого света, а под всем этим мягкая тень. Из этих четырёх
/// вещей и получается выпуклость: плоский border + blur её не дают.
class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.radius = K.rCell,
    this.blur = K.blurCell,
    this.tone = GlassTone.button,
    this.border,
    this.padding,
    this.shadow,
    this.shape = BoxShape.rectangle,
    this.highlight = true,
    this.lifted = true,
    this.fill,
  });

  final Widget child;
  final double radius;
  final double blur;
  final GlassTone tone;

  /// Свой цвет кромки вместо нейтрального стекла — акцент режима, янтарь
  /// таймера. Кольцо остаётся градиентным, меняется только его цвет.
  final Color? border;

  final EdgeInsetsGeometry? padding;

  /// Своя тень или свечение поверх собственной тени стекла.
  final List<BoxShadow>? shadow;

  final BoxShape shape;

  /// Косой блик и нижний отсвет. Выключается там, где стекло совсем мелкое.
  final bool highlight;

  /// Насколько высоко стекло висит над фоном. Мелкие кнопки внутри листа
  /// висят низко: густая тень под ними читается как грязь, а не как объём.
  final bool lifted;

  /// Плоская заливка вместо стеклянного градиента.
  final Color? fill;

  @override
  Widget build(BuildContext context) {
    final circle = shape == BoxShape.circle;
    final form = circle ? const CircleBorder() : kSquircle(radius);
    final colors = tone == GlassTone.panel ? K.glassB : K.glassA;
    final accent = border;

    // Кромка: ярче всего сверху слева, к нижнему правому углу почти гаснет.
    final ring = LinearGradient(
      begin: circle ? Alignment.topLeft : Alignment.topCenter,
      end: circle ? Alignment.bottomRight : Alignment.bottomCenter,
      colors: accent == null
          ? const [Color(0x4DFFFFFF), Color(0x1FFFFFFF), Color(0x0FFFFFFF)]
          : [
              accent.withValues(alpha: 0.85),
              accent.withValues(alpha: 0.45),
              accent.withValues(alpha: 0.18),
            ],
      stops: const [0, 0.55, 1],
    );

    Widget surface = Stack(
      fit: StackFit.passthrough,
      children: [
        DecoratedBox(
          decoration: ShapeDecoration(
            shape: form,
            gradient: fill != null
                ? null
                : LinearGradient(
                    // Свет падает сверху. Диагональ, заданная спецификацией
                    // для квадратных ячеек, на широкой кнопке читается не
                    // стеклом, а градиентной заливкой: слева светло, справа
                    // темно. На круге диагональ оставлена — там она и лепит
                    // объём.
                    begin: circle ? Alignment.topLeft : Alignment.topCenter,
                    end: circle
                        ? Alignment.bottomRight
                        : Alignment.bottomCenter,
                    colors: colors,
                  ),
            color: fill,
          ),
          child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
        ),
        if (highlight)
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: ShapeDecoration(
                  shape: form,
                  gradient: circle
                      ? const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomCenter,
                          colors: [
                            Color(0x24FFFFFF),
                            Color(0x0AFFFFFF),
                            Color(0x00FFFFFF),
                            Color(0x12FFFFFF),
                          ],
                          stops: [0, 0.35, 0.62, 1],
                        )
                      : const LinearGradient(
                          // Светлая кромка сверху, провал в середине и слабый
                          // отсвет снизу — так выглядит выпуклое стекло на
                          // плоском фоне. Света здесь меньше, чем на круге:
                          // широкая поверхность набирает его всей площадью и
                          // на тёмном листе быстро становится молочной.
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Color(0x17FFFFFF),
                            Color(0x08FFFFFF),
                            Color(0x00FFFFFF),
                            Color(0x0DFFFFFF),
                          ],
                          stops: [0, 0.32, 0.7, 1],
                        ),
                ),
              ),
            ),
          ),
      ],
    );

    // Размытие нулевой силы — не бесплатная операция: BackdropFilter всё
    // равно заводит слой. Внутри листа размывать нечего (лист сам уже
    // размытие), поэтому там стекло обходится без него.
    if (blur > 0) {
      surface = BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: surface,
      );
    }
    surface = circle
        ? ClipOval(child: surface)
        : ClipRSuperellipse(
            borderRadius: BorderRadius.circular(radius),
            child: surface,
          );

    // Кромка — именно обводка по контуру, а не подложка под стеклом. Раньше
    // она была контейнером с градиентом, и сквозь полупрозрачное стекло этот
    // градиент просвечивал всей площадью: поверхность выходила молочной.
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: form,
        shadows: [
          if (lifted)
            const BoxShadow(
              color: Color(0x40000000),
              blurRadius: 12,
              offset: Offset(0, 4),
            )
          else
            const BoxShadow(
              color: Color(0x1F000000),
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
          ...?shadow,
        ],
      ),
      child: CustomPaint(
        foregroundPainter: _Rim(shape: form, gradient: ring),
        child: surface,
      ),
    );
  }
}

/// Светящаяся кромка стекла: штрих в один пиксель по контуру фигуры.
class _Rim extends CustomPainter {
  _Rim({required this.shape, required this.gradient});

  final ShapeBorder shape;
  final Gradient gradient;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawPath(
      shape.getOuterPath(rect.deflate(0.5)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = gradient.createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_Rim o) => o.shape != shape || o.gradient != gradient;
}

/// Текст с плавной сменой цвета.
///
/// AnimatedDefaultTextStyle тут не годится: он подменяет DefaultTextStyle
/// целиком, и текст теряет семейство шрифта, которое пришло из темы.
class KText extends StatelessWidget {
  const KText(
    this.data, {
    super.key,
    required this.style,
    required this.color,
    this.textAlign,
    this.maxLines,
    this.overflow,
    this.duration = const Duration(milliseconds: 500),
  });

  final String data;
  final TextStyle style;
  final Color color;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;
  final Duration duration;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<Color?>(
    tween: ColorTween(end: color),
    duration: duration,
    curve: Curves.easeOutCubic,
    builder: (context, value, _) => Text(
      data,
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
      style: style.copyWith(color: value ?? color),
    ),
  );
}

/// Короткое нажатие с лёгким уменьшением: без материаловских разводов.
class KTap extends StatefulWidget {
  const KTap({
    super.key,
    required this.child,
    required this.onTap,
    this.scale = 0.94,
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double scale;
  final String? semanticLabel;

  @override
  State<KTap> createState() => _KTapState();
}

class _KTapState extends State<KTap> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final gesture = GestureDetector(
      onTapDown: enabled ? (_) => setState(() => _down = true) : null,
      onTapCancel: enabled ? () => setState(() => _down = false) : null,
      onTapUp: enabled ? (_) => setState(() => _down = false) : null,
      onTap: widget.onTap,
      excludeFromSemantics: true,
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticLabel,
      onTap: widget.onTap,
      child: widget.semanticLabel == null
          ? gesture
          : ExcludeSemantics(child: gesture),
    );
  }
}

/// iOS-переключатель 50×30. Включённый — градиент режима «нагрев + пролив».
class KSwitch extends StatelessWidget {
  const KSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.semanticLabel,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final on = onChanged != null;
    return Semantics(
      toggled: value,
      enabled: on,
      label: semanticLabel,
      onTap: on ? () => onChanged!(!value) : null,
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: on ? () => onChanged!(!value) : null,
          excludeFromSemantics: true,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            width: 50,
            height: 30,
            padding: const EdgeInsets.all(2),
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            decoration: BoxDecoration(
              gradient: value
                  ? LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: ModeStyle.both.gradient,
                    )
                  : null,
              color: value ? null : const Color(0x1FFFFFFF),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: value ? Colors.transparent : K.glassBorder,
              ),
            ),
            child: Container(
              width: 26,
              height: 26,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Color(0x40000000),
                    blurRadius: 4,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Стеклянный диалог: Material AlertDialog приносит свой фон, отступы и
/// типографику — три вещи, которые здесь везде заданы иначе.
Future<T?> showGlassDialog<T>(
  BuildContext context, {
  required String title,
  String? message,
  Widget? content,
  required List<Widget> actions,
}) {
  return showDialog<T>(
    context: context,
    barrierColor: K.overlay,
    builder: (ctx) => Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Material(
          type: MaterialType.transparency,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(K.rSheet),
            child: BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: K.blurSheet,
                sigmaY: K.blurSheet,
              ),
              child: Container(
                padding: const EdgeInsets.fromLTRB(22, 20, 22, 14),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [K.sheetTop, K.sheetBottom],
                  ),
                  borderRadius: BorderRadius.circular(K.rSheet),
                  border: Border.all(color: K.sheetBorder),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(title, style: K.title),
                    if (message != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        message,
                        style: const TextStyle(
                          color: K.text2,
                          fontSize: 14,
                          height: 1.35,
                        ),
                      ),
                    ],
                    if (content != null) ...[
                      const SizedBox(height: 16),
                      content,
                    ],
                    const SizedBox(height: 18),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        for (final (i, a) in actions.indexed) ...[
                          if (i > 0) const SizedBox(width: 6),
                          a,
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Кнопка диалога: без заливки, без ряби, только текст.
class KDialogButton extends StatelessWidget {
  const KDialogButton({
    super.key,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) => KTap(
    onTap: onTap,
    semanticLabel: label,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Text(
        label,
        style: TextStyle(
          color: danger ? const Color(0xFFFF7052) : K.amber,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );
}
