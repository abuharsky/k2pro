import 'package:flutter/material.dart';

import '../../ble/protocol.dart';
import '../../model/recipe.dart';
import '../../l10n/l10n_ext.dart';
import 'sheet.dart';

/// Пролив целиком: времена трёх его фаз и скорость подачи воды.
///
/// Экстракция здесь — не «сколько нальётся», а потолок: машина остановится
/// ровно на этой отметке и дольше лить не станет. Шаг, выставленный в ноль,
/// из цикла просто выпадает — об этом сказано прямым текстом, иначе ноль
/// читается как поломка.
///
/// Скорость подачи воды стоит здесь же: менять её приходится вместе с
/// временами — короткий пролив на медленной подаче и длинный на быстрой это
/// два разных кофе, и решаются они одним движением.
Future<void> showPourSheet(
  BuildContext context, {
  required Recipe recipe,
  required WorkParams params,
  required ValueChanged<Recipe> onChanged,
}) {
  final t = context.t;
  return showAppSheet<void>(
    context,
    title: t.pourTimeTitle,
    builder: (ctx) =>
        _Body(recipe: recipe, params: params, onChanged: onChanged),
  );
}

class _Body extends StatefulWidget {
  const _Body({
    required this.recipe,
    required this.params,
    required this.onChanged,
  });

  final Recipe recipe;
  final WorkParams params;
  final ValueChanged<Recipe> onChanged;

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  late Recipe _r = widget.recipe;

  void _set(Recipe r) {
    setState(() => _r = r);
    widget.onChanged(r);
  }

  // Границы приходят от машины; пока их нет — те, что в спецификации.
  Range get _pre => widget.params.preInfusion;
  Range get _still => widget.params.standstill;
  Range get _ext => widget.params.extraction;
  Range get _flow => widget.params.pressure;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final total =
        _r.preInfusionSeconds + _r.standstillSeconds + _r.extractionSeconds;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _row(
          label: t.stepWetting,
          description: t.descWetting,
          value: _r.preInfusionSeconds,
          range: _pre,
          unit: t.secondsUnit,
          apply: (v) => _r.copyWith(preInfusionSeconds: v),
        ),
        _row(
          label: t.stepPause,
          description: t.descPause,
          value: _r.standstillSeconds,
          range: _still,
          unit: t.secondsUnit,
          apply: (v) => _r.copyWith(standstillSeconds: v),
        ),
        _row(
          label: t.extraction,
          description: t.descExtraction,
          value: _r.extractionSeconds,
          range: _ext,
          // Время экстракции машина принимает шагом 5 с, остальное посекундно.
          step: 5,
          unit: t.secondsUnit,
          apply: (v) => _r.copyWith(extractionSeconds: v),
        ),
        _row(
          label: t.flowSpeed,
          description: t.descFlow,
          value: _r.pressure,
          range: _flow,
          text: t.stepOf(_r.pressure, _flow.max),
          apply: (v) => _r.copyWith(pressure: v),
        ),
        const SizedBox(height: 16),
        SheetCaption(t.pourSkipNote, align: TextAlign.start),
        const SizedBox(height: 10),
        SheetCaption(t.cycleTotal(total), align: TextAlign.start),
      ],
    );
  }

  Widget _row({
    required String label,
    required String description,
    required int value,
    required Range range,
    required Recipe Function(int) apply,
    String? unit,
    String? text,
    int step = 1,
  }) => SheetStepperRow(
    label: label,
    description: description,
    value: text ?? '$value',
    unit: text == null ? unit : null,
    canDown: value > range.min,
    canUp: value < range.max,
    onDown: () => _set(apply(range.clamp(value - step))),
    onUp: () => _set(apply(range.clamp(value + step))),
  );
}
