import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ble/protocol.dart';
import '../../l10n/app_l10n.dart';
import '../../l10n/l10n_ext.dart';
import '../theme.dart';
import '../widgets/mode_button.dart';
import 'sheet.dart';

/// Режим работы: что именно запустит кнопка пуска.
///
/// Выбор закрывает лист — это одно решение из трёх, задерживаться в нём не за
/// чем.
Future<WorkMode?> showModeSheet(
  BuildContext context, {
  required WorkMode selected,
}) {
  final t = context.t;
  return showAppSheet<WorkMode>(
    context,
    title: t.runMode,
    builder: (ctx) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, m) in _order.indexed) ...[
          if (i > 0) const SizedBox(height: 8),
          Builder(
            builder: (context) {
              final style = ModeStyle.of(m);
              return SheetTile(
                title: m.label(t),
                description: _describe(t, m),
                accent: style.light,
                selected: m == selected,
                icon: ModeIcon(mode: m, size: 19, color: style.light),
                onTap: () {
                  HapticFeedback.selectionClick();
                  Navigator.pop(ctx, m);
                },
              );
            },
          ),
        ],
      ],
    ),
  );
}

/// Порядок рядов: от самого простого действия к самому полному и обратно к
/// холодному проливу.
const _order = [WorkMode.heat, WorkMode.heatAndBrew, WorkMode.brew];

String _describe(AppL10n t, WorkMode m) => switch (m) {
  WorkMode.heat => t.modeHeatDesc,
  WorkMode.heatAndBrew => t.modeHeatAndBrewDesc,
  WorkMode.brew => t.modeBrewDesc,
};
