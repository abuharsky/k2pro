import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../ble/k2_device.dart';
import '../ble/scale/scale_device.dart';
import '../l10n/app_l10n.dart';
import '../l10n/l10n_ext.dart';
import '../model/brew_advice.dart';
import '../store/prefs.dart';
import '../store/recipe_editor.dart';
import 'sheets/sheet.dart';
import 'theme.dart';
import 'widgets/k_icons.dart';
import 'widgets/round_button.dart';

/// Полноэкранный разбор чашки. Отметил вкус и тело — экран объясняет, почему так
/// вышло, и даёт рычаги по убыванию силы: помол и доза (их крутят руками на
/// кофемолке), выход по весам, и лишь в крайнем случае — температуру, которую
/// тут же можно поправить. Слабые рычаги (пролив, пред-смачивание) не
/// показываем вовсе: на этой машине они вкус почти не двигают.
Future<void> openBrewAdvice(
  BuildContext context, {
  required RecipeEditor editor,
  required K2Device device,
  required ScaleDevice scale,
  required Prefs prefs,
}) => Navigator.of(context).push<void>(
  MaterialPageRoute(
    builder: (_) => BrewAdvicePage(
      editor: editor,
      device: device,
      scale: scale,
      prefs: prefs,
    ),
  ),
);

/// Пояснения на этом экране читают целиком, а не проглядывают краем глаза: это
/// не подпись под ручкой, а абзац, который объясняет, почему чашка вышла такой.
/// Отсюда и размер — заметно крупнее `K.rowDesc` из листов, и воздух между
/// строк.
const _prose = TextStyle(fontSize: 15, height: 1.45, color: K.text2);

class BrewAdvicePage extends StatefulWidget {
  const BrewAdvicePage({
    super.key,
    required this.editor,
    required this.device,
    required this.scale,
    required this.prefs,
  });

  final RecipeEditor editor;
  final K2Device device;
  final ScaleDevice scale;
  final Prefs prefs;

  @override
  State<BrewAdvicePage> createState() => _BrewAdvicePageState();
}

class _BrewAdvicePageState extends State<BrewAdvicePage> {
  Taste? _taste;
  BrewBody? _body;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final safe = MediaQuery.paddingOf(context);

    return Scaffold(
      body: AppBackground(
        child: Column(
          children: [
            SizedBox(height: math.max(safe.top, 20) + 4),
            _Header(title: t.brewAdvice),
            Expanded(
              child: ListenableBuilder(
                listenable: Listenable.merge([
                  widget.editor,
                  widget.device,
                  widget.scale,
                ]),
                builder: (context, _) {
                  final hasScale = widget.scale.isConnected;
                  final recs = adviceFor(
                    taste: _taste,
                    body: _body,
                    hasScale: hasScale,
                  );
                  return ListView(
                    padding: EdgeInsets.fromLTRB(
                      18,
                      6,
                      18,
                      math.max(safe.bottom, 12) + 24,
                    ),
                    children: [
                      SheetSectionTitle(t.adviceTasteTitle),
                      _ChoiceRow(
                        children: [
                          for (final taste in Taste.values)
                            _Choice(
                              label: _tasteLabel(t, taste),
                              selected: _taste == taste,
                              onTap: () => setState(
                                () => _taste = _taste == taste ? null : taste,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SheetSectionTitle(t.adviceBodyTitle),
                      _ChoiceRow(
                        children: [
                          for (final body in BrewBody.values)
                            _Choice(
                              label: _bodyLabel(t, body),
                              selected: _body == body,
                              onTap: () => setState(
                                () => _body = _body == body ? null : body,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      ..._solution(t, recs, hasScale),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _solution(AppL10n t, List<Rec> recs, bool hasScale) {
    if (_taste == null && _body == null) {
      return [Text(t.advicePick, style: _prose.copyWith(color: K.textDim))];
    }
    return [
      _Diagnosis(taste: _taste, body: _body),
      const SizedBox(height: 16),
      if (recs.isEmpty)
        Text(t.adviceNoChange, style: _prose.copyWith(color: K.textDim))
      else ...[
        SheetSectionTitle(t.adviceControls),
        for (final rec in recs)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: rec.fix.lever == Lever.temperature
                ? _TempCard(
                    up: rec.fix == Fix.tempUp,
                    tier: rec.tier,
                    device: widget.device,
                    editor: widget.editor,
                    fahrenheit: widget.prefs.fahrenheit,
                  )
                : _FixCard(fix: rec.fix, tier: rec.tier),
          ),
      ],
      // Выход — сильный рычаг, но без весов его не задать точно. Не молчим о
      // нём, а зовём подключить весы.
      if (wantsScale(taste: _taste, body: _body, hasScale: hasScale)) ...[
        const SizedBox(height: 10),
        Row(
          children: [
            const KIconView(KIcon.scale, size: 17, color: K.textMuted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                t.adviceScaleOff,
                style: _prose.copyWith(fontSize: 13.5, color: K.textMuted),
              ),
            ),
          ],
        ),
      ],
    ];
  }
}

String _tasteLabel(AppL10n t, Taste taste) => switch (taste) {
  Taste.sour => t.tasteSour,
  Taste.salty => t.tasteSalty,
  Taste.empty => t.tasteEmpty,
  Taste.sweet => t.tasteSweet,
  Taste.bitter => t.tasteBitter,
  Taste.astringent => t.tasteAstringent,
};

String _bodyLabel(AppL10n t, BrewBody body) => switch (body) {
  BrewBody.thin => t.bodyThin,
  BrewBody.full => t.bodyFull,
};

/// Почему так вышло — то, ради чего экран учит, а не просто чинит.
class _Diagnosis extends StatelessWidget {
  const _Diagnosis({required this.taste, required this.body});

  final Taste? taste;
  final BrewBody? body;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final lines = <String>[
      if (taste != null && taste != Taste.sweet) _whyTaste(t, taste!),
      if (body == BrewBody.thin) t.adviceWhyThin,
      if (taste == Taste.sweet) t.adviceWhySweet,
    ];
    if (lines.isEmpty) lines.add(t.adviceNoChange);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: ShapeDecoration(
        color: const Color(0x14FFB000),
        shape: kSquircle(
          K.rCard,
          side: BorderSide(color: K.amber.withValues(alpha: 0.35)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (i, line) in lines.indexed) ...[
            if (i > 0) const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const KIconView(KIcon.speedometer, size: 18, color: K.amber),
                const SizedBox(width: 9),
                Expanded(child: Text(line, style: _prose)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static String _whyTaste(AppL10n t, Taste taste) => switch (taste) {
    Taste.sour => t.adviceWhySour,
    Taste.salty => t.adviceWhySalty,
    Taste.empty => t.adviceWhyEmpty,
    Taste.bitter => t.adviceWhyBitter,
    Taste.astringent => t.adviceWhyAstringent,
    Taste.sweet => t.adviceWhySweet,
  };
}

/// Карточка рычага, который крутят руками: помол, доза, выход. Не ручка —
/// обучение: что сделать и почему это работает.
class _FixCard extends StatelessWidget {
  const _FixCard({required this.fix, required this.tier});

  final Fix fix;
  final Tier tier;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final primary = tier == Tier.primary;
    final muted = tier == Tier.lastResort;
    final accent = muted ? K.textMuted : K.amber;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: ShapeDecoration(
        color: primary ? const Color(0x14FFB000) : K.rowBg,
        shape: kSquircle(
          K.rCard,
          side: BorderSide(
            color: primary ? K.amber.withValues(alpha: 0.5) : K.glassBorder,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: K.rowDial,
              shape: BoxShape.circle,
            ),
            child: KIconView(_icon(fix), size: 18, color: accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (muted) ...[
                  Text(
                    t.adviceLastResort.toUpperCase(),
                    style: K.cap.copyWith(color: K.textMuted),
                  ),
                  const SizedBox(height: 3),
                ],
                Text(
                  _title(t, fix),
                  style: K.rowTitle.copyWith(
                    color: muted ? K.text2 : K.text,
                    fontSize: 17,
                  ),
                ),
                const SizedBox(height: 4),
                Text(_why(t, fix), style: _prose.copyWith(color: K.textDim)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static KIcon _icon(Fix fix) => switch (fix) {
    Fix.grindFiner || Fix.grindCoarser => KIcon.coil,
    Fix.doseMore => KIcon.cup,
    Fix.ratioShorter => KIcon.scale,
    Fix.tempUp || Fix.tempDown => KIcon.thermometer,
  };

  static String _title(AppL10n t, Fix fix) => switch (fix) {
    Fix.grindFiner => t.fixGrindFiner,
    Fix.grindCoarser => t.fixGrindCoarser,
    Fix.doseMore => t.fixDoseMore,
    Fix.ratioShorter => t.fixRatioShorter,
    Fix.tempUp || Fix.tempDown => t.temperature,
  };

  static String _why(AppL10n t, Fix fix) => switch (fix) {
    Fix.grindFiner => t.fixGrindFinerWhy,
    Fix.grindCoarser => t.fixGrindCoarserWhy,
    Fix.doseMore => t.fixDoseMoreWhy,
    Fix.ratioShorter => t.fixRatioShorterWhy,
    Fix.tempUp => t.fixTempUpWhy,
    Fix.tempDown => t.fixTempDownWhy,
  };
}

/// Единственная ручка в приложении — температура. Крайняя мера: показываем, лишь
/// когда помол на своём месте, и правим её тут же, вживую.
class _TempCard extends StatelessWidget {
  const _TempCard({
    required this.up,
    required this.tier,
    required this.device,
    required this.editor,
    required this.fahrenheit,
  });

  final bool up;
  final Tier tier;
  final K2Device device;
  final RecipeEditor editor;
  final bool fahrenheit;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final r = editor.active;
    final limits = device.tempLimits;
    final muted = tier == Tier.lastResort;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: ShapeDecoration(
        color: K.rowBg,
        shape: kSquircle(K.rCard, side: const BorderSide(color: K.glassBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (muted) ...[
            Text(
              t.adviceLastResort.toUpperCase(),
              style: K.cap.copyWith(color: K.textMuted),
            ),
            const SizedBox(height: 3),
          ],
          Text(
            up ? t.fixTempUpWhy : t.fixTempDownWhy,
            style: _prose.copyWith(color: K.textDim),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  t.temperature,
                  style: K.rowTitle.copyWith(color: K.text),
                ),
              ),
              StepButton(
                plus: false,
                enabled: r.temperatureC > limits.min,
                onTap: () => editor.edit(temperatureC: r.temperatureC - 1),
                size: 38,
              ),
              Container(
                width: 74,
                alignment: Alignment.center,
                child: Text(
                  '${toDisplayTemp(r.temperatureC, fahrenheit)}'
                  '${fahrenheit ? '°F' : '°C'}',
                  style: K.rowValue.copyWith(color: K.amber),
                ),
              ),
              StepButton(
                plus: true,
                enabled: r.temperatureC < limits.max,
                onTap: () => editor.edit(temperatureC: r.temperatureC + 1),
                size: 38,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Ряд выбираемых чипов, переносится на вторую строку при нехватке места.
class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) =>
      Wrap(spacing: 8, runSpacing: 8, children: children);
}

/// Чип выбора вкуса или тела. Выбранный — янтарный.
class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => KTap(
    onTap: onTap,
    semanticLabel: label,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: selected ? const Color(0x1FFFB000) : const Color(0x08FFFFFF),
        borderRadius: BorderRadius.circular(K.rChip),
        border: Border.all(
          color: selected ? K.amber.withValues(alpha: 0.7) : K.glassBorder,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: selected ? K.amber : K.text2,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );
}

/// Шапка страницы с кнопкой «назад».
class _Header extends StatelessWidget {
  const _Header({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 44,
    child: Row(
      children: [
        const SizedBox(width: 8),
        RoundIconButton(
          icon: KIcon.chevronRight,
          flipped: true,
          onTap: () => Navigator.of(context).maybePop(),
          semanticLabel: MaterialLocalizations.of(context).backButtonTooltip,
        ),
        Expanded(
          child: Text(title, textAlign: TextAlign.center, style: K.title),
        ),
        const SizedBox(width: 52),
      ],
    ),
  );
}
