import 'package:flutter/material.dart';

import '../../ble/scale/scale_device.dart';
import '../../l10n/l10n_ext.dart';
import '../../model/gravimetry.dart';
import '../../store/prefs.dart';
import '../theme.dart';
import '../widgets/k_icons.dart';
import 'sheet.dart';

/// Настройка шага «вес»: чем кончится пролив и в каком отношении.
///
/// Здесь только уставки — ровно как в листе пролива. Сами весы как прибор
/// (крупная цифра, тара, журнал) живут на своём экране: смешивать «взвесить
/// зерно» с «чем рубить экстракцию» значит делать вид, что это одно занятие.
/// Единственное живое число тут — в строке «взять с весов», и оно здесь на
/// правах датчика, а не прибора.
///
/// Переключатель стоит первой строкой, потому что он главный: весы на связи
/// ещё не значат, что они участвуют в проливе, — они могут просто лежать на
/// столе. Решает человек, и решает здесь.
Future<void> showWeightSheet(
  BuildContext context, {
  required ScaleDevice scale,
  required Prefs prefs,
  required void Function(bool on)? onAutoStop,
}) {
  final t = context.t;
  return showAppSheet<void>(
    context,
    title: t.stepWeight,
    builder: (ctx) => _Body(scale: scale, prefs: prefs, onAutoStop: onAutoStop),
  );
}

class _Body extends StatelessWidget {
  const _Body({
    required this.scale,
    required this.prefs,
    required this.onAutoStop,
  });

  final ScaleDevice scale;
  final Prefs prefs;

  /// null — переключать нельзя: машина работает, уставок на ходу она не берёт.
  final void Function(bool on)? onAutoStop;

  static String _g(double v) => v.toStringAsFixed(1);

  static void _setTarget(Prefs prefs, Gravimetry g, double delta) {
    prefs.gravimetry = g.copyWith(
      targetG: snapGrams((g.targetG + delta).clamp(kYieldMin, kYieldMax)),
    );
  }

  static void _setDose(Prefs prefs, Gravimetry g, double delta) {
    prefs.gravimetry = g.copyWith(
      doseG: snapGrams(((g.doseG ?? 0) + delta).clamp(0.0, kYieldMax)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return ListenableBuilder(
      listenable: Listenable.merge([scale, prefs]),
      builder: (context, _) {
        final g = prefs.gravimetry;
        final live = scale.isLive;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetSwitch(
              title: t.weightStopByWeight,
              value: g.stopOnYield && live,
              onChanged: live ? onAutoStop : null,
            ),
            SheetCaption(
              !live
                  ? t.weightNotConnected
                  : g.stopOnYield
                  ? t.weightStopByWeightHint
                  : t.weightLimitHint,
              align: TextAlign.start,
            ),
            const SizedBox(height: 10),

            SheetStepperRow(
              label: t.weightTarget,
              description: t.descYield,
              value: _g(g.targetG),
              unit: t.gramsUnit,
              canDown: g.targetG > kYieldMin,
              canUp: g.targetG < kYieldMax,
              onDown: () => _setTarget(prefs, g, -kYieldStep),
              onUp: () => _setTarget(prefs, g, kYieldStep),
              // Удержание — по грамму: цель редко ходит на десятые, а вот с 36
              // до 40 крутить мелким шагом мучительно.
              onDownHold: () => _setTarget(prefs, g, -kYieldStepCoarse),
              onUpHold: () => _setTarget(prefs, g, kYieldStepCoarse),
            ),

            SheetStepperRow(
              label: t.weightDose,
              description: g.ratio == null
                  ? t.weightNoDose
                  : t.weightRatio(g.ratio!.toStringAsFixed(1)),
              value: g.doseG == null ? '—' : _g(g.doseG!),
              unit: g.doseG == null ? null : t.gramsUnit,
              canDown: (g.doseG ?? 0) > kYieldStep,
              canUp: (g.doseG ?? 0) < kYieldMax,
              onDown: () => _setDose(prefs, g, -kYieldStep),
              onUp: () => _setDose(prefs, g, kYieldStep),
              onDownHold: () => _setDose(prefs, g, -kYieldStepCoarse),
              onUpHold: () => _setDose(prefs, g, kYieldStepCoarse),
            ),

            // Взвесил зерно — и тут же сделал его дозой. Без этой строки
            // цифру пришлось бы набирать плюсиком, глядя на неё же. Подпись
            // говорит, что именно уедет в дозу: «взять с весов» человек читал
            // как загадку, потому что не видно, что там на весах.
            if (live) ...[
              // Ряд-кнопка после счётчика: без зазора она липнет к плюсу и
              // читается как его продолжение, а это отдельное действие.
              const SizedBox(height: 18),
              SheetTile(
                title: t.weightTakeCurrent,
                description: t.weightOnScale(_g(scale.grams)),
                icon: const KIconView(
                  KIcon.scale,
                  size: 17,
                  color: K.textMuted,
                ),
                onTap: scale.grams <= 0
                    ? () {}
                    : () => prefs.gravimetry = g.copyWith(
                        doseG: snapGrams(scale.grams),
                      ),
              ),
            ],
          ],
        );
      },
    );
  }
}
