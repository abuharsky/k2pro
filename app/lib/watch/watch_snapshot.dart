import '../ble/k2_device.dart';
import '../ble/protocol.dart';
import '../ble/transport.dart';
import '../l10n/app_l10n.dart';
import '../l10n/l10n_ext.dart';
import '../model/pipeline.dart';
import '../model/recipe.dart';
import '../store/prefs.dart';

/// Версия контракта. Часы отказываются рисовать снимок с чужим номером —
/// лучше честное «обновите приложение», чем экран с перепутанными полями.
const int kWatchContractVersion = 1;

/// Палитра часов по спецификации watchOS. Она отдельная от телефонной: там
/// стекло и градиенты, здесь плоский OLED. Живёт в Dart, чтобы на часах не
/// заводить второй набор цветов, который начнёт расходиться с этим.
class WatchPalette {
  /// Акцент режима — им красятся кнопка пуска и ряд режима.
  static const Map<WorkMode, String> modeAccent = {
    WorkMode.heat: '#FF7A3D',
    WorkMode.heatAndBrew: '#FFB100',
    WorkMode.brew: '#3D9BFF',
  };

  /// Тот же акцент, но для текста: на чёрном фоне заливка читается хуже.
  static const Map<WorkMode, String> modeText = {
    WorkMode.heat: '#FF9E70',
    WorkMode.heatAndBrew: '#FFB000',
    WorkMode.brew: '#7CBBFF',
  };

  static const String heat = '#FF9E70';
  static const String water = '#7CBBFF';
  static const String amber = '#FFB000';

  static const String danger = '#E0352B';
  static const String success = '#34C759';
  static const String onSuccess = '#0D2413';
  static const String onAccent = '#0D0F12';
  static const String onDanger = '#FFFFFF';
}

/// Собрать снимок состояния для часов.
///
/// Всё, что часам нужно знать, лежит здесь: и числа, и подписи, и границы, и
/// цвета. На той стороне нет ни одного правила про кофе — только отрисовка
/// того, что приехало.
Map<String, Object?> buildWatchSnapshot({
  required K2Device d,
  required AppL10n t,
  required Prefs prefs,
  required Recipe recipe,
  required bool scanning,

  /// Команда ушла, машина ещё не подтвердила: на кнопке крутится ожидание.
  bool ctaBusy = false,
}) {
  // Пока будильник заведён, машину запустит он — и режимом распорядится тоже
  // он. Показываем то, что действительно случится.
  final armed = d.appointment.enabled;
  final mode = armed ? d.appointment.mode.asWorkMode : prefs.runMode;
  final model = buildPipeline(
    d: d,
    t: t,
    recipe: recipe,
    mode: mode,
    fahrenheit: prefs.fahrenheit,
    editable: d.isConnected && !d.isBusy && !armed,
  );
  final accent = WatchPalette.modeAccent[mode]!;
  final status = d.status;

  return {
    'v': kWatchContractVersion,
    'link': d.link.name,
    'scanning': scanning,
    'accent': accent,
    'accentText': WatchPalette.modeText[mode]!,
    'devices': _devices(t, d, prefs),
    'device': d.isConnected
        ? {
            'id': d.connectedId,
            'name': prefs.deviceName,
            // Делений на корпусе машины четыре — столько же и здесь.
            'battery': status?.batteryLevel,
            'batteryPercent': status == null
                ? null
                : (status.batteryLevel * 100 / 4).round(),
            'charging': status?.charge == ChargeState.charging,
            'state': status?.state.label(t),
            'running': d.isBusy,
            'model': d.info?.model,
            'error': d.lastFault == MachineError.none
                ? null
                : d.lastFault.label(t),
          }
        : null,
    'steps': _rows(t, model, accent, mode),
    'modes': [
      for (final m in const [
        WorkMode.heat,
        WorkMode.heatAndBrew,
        WorkMode.brew,
      ])
        {
          'value': m.code,
          'label': m.label(t),
          'icon': _modeIcon(m),
          'accent': WatchPalette.modeAccent[m]!,
          'accentText': WatchPalette.modeText[m]!,
          'selected': m == mode,
        },
    ],
    'cta': _cta(t, model, accent, ctaBusy),
    'strings': _strings(t),
  };
}

/// Шаги пролива на часах не занимают по строке каждый.
///
/// На 45 мм четыре отдельных ряда съедали экран целиком, а настраивают они
/// одно и то же — пролив. Поэтому наверху остаётся «Пролив» одной строкой, а
/// его составляющие живут на своём экране, как лист пролива на телефоне.
const Set<StepId> _pourGroup = {
  StepId.wetting,
  StepId.pause,
  StepId.extraction,
  StepId.flow,
};

/// Верхний уровень пайплайна: таймер, режим, нагрев и пролив.
List<Map<String, Object?>> _rows(
  AppL10n t,
  PipelineModel model,
  String accent,
  WorkMode mode,
) {
  final rows = <Map<String, Object?>>[];
  final pour = <PipelineStep>[];

  for (final s in model.steps) {
    if (_pourGroup.contains(s.id)) {
      pour.add(s);
    } else {
      rows.add(_step(t, s, accent, mode));
    }
  }
  if (pour.isEmpty) return rows;

  // Пока идёт цикл, свёрнутая строка показывает тот шаг, который сейчас
  // работает: иначе о ходе пролива с часов ничего не узнать.
  PipelineStep? live;
  for (final s in pour) {
    if (s.mark == StepMark.active) {
      live = s;
      break;
    }
  }
  final seconds = pour
      .where((s) => s.unit == t.secondsUnit)
      .fold<int>(0, (sum, s) => sum + s.editValue);

  rows.add({
    ..._step(
      t,
      PipelineStep(
        id: StepId.extraction,
        label: live?.label ?? t.pourTitle,
        value: live?.value ?? t.seconds(seconds),
        tone: StepTone.amber,
        mark: live?.mark ?? pour.first.mark,
        progress: live?.progress,
        editor: EditorKind.stepper,
        editable: pour.any((s) => s.editable),
      ),
      accent,
      mode,
    ),
    'id': 'pour',
    'icon': 'streams',
    'editor': 'group',
    'children': [for (final s in pour) _step(t, s, accent, mode)],
  });
  return rows;
}

/// Список машин для часов.
///
/// Строится из того, что телефон ЗНАЕТ, а не из того, что видит эфир прямо
/// сейчас. Раньше здесь были только результаты сканирования — и как только
/// скан заканчивался, список на часах пустел, хотя машина оставалась
/// подключённой. Часы — проекция приложения, а в приложении своя машина никуда
/// не девается.
///
/// Порядок: сначала своя (подключённая или последняя известная), потом всё
/// остальное, что нашлось в эфире.
List<Map<String, Object?>> _devices(AppL10n t, K2Device d, Prefs prefs) {
  final rows = <Map<String, Object?>>[];
  final seen = <String>{};
  final status = d.status;

  final mine = d.connectedId ?? prefs.lastDeviceId;
  if (mine != null) {
    seen.add(mine);
    final here = d.isConnected && d.connectedId == mine;
    rows.add({
      'id': mine,
      // Своя машина зовётся так, как её назвал хозяин, а не как она
      // представляется в эфире.
      'name': prefs.deviceName,
      'rssi': null,
      'connected': here,
      'known': true,
      'status': here
          ? t.deviceConnected
          : d.link == LinkState.connecting
          ? t.connecting
          : d.discovered.any((e) => e.id == mine)
          ? t.deviceAvailable
          : t.notConnected,
      'battery': here ? status?.batteryLevel : null,
      'batteryPercent': here && status != null
          ? (status.batteryLevel * 100 / 4).round()
          : null,
      'charging': here && status?.charge == ChargeState.charging,
    });
  }

  for (final e in d.discovered) {
    if (!seen.add(e.id)) continue;
    rows.add({
      'id': e.id,
      'name': e.advertisedName,
      'rssi': e.rssi,
      'connected': false,
      'known': false,
      'status': t.deviceAvailable,
      'battery': null,
      'batteryPercent': null,
      'charging': false,
    });
  }
  return rows;
}

Map<String, Object?> _step(
  AppL10n t,
  PipelineStep s,
  String accent,
  WorkMode mode,
) => {
  'id': s.id.name,
  'icon': s.id == StepId.mode ? _modeIcon(mode) : _icon(s.id),
  'label': s.label.toUpperCase(),
  'value': s.value,
  'tone': switch (s.tone) {
    StepTone.heat => WatchPalette.heat,
    StepTone.water => WatchPalette.water,
    StepTone.amber => WatchPalette.amber,
    StepTone.mode => WatchPalette.modeText[mode]!,
  },
  'mark': s.mark.name,
  'progress': s.progress,
  // Взведённый таймер подсвечен весь: это не фаза, а состояние ряда.
  'highlighted': s.id == StepId.alarm && s.mark != StepMark.upcoming,
  'editable': s.editable,
  'editor': s.editor.name,
  'editValue': s.editValue,
  'min': s.min,
  'max': s.max,
  'step': s.step,
  'unit': s.unit,
  'hint': s.hint,
};

Map<String, Object?> _cta(
  AppL10n t,
  PipelineModel m,
  String accent,
  bool busy,
) {
  final (label, bg, fg) = switch (m.cta) {
    CtaKind.connect => (t.connect, accent, WatchPalette.onAccent),
    CtaKind.start => (t.ctaStart, accent, WatchPalette.onAccent),
    CtaKind.stop => (t.ctaStop, WatchPalette.danger, WatchPalette.onDanger),
    CtaKind.cancelAlarm => (
      t.cancelAlarm,
      WatchPalette.danger,
      WatchPalette.onDanger,
    ),
    CtaKind.done => (t.ctaDone, WatchPalette.success, WatchPalette.onSuccess),
  };
  return {
    'kind': m.cta.name,
    'label': label,
    'bg': bg,
    'fg': fg,
    // «Готово» и «Подключиться» ничего не ждут — крутить там нечего.
    'busy': busy && (m.cta == CtaKind.start || m.cta == CtaKind.stop),
  };
}

/// Подписи, которые часы рисуют сами. Они же кэшируются на той стороне: когда
/// телефон недоступен, сказать об этом надо на языке пользователя, а спросить
/// уже не у кого.
Map<String, Object?> _strings(AppL10n t) => {
  'machines': t.machines,
  'searching': t.searching,
  'noPhone': t.notConnected,
  'connected': t.deviceConnected,
  'timer': t.stepAlarm,
  'timerOff': t.timerOff,
  'mode': t.runMode,
  'enable': t.scheduleEnabled,
  'disable': t.cancel,
  'connecting': t.connecting,
  'empty': t.searchNearby,
};

String _icon(StepId id) => switch (id) {
  StepId.alarm => 'alarm',
  StepId.mode => 'coil',
  StepId.heat => 'coil',
  StepId.wetting => 'droplet',
  StepId.pause => 'pause',
  StepId.extraction => 'streams',
  StepId.flow => 'speedometer',
};

String _modeIcon(WorkMode m) => switch (m) {
  WorkMode.heat => 'coil',
  WorkMode.heatAndBrew => 'heatbrew',
  WorkMode.brew => 'droplet',
};
