import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ble/k2_device.dart';
import '../../ble/protocol.dart';
import '../../l10n/app_l10n.dart';
import '../../l10n/l10n_ext.dart';
import '../../model/recipe.dart';
import '../theme.dart';
import '../widgets/k_icons.dart';
import 'sheet.dart';

/// Пресеты готовности: через сколько минут кофе должен стоять в чашке. Три
/// минуты для отсчёта смысла не имеют, тридцать — разумный потолок для «пока
/// готовлю завтрак».
const List<int> _presets = [5, 10, 20, 30];

/// Насколько заранее машина стартует под режим с нагревом, чтобы к сроку кофе
/// уже был готов. Пролив мы знаем из рецепта до секунды, а вот время нагрева
/// машина не сообщает — это оценка. Она намеренно скромная: лучше кофе выйдет
/// на минуту раньше и подождёт, чем человек вернётся к пустой чашке.
const int _heatEstimateSeconds = 150;

/// Таймер готовности. Главное — пресеты «готов через N минут»: тапнул — и на
/// экране живой отсчёт. Внутри протокола это по-прежнему будильник по часам
/// суток, «через N» мы считаем сами: старт = срок − длительность цикла.
Future<void> showTimerSheet(
  BuildContext context,
  K2Device device, {
  required Recipe recipe,
  required WorkMode runMode,
}) async {
  final t = context.t;
  await showAppSheet<void>(
    context,
    title: t.timer,
    builder: (ctx) => ListenableBuilder(
      listenable: device,
      builder: (ctx, _) =>
          _Body(device: device, recipe: recipe, runMode: runMode),
    ),
  );
  // Лист закрыли — крутить время больше не будут, дожимаем отложенную запись.
  await device.flushSchedule();
}

/// Сколько длится цикл выбранного режима: то, что мы вычитаем из срока
/// готовности, чтобы получить момент старта.
int _cycleSeconds(Recipe r, ScheduleMode mode) {
  final brew = r.preInfusionSeconds + r.standstillSeconds + r.extractionSeconds;
  return switch (mode) {
    ScheduleMode.heat => _heatEstimateSeconds,
    ScheduleMode.heatAndBrew => _heatEstimateSeconds + brew,
    ScheduleMode.brew => brew,
  };
}

/// Ближайшее наступление часа:минуты будильника.
DateTime _nextAt(Appointment a, DateTime now) {
  final today = DateTime(now.year, now.month, now.day, a.hour, a.minute);
  return today.isAfter(now) ? today : today.add(const Duration(days: 1));
}

String _two(int v) => v.toString().padLeft(2, '0');
String _hhmm(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}';

String _scheduleSentence(AppL10n t, K2Device device) {
  final a = device.appointment;
  final now = device.currentTime;
  final at = _nextAt(a, now);
  final today =
      at.year == now.year && at.month == now.month && at.day == now.day;
  return t.scheduleStarts(
    today ? t.scheduleToday : t.scheduleTomorrow,
    _hhmm(at),
    a.mode.label(t),
  );
}

/// Что сейчас крутят кнопками на экране «Ко времени»: часы или минуты.
enum _Unit { hour, minute }

class _Body extends StatefulWidget {
  const _Body({
    required this.device,
    required this.recipe,
    required this.runMode,
  });

  final K2Device device;
  final Recipe recipe;
  final WorkMode runMode;

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  /// Раскрыт ли раздел «Ко времени». По умолчанию свёрнут — на экране только
  /// пресеты, ради двух тапов всё и затевалось.
  bool _byTime = false;

  /// Какую часть времени крутят на «Ко времени».
  _Unit _unit = _Unit.hour;

  /// Тикает раз в секунду, чтобы живой отсчёт шёл, пока лист открыт.
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  K2Device get _device => widget.device;
  Appointment get _a => _device.appointment;

  /// Взвести пресет: срок = сейчас + N, старт = срок − цикл (но не в прошлое).
  void _armPreset(int minutes) {
    HapticFeedback.selectionClick();
    final mode = widget.runMode.asScheduleMode;
    final now = _device.currentTime;
    final cycle = _cycleSeconds(widget.recipe, mode);
    var start = now
        .add(Duration(minutes: minutes))
        .subtract(Duration(seconds: cycle));
    // Пресет короче цикла — стартуем как можно раньше, прямо сейчас.
    if (start.isBefore(now)) start = now;
    // Машина хранит только час и минуту: округляем до минуты.
    _device.setSchedule(
      _a.copyWith(
        mode: mode,
        hour: start.hour,
        minute: start.minute,
        enabled: true,
      ),
      immediate: true,
    );
  }

  void _cancel() {
    HapticFeedback.selectionClick();
    _device.setSchedule(_a.copyWith(enabled: false), immediate: true);
  }

  /// Сдвинуть будильник «Ко времени» на [minutes] по кругу суток.
  void _shift(int minutes) {
    HapticFeedback.selectionClick();
    final total = (_a.hour * 60 + _a.minute + minutes) % (24 * 60);
    final m = total < 0 ? total + 24 * 60 : total;
    _device.setSchedule(_a.copyWith(hour: m ~/ 60, minute: m % 60));
  }

  /// Тап по ячейке режима перебирает режимы по кругу — без второго листа.
  void _cycleMode() {
    HapticFeedback.selectionClick();
    const vals = ScheduleMode.values;
    final next = vals[(vals.indexOf(_a.mode) + 1) % vals.length];
    _device.setSchedule(_a.copyWith(mode: next));
  }

  /// Так же по кругу — мелодия сигнала.
  void _cycleTone() {
    HapticFeedback.selectionClick();
    const vals = BeepSound.values;
    final next = vals[(vals.indexOf(_a.beep) + 1) % vals.length];
    _device.setSchedule(_a.copyWith(beep: next));
  }

  Future<void> _scheduleByTime() async {
    final t = context.t;
    final ok = await showGlassDialog<bool>(
      context,
      title: t.confirmScheduledStart,
      message: '${_scheduleSentence(t, _device)}\n\n${t.scheduledStartWarning}',
      actions: [
        KDialogButton(
          label: t.cancel,
          onTap: () => Navigator.pop(context, false),
        ),
        KDialogButton(
          label: t.enable,
          danger: true,
          onTap: () => Navigator.pop(context, true),
        ),
      ],
    );
    if (ok == true) {
      _device.setSchedule(_a.copyWith(enabled: true), immediate: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Взведён — показываем живой отсчёт, всё остальное убираем: у листа сейчас
    // ровно одна задача, отменить.
    return _a.enabled ? _armed(context) : _setup(context);
  }

  Widget _armed(BuildContext context) {
    final t = context.t;
    final now = _device.currentTime;
    final start = _nextAt(_a, now);
    final cycle = _cycleSeconds(widget.recipe, _a.mode);
    final readyAt = start.add(Duration(seconds: cycle));
    final left = readyAt.difference(now);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 4),
        Text(
          t.timerReadyIn,
          textAlign: TextAlign.center,
          style: K.cap.copyWith(color: K.textDim),
        ),
        const SizedBox(height: 10),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            _remaining(t, left),
            maxLines: 1,
            style: K.bigValue.copyWith(
              fontSize: 56,
              color: K.amber,
              shadows: const [Shadow(color: Color(0x73FFB000), blurRadius: 28)],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '${t.timerStartAt(_hhmm(start))} · ${_a.mode.label(t)}',
          textAlign: TextAlign.center,
          style: K.caption.copyWith(color: K.textMuted),
        ),
        const SizedBox(height: 22),
        _WideButton(label: t.cancelAlarm, onTap: _cancel),
      ],
    );
  }

  Widget _setup(BuildContext context) {
    final t = context.t;
    final connected = _device.isConnected;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetCaption(t.timerReadyHint, align: TextAlign.start),
        const SizedBox(height: 16),
        AnimatedOpacity(
          opacity: connected ? 1 : 0.35,
          duration: const Duration(milliseconds: 250),
          child: Row(
            children: [
              for (var i = 0; i < _presets.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: _PresetButton(
                    minutes: _presets[i],
                    enabled: connected,
                    onTap: () => _armPreset(_presets[i]),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        // «Ко времени» раскрывается прямо здесь, в этом же листе: секции просто
        // выезжают вниз, второй модалки поверх первой не появляется.
        _Expander(
          title: t.timerByTime,
          open: _byTime,
          enabled: connected,
          onTap: () => setState(() => _byTime = !_byTime),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _byTime && connected
              ? _byTimeBody(context)
              : const SizedBox(width: double.infinity),
        ),
        if (!connected) ...[
          const SizedBox(height: 12),
          SheetCaption(t.notConnected),
        ],
      ],
    );
  }

  Widget _byTimeBody(BuildContext context) {
    final t = context.t;
    final step = _unit == _Unit.hour ? 60 : 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 18),
        BigStepper(
          buttonSize: 42,
          canDown: true,
          canUp: true,
          onDown: () => _shift(-step),
          onUp: () => _shift(step),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Part(
                text: _two(_a.hour),
                selected: _unit == _Unit.hour,
                onTap: () => setState(() => _unit = _Unit.hour),
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
                text: _two(_a.minute),
                selected: _unit == _Unit.minute,
                onTap: () => setState(() => _unit = _Unit.minute),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SheetChip(label: t.minutesShift('−15'), onTap: () => _shift(-15)),
            const SizedBox(width: 10),
            SheetChip(label: t.minutesShift('+15'), onTap: () => _shift(15)),
          ],
        ),
        const SizedBox(height: 14),
        _CycleRow(
          title: t.scheduleMode,
          value: _a.mode.label(t),
          onTap: _cycleMode,
        ),
        SheetSwitch(
          title: t.scheduleSound,
          value: _a.reminder == ReminderMode.sound,
          onChanged: (v) => _device.setSchedule(
            _a.copyWith(reminder: v ? ReminderMode.sound : ReminderMode.silent),
          ),
        ),
        // Мелодию показываем только при включённом звуке: без него выбирать
        // сигнал нечему.
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.topCenter,
          child: _a.reminder == ReminderMode.sound
              ? _CycleRow(
                  title: t.scheduleTone,
                  value: _a.beep.label(t),
                  onTap: _cycleTone,
                )
              : const SizedBox(width: double.infinity),
        ),
        const SizedBox(height: 16),
        SheetCaption(_scheduleSentence(t, _device), align: TextAlign.start),
        const SizedBox(height: 10),
        _WideButton(label: t.timerSchedule, onTap: _scheduleByTime),
      ],
    );
  }

  /// Живой остаток: до часа — «M:SS», дальше — «1 ч 32 мин».
  static String _remaining(AppL10n t, Duration d) {
    final s = d.inSeconds.clamp(0, 24 * 3600);
    if (s >= 3600) {
      return '${s ~/ 3600} ${t.hoursShort} ${_two((s % 3600) ~/ 60)} ${t.minutesShort}';
    }
    return '${s ~/ 60}:${_two(s % 60)}';
  }
}

/// Пресет готовности: крупное число и «мин» под ним.
class _PresetButton extends StatelessWidget {
  const _PresetButton({
    required this.minutes,
    required this.enabled,
    required this.onTap,
  });

  final int minutes;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return KTap(
      onTap: enabled ? onTap : null,
      semanticLabel: '$minutes ${t.minutesShort}',
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0x08FFFFFF),
          borderRadius: BorderRadius.circular(K.rPreset),
          border: Border.all(color: K.glassBorder),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$minutes',
              style: K.bigValue.copyWith(fontSize: 26, color: K.amber),
            ),
            const SizedBox(height: 2),
            Text(
              t.minutesShort,
              style: TextStyle(
                color: K.amber.withValues(alpha: 0.55),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Заголовок раскрывающегося раздела со стрелкой, что смотрит вниз, когда
/// раздел открыт.
class _Expander extends StatelessWidget {
  const _Expander({
    required this.title,
    required this.open,
    required this.enabled,
    required this.onTap,
  });

  final String title;
  final bool open;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => KTap(
    onTap: enabled ? onTap : null,
    semanticLabel: title,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 13),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: enabled ? K.text : K.textDisabled,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          AnimatedRotation(
            turns: open ? 0.25 : 0,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            child: KIconView(
              KIcon.chevronRight,
              size: 18,
              color: enabled ? K.textMuted : K.textDisabled,
            ),
          ),
        ],
      ),
    ),
  );
}

/// Ряд «название — значение», где тап по всему ряду перебирает значение по
/// кругу. Заменяет вложенный лист выбора: значение в янтарной пилюле само
/// говорит, что его можно нажать.
class _CycleRow extends StatelessWidget {
  const _CycleRow({
    required this.title,
    required this.value,
    required this.onTap,
  });

  final String title;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => KTap(
    onTap: onTap,
    semanticLabel: '$title: $value',
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: K.text,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: K.chipBg,
              borderRadius: BorderRadius.circular(K.rChip),
              border: Border.all(color: K.amber.withValues(alpha: 0.35)),
            ),
            child: Text(value, style: K.menuChip.copyWith(color: K.amber)),
          ),
        ],
      ),
    ),
  );
}

/// Кнопка во всю ширину листа: отмена отсчёта, «запланировать».
class _WideButton extends StatelessWidget {
  const _WideButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => KTap(
    onTap: onTap,
    semanticLabel: label,
    child: Container(
      height: 50,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: K.chipBg,
        borderRadius: BorderRadius.circular(K.rPill),
        border: Border.all(color: K.amber.withValues(alpha: 0.45)),
      ),
      child: Text(
        label,
        style: K.menuChip.copyWith(color: K.amber, fontSize: 15),
      ),
    ),
  );
}

/// Часы или минуты на экране «Ко времени». Выбранная часть светится и
/// подчёркнута — по ней и работают кнопки «−» и «+».
class _Part extends StatelessWidget {
  const _Part({
    required this.text,
    required this.selected,
    required this.onTap,
  });

  final String text;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => KTap(
    onTap: onTap,
    semanticLabel: text,
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
