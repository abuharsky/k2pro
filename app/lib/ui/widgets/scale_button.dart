import 'package:flutter/material.dart';

import '../../ble/scale/scale_device.dart';
import '../../l10n/l10n_ext.dart';
import '../theme.dart';

/// Весы в нижнем ряду, слева от пуска.
///
/// Стоят здесь, а не в шапке, по двум причинам. Первая: в шапке весы были
/// строчкой текста, а текст не выглядит нажимаемым — тыкать в имя устройства
/// человек не догадается. Вторая: на кнопке видно сам вес, и чтобы взглянуть
/// на него, открывать ничего не надо.
///
/// Той же высоты и того же скругления, что пуск: это один ряд управления. В
/// углу над кнопкой они смотрелись приткнутыми и лезли машине под ноги.
///
/// Появляются только вместе с весами: показывать пустую кнопку тому, у кого
/// весов нет, незачем.
class ScaleButton extends StatelessWidget {
  const ScaleButton({super.key, required this.scale, required this.onTap});

  final ScaleDevice scale;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final live = scale.isLive;

    return KTap(
      onTap: onTap,
      scale: 0.97,
      semanticLabel: t.weightTitle,
      child: Glass(
        radius: K.rCta,
        blur: K.blurButton,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(
                    color: live ? K.success : K.success.withValues(alpha: 0.28),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  t.weightTitle.toUpperCase(),
                  style: K.cap.copyWith(color: K.textDim, fontSize: 9),
                ),
              ],
            ),
            const SizedBox(height: 3),
            // Вес — единственное, ради чего на кнопку смотрят не нажимая.
            // Табличные цифры, чтобы она не дёргалась на каждом кадре весов.
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  live ? scale.grams.toStringAsFixed(1) : '—',
                  style: TextStyle(
                    color: live ? K.textBright : K.textMuted,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                if (live) ...[
                  const SizedBox(width: 2),
                  Text(
                    t.gramsUnit,
                    style: K.caption.copyWith(color: K.textDim2, fontSize: 9),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
