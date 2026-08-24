import 'package:flutter/material.dart';

import '../../l10n/app_l10n.dart';
import '../../l10n/l10n_ext.dart';
import '../../store/prefs.dart';
import 'sheet.dart';

/// Пресеты температуры по обжарке. Светлую надо заваривать горячее, тёмную —
/// прохладнее, иначе горчит. Порядок в ряду — от тёмной к светлой.
const _presets = <String, int>{'dark': 89, 'medium': 93, 'light': 96};

/// Выбор температуры: крупный степпер плюс три пресета по обжарке.
Future<void> showTemperatureSheet(
  BuildContext context, {
  required int celsius,
  required int min,
  required int max,
  required bool fahrenheit,
  required ValueChanged<int> onChanged,
}) {
  final t = context.t;
  return showAppSheet<void>(
    context,
    title: t.temperature,
    builder: (ctx) => _Body(
      value: celsius,
      min: min,
      max: max,
      fahrenheit: fahrenheit,
      onChanged: onChanged,
    ),
  );
}

class _Body extends StatefulWidget {
  const _Body({
    required this.value,
    required this.min,
    required this.max,
    required this.fahrenheit,
    required this.onChanged,
  });

  final int value;
  final int min;
  final int max;
  final bool fahrenheit;
  final ValueChanged<int> onChanged;

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  late int _v = widget.value;

  void _set(int celsius) {
    final c = celsius.clamp(widget.min, widget.max);
    if (c == _v) return;
    setState(() => _v = c);
    widget.onChanged(c);
  }

  String _fmt(int celsius) =>
      '${toDisplayTemp(celsius, widget.fahrenheit)}${widget.fahrenheit ? '°F' : '°C'}';

  String _title(AppL10n t, String key) => switch (key) {
    'light' => t.roastLightShort,
    'dark' => t.roastDarkShort,
    _ => t.roastMediumShort,
  };

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    // Пресет вне границ машины прячем, иначе он молча съедет при нажатии.
    final shown = _presets.entries
        .where((e) => e.value >= widget.min && e.value <= widget.max)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BigStepper(
          text: _fmt(_v),
          canDown: _v > widget.min,
          canUp: _v < widget.max,
          onDown: () => _set(_v - 1),
          onUp: () => _set(_v + 1),
        ),
        const SizedBox(height: 10),
        SheetCaption(t.limitsRange(_fmt(widget.min), _fmt(widget.max))),
        const SizedBox(height: 24),
        Row(
          children: [
            for (final (i, e) in shown.indexed) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: PresetTile(
                  title: _title(t, e.key),
                  value: _fmt(e.value),
                  selected: _v == e.value,
                  onTap: () => _set(e.value),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 14),
        SheetCaption(t.presetsByRoast),
      ],
    );
  }
}
