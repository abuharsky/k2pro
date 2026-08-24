import 'package:flutter/widgets.dart';

import '../../ble/protocol.dart';
import 'k_icons.dart';

/// Значок режима: спираль, спираль с каплей или капля.
///
/// Выбор режима живёт в листе — здесь остался только его знак: он стоит в
/// ячейке нижнего ряда и в самом листе.
class ModeIcon extends StatelessWidget {
  const ModeIcon({
    super.key,
    required this.mode,
    required this.color,
    this.size = 20,
  });

  final WorkMode mode;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => switch (mode) {
    WorkMode.heat => KIconView(KIcon.coil, size: size, color: color),
    WorkMode.heatAndBrew => KIconView(KIcon.heatBrew, size: size, color: color),
    WorkMode.brew => KIconView(KIcon.droplet, size: size, color: color),
  };
}
