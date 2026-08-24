import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ble/k2_device.dart';
import '../../ble/protocol.dart';
import '../../l10n/l10n_ext.dart';
import '../theme.dart';
import 'sheet.dart';

/// Отложенный старт. По протоколу это будильник: машина сама включает выбранный
/// режим в заданное время суток и, если разрешён звук, пикает.
Future<void> showTimerSheet(BuildContext context, K2Device device) async {
  final t = context.t;
  await showAppSheet<void>(
    context,
    title: t.timer,
    trailing: ListenableBuilder(
      listenable: device,
      builder: (ctx, _) => KSwitch(
        value: device.appointment.enabled,
        // Пока связи нет, менять будильник некуда — он живёт в машине.
        onChanged: device.isConnected
            ? (v) => device.setSchedule(device.appointment.copyWith(enabled: v))
            : null,
      ),
    ),
    builder: (ctx) => ListenableBuilder(
      listenable: device,
      builder: (ctx, _) => _Body(device: device),
    ),
  );
  // Лист закрыли — значение выбрано, ждать паузу больше незачем.
  await device.flushSchedule();
}

/// Что сейчас крутят кнопками: часы или минуты.
enum _Unit { hour, minute }

class _Body extends StatefulWidget {
  const _Body({required this.device});

  final K2Device device;

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  /// Часы — крупный шаг, минуты — точная доводка. Начинаем с часов: время
  /// будильника чаще двигают на час, чем на минуту.
  _Unit _unit = _Unit.hour;

  /// Сдвинуть будильник на [minutes] минут по кругу суток.
  void _shift(int minutes) {
    HapticFeedback.selectionClick();
    final a = widget.device.appointment;
    final total = (a.hour * 60 + a.minute + minutes) % (24 * 60);
    final m = total < 0 ? total + 24 * 60 : total;
    widget.device.setSchedule(a.copyWith(hour: m ~/ 60, minute: m % 60));
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final a = widget.device.appointment;
    final on = widget.device.isConnected;
    // Пока будильник выключен, время и сигнал редактировать бессмысленно.
    final live = on && a.enabled;
    final step = _unit == _Unit.hour ? 60 : 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetCaption(t.scheduleHint, align: TextAlign.start),
        const SizedBox(height: 22),
        AnimatedOpacity(
          opacity: live ? 1 : 0.35,
          duration: const Duration(milliseconds: 250),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BigStepper(
                buttonSize: 42,
                canDown: live,
                canUp: live,
                onDown: () => _shift(-step),
                onUp: () => _shift(step),
                // Кнопки крутят ту часть, по которой тапнули: час целиком или
                // минуту за раз. Иначе поставить 07:37 было бы нечем.
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _Part(
                      text: _two(a.hour),
                      selected: _unit == _Unit.hour,
                      onTap: live
                          ? () => setState(() => _unit = _Unit.hour)
                          : null,
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Text(
                        ':',
                        style: K.bigValue.copyWith(
                          fontSize: 44,
                          color: K.amber.withValues(alpha: 0.55),
                        ),
                      ),
                    ),
                    _Part(
                      text: _two(a.minute),
                      selected: _unit == _Unit.minute,
                      onTap: live
                          ? () => setState(() => _unit = _Unit.minute)
                          : null,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Пресеты: то, что чаще всего и нужно — сдвинуть подъём на
              // четверть часа в ту или другую сторону.
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SheetChip(
                    label: t.minutesShift('−15'),
                    enabled: live,
                    onTap: () => _shift(-15),
                  ),
                  const SizedBox(width: 10),
                  SheetChip(
                    label: t.minutesShift('+15'),
                    enabled: live,
                    onTap: () => _shift(15),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              SheetOption(
                title: t.scheduleMode,
                trailing: a.mode.label(t),
                onTap: live
                    ? () => widget.device.setSchedule(
                        a.copyWith(
                          mode: ScheduleMode.values[(a.mode.index + 1) % 3],
                        ),
                      )
                    : () {},
              ),
              SheetSwitch(
                title: t.scheduleSound,
                value: a.reminder == ReminderMode.sound,
                onChanged: live
                    ? (v) => widget.device.setSchedule(
                        a.copyWith(
                          reminder: v
                              ? ReminderMode.sound
                              : ReminderMode.silent,
                        ),
                      )
                    : null,
              ),
              SheetOption(
                title: t.scheduleTone,
                trailing: a.beep.label(t),
                onTap: live
                    ? () => widget.device.setSchedule(
                        a.copyWith(
                          beep: BeepSound.values[(a.beep.index + 1) % 4],
                        ),
                      )
                    : () {},
              ),
            ],
          ),
        ),
        if (!on) ...[const SizedBox(height: 12), SheetCaption(t.notConnected)],
      ],
    );
  }
}

/// Часы или минуты. Выбранная часть светится и подчёркнута — по ней и работают
/// кнопки «−» и «+».
class _Part extends StatelessWidget {
  const _Part({
    required this.text,
    required this.selected,
    required this.onTap,
  });

  final String text;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    behavior: HitTestBehavior.opaque,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          text,
          style: K.bigValue.copyWith(
            fontSize: 44,
            color: selected ? K.amber : K.amber.withValues(alpha: 0.5),
            shadows: selected
                ? [const Shadow(color: Color(0x73FFB000), blurRadius: 24)]
                : null,
          ),
        ),
        const SizedBox(height: 6),
        AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          height: 2,
          width: selected ? 46 : 0,
          decoration: BoxDecoration(
            color: K.amber,
            borderRadius: BorderRadius.circular(1),
          ),
        ),
      ],
    ),
  );
}
