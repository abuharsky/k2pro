import 'package:flutter/material.dart';

import '../../ble/protocol.dart';
import '../../l10n/l10n_ext.dart';
import '../theme.dart';
import 'k_icons.dart';
import 'round_button.dart';

/// Шапка: гамбургер слева, имя машины по центру с точкой статуса, заряд под
/// именем, кнопка связи справа.
class TopBar extends StatelessWidget {
  const TopBar({
    super.key,
    required this.name,
    required this.connected,
    required this.connecting,
    required this.asleep,
    required this.status,
    required this.onMenu,
    required this.onLink,
    required this.onName,
  });

  final String name;
  final bool connected;
  final bool connecting;

  /// Связь есть, а телеметрии нет — машина в дежурном режиме.
  final bool asleep;

  final DeviceStatus? status;
  final VoidCallback onMenu;
  final VoidCallback onLink;

  /// Тап по имени открывает инфо о машине — так же, как гамбургер.
  final VoidCallback onName;

  /// Высота шапки: от неё считается верх зоны машины.
  static const double height = 42;

  @override
  Widget build(BuildContext context) {
    final s = status;
    // Серый — связи нет; тусклый зелёный — на связи, но машина спит; зелёный —
    // на связи и в покое; янтарный — работает.
    final dot = !connected
        ? const Color(0x40FFFFFF)
        : asleep
        ? K.success.withValues(alpha: 0.28)
        : (s?.state.isBusy ?? false)
        ? K.amber
        : K.success;

    return SizedBox(
      height: height,
      child: Row(
        children: [
          RoundIconButton(icon: KIcon.menu, onTap: onMenu),
          Expanded(
            child: GestureDetector(
              onTap: onName,
              behavior: HitTestBehavior.opaque,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 400),
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: dot,
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: dot, blurRadius: 8)],
                    ),
                  ),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: K.title,
                    ),
                  ),
                  // Заряд стоит справа от имени: строкой ниже он утягивал
                  // шапку вниз, а сам по себе это одна короткая деталь.
                  // Пока машина спит, показывать её заряд нечестно: цифра
                  // осталась с последнего кадра и с тех пор не проверялась.
                  if (asleep) ...[
                    const SizedBox(width: 8),
                    Text(
                      context.t.asleep,
                      style: K.caption.copyWith(color: K.textDim2),
                    ),
                  ] else if (s != null) ...[
                    const SizedBox(width: 10),
                    _Battery(status: s),
                  ],
                ],
              ),
            ),
          ),
          // Связь показывает не рамка, а огонёк на кромке: сама кнопка
          // остаётся обычным стеклом, светится только значок и точка.
          RoundIconButton(
            icon: KIcon.bluetooth,
            onTap: onLink,
            color: connected || connecting ? K.btBlue : K.iconDim,
            glow: connected ? K.btBlue.withValues(alpha: 0.18) : null,
            badge: connected ? K.btBlue : null,
          ),
        ],
      ),
    );
  }
}

/// Заряд машины: четыре деления в контуре батарейки.
///
/// Процентов машина не отдаёт — в пакете лежит номер корзины, и ровно столько
/// же точек светится на её корпусе. Поэтому в подписи рядом только факт
/// зарядки: рисовать «75 %» значило бы придумывать точность, которой нет.
class _Battery extends StatefulWidget {
  const _Battery({required this.status});

  final DeviceStatus status;

  @override
  State<_Battery> createState() => _BatteryState();
}

class _BatteryState extends State<_Battery>
    with SingleTickerProviderStateMixin {
  late final AnimationController _blink = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  );

  bool get _charging => widget.status.charge != ChargeState.notCharging;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(_Battery old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (_charging && !_blink.isAnimating) {
      _blink.repeat(reverse: true);
    } else if (!_charging && _blink.isAnimating) {
      _blink
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _blink,
          builder: (context, _) => CustomPaint(
            size: const Size(25, 12),
            painter: _BatteryPainter(
              level: widget.status.batteryLevel,
              // Мигает только последний сегмент: 1 → .15 и обратно за секунду.
              blink: _charging ? 1 - 0.85 * _blink.value : 1,
              charging: _charging,
            ),
          ),
        ),
        if (_charging) ...[
          const SizedBox(width: 6),
          Text(
            context.t.charging,
            style: K.caption.copyWith(color: K.textDim2),
          ),
        ],
      ],
    );
  }
}

class _BatteryPainter extends CustomPainter {
  _BatteryPainter({
    required this.level,
    required this.blink,
    required this.charging,
  });

  /// 0..4 — столько делений машина и знает.
  final int level;

  /// Прозрачность мигающего сегмента при зарядке.
  final double blink;

  final bool charging;

  @override
  void paint(Canvas canvas, Size size) {
    const nub = 1.6;
    final body = Rect.fromLTWH(
      0.5,
      0.5,
      size.width - nub - 2.5,
      size.height - 1,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(body, const Radius.circular(4)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0x38FFFFFF),
    );

    final inner = body.deflate(2.4);
    const gap = 1.4;
    final w = (inner.width - gap * 3) / 4;
    for (var i = 0; i < 4; i++) {
      // При зарядке следующий за уровнем сегмент мигает — заряд «набирается».
      final pulsing = charging && i == 3;
      final on = i < level;
      final color = on
          ? K.text.withValues(alpha: pulsing ? blink : 1)
          : pulsing
          ? K.text.withValues(alpha: blink * 0.6)
          : const Color(0x24FFFFFF);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(inner.left + i * (w + gap), inner.top, w, inner.height),
          const Radius.circular(1),
        ),
        Paint()..color = color,
      );
    }

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(body.right + 1.2, size.height / 2 - 2, nub, 4),
        const Radius.circular(1),
      ),
      Paint()..color = const Color(0x38FFFFFF),
    );
  }

  @override
  bool shouldRepaint(_BatteryPainter o) =>
      o.level != level || o.blink != blink || o.charging != charging;
}
