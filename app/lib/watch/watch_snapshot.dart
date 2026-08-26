import '../ble/k2_device.dart';
import '../ble/protocol.dart';
import '../ble/scale/scale_device.dart';
import '../ble/transport.dart';
import '../l10n/app_l10n.dart';
import '../l10n/l10n_ext.dart';
import '../model/gravimetry.dart';
import '../model/pipeline.dart';
import '../model/recipe.dart';
import '../store/prefs.dart';

/// Версия контракта. Часы отказываются рисовать снимок с чужим номером —
/// лучше честное «обновите приложение», чем экран с перепутанными полями.
///
/// 2 — появились весы: у устройства в списке завёлся род, у снимка раздел
/// `scale`, а у пайплайна ряд веса.
/// 3 — таймер стал таймером готовности: у снимка завёлся раздел `timer` с
/// пресетами «готов через N» и живым отсчётом.
const int kWatchContractVersion = 3;

/// Пресеты готовности: через сколько минут кофе должен стоять в чашке. Одна с
/// парой минут смысла не имеют — столько машина сама тратит на выход; тридцать
/// — разумный потолок для «пока готовлю завтрак». Один в один с телефоном.
const List<int> kWatchTimerPresets = [5, 10, 20, 30];

/// Насколько заранее машина стартует под режим с нагревом, чтобы к сроку кофе
/// уже был готов. Пролив известен из рецепта до секунды, а время нагрева
/// машина не сообщает — это оценка, намеренно скромная: лучше кофе выйдет на
/// минуту раньше и подождёт, чем человек вернётся к пустой чашке.
///
/// Это число живёт и в листе таймера на телефоне. Держать общий источник
/// нельзя: тот лист — слой интерфейса, а часам сюда тянуться запрещено. Оценка
/// грубая, и её расхождение на десяток секунд ни на что не влияет.
const int kWatchHeatEstimateSeconds = 150;

/// Сколько длится цикл выбранного режима — то, что вычитается из срока
/// готовности, чтобы получить момент старта.
int watchCycleSeconds(Recipe r, WorkMode mode) {
  final brew = r.preInfusionSeconds + r.standstillSeconds + r.extractionSeconds;
  return switch (mode) {
    WorkMode.heat => kWatchHeatEstimateSeconds,
    WorkMode.heatAndBrew => kWatchHeatEstimateSeconds + brew,
    WorkMode.brew => brew,
  };
}

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
  required ScaleDevice scale,
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

  // Абсолютные границы текущей фазы цикла.
  //
  return {
    'v': kWatchContractVersion,
    // Когда снимок собран. Часы могут достать его из хранилища системы спустя
    // час — по этой метке они поймут, что числам верить уже нельзя. Своё
    // «сейчас» для этого не годится: часы не знают, откуда снимок приехал.
    'at': DateTime.now().millisecondsSinceEpoch,
    'link': d.link.name,
    'scanning': scanning,
    'accent': accent,
    'accentText': WatchPalette.modeText[mode]!,
    'devices': _devices(t, d, scale, prefs),
    'device': d.isConnected
        ? {
            'id': d.connectedId,
            'name': prefs.deviceName,
            // Делений на корпусе машины четыре — столько же и здесь.
            'battery': status?.batteryLevel,
            // Проценты из четырёх корзин были ложной точностью.
            'batteryPercent': null,
            'charging': status?.charge == ChargeState.charging,
            'state': status?.state.label(t),
            'running': d.isBusy,
            'model': d.info?.model,
            'error': d.lastFault == MachineError.none
                ? null
                : d.lastFault.label(t),
          }
        : null,
    'scale': _scale(t, d, scale, prefs),
    'steps': _rows(t, model, accent, mode, _weight(t, d, scale, prefs)),
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
    'timer': _timer(t, d, recipe, prefs.runMode),
    'strings': _strings(t),
  };
}

String _two(int v) => v.toString().padLeft(2, '0');
String _hhmm(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}';

/// Таймер готовности для часов.
///
/// Главное — пресеты «готов через N минут»: тапнул — и пошёл отсчёт. Внутри
/// протокола это по-прежнему будильник по часам суток, «через N» считается на
/// телефоне (см. [WatchBridge]), а сюда уезжает уже результат: взведён ли,
/// сколько осталось и к какому часу всё будет.
///
/// Подписи с подстановками (`Старт в 07:20`) собираются здесь, готовой
/// строкой: на часах локализации нет, только отрисовка.
Map<String, Object?> _timer(
  AppL10n t,
  K2Device d,
  Recipe recipe,
  WorkMode runMode,
) {
  final a = d.appointment;
  final armed = a.enabled;
  final mode = armed ? a.mode.asWorkMode : runMode;
  final now = d.currentTime;

  // Ближайшее наступление часа:минуты будильника.
  final today = DateTime(now.year, now.month, now.day, a.hour, a.minute);
  final start = today.isAfter(now) ? today : today.add(const Duration(days: 1));
  final readyAt = start.add(Duration(seconds: watchCycleSeconds(recipe, mode)));

  return {
    'armed': armed,
    'presets': kWatchTimerPresets,
    // «мин» под крупным числом пресета.
    'presetUnit': t.minutesShort,
    'hint': t.timerReadyHint,
    // Минуты от полуночи для колёс «своё время».
    'byTime': a.hour * 60 + a.minute,
    'readyLabel': t.timerReadyIn,
    // Живой остаток и час готовности — только когда взведено. На часах отсчёт
    // тикает сам от этого числа: телефон, пока машина ждёт, снимок не шлёт.
    'readyInSeconds': armed
        ? readyAt.difference(now).inSeconds.clamp(0, 24 * 3600)
        : null,
    'startLine': armed
        ? '${t.timerStartAt(_hhmm(start))} · ${mode.label(t)}'
        : null,
    'cancel': t.cancelAlarm,
    'enable': t.enable,
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

/// Верхний уровень пайплайна: таймер, режим, нагрев, пролив и вес.
///
/// [weight] приходит готовым и снаружи: веса нет в [PipelineModel] и быть не
/// должно — машина о нём не знает, уставка в неё не уезжает, а фаз у него нет.
/// Это ряд приборный, а не машинный, и живёт он последним, как на телефоне.
List<Map<String, Object?>> _rows(
  AppL10n t,
  PipelineModel model,
  String accent,
  WorkMode mode,
  Map<String, Object?>? weight,
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
  if (pour.isEmpty) {
    if (weight != null) rows.add(weight);
    return rows;
  }

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
  if (weight != null) rows.add(weight);
  return rows;
}

/// Список устройств для часов: машина и весы в одном столбце.
///
/// Строится из того, что телефон ЗНАЕТ, а не из того, что видит эфир прямо
/// сейчас. Раньше здесь были только результаты сканирования — и как только
/// скан заканчивался, список на часах пустел, хотя машина оставалась
/// подключённой. Часы — проекция приложения, а в приложении своя машина никуда
/// не девается.
///
/// Порядок: сначала свои (подключённые или последние известные), потом всё
/// остальное, что нашлось в эфире. Машина идёт раньше весов: за ней приходят
/// чаще, и она же открывает главный экран.
List<Map<String, Object?>> _devices(
  AppL10n t,
  K2Device d,
  ScaleDevice scale,
  Prefs prefs,
) {
  final rows = <Map<String, Object?>>[];
  final seen = <String>{};
  final status = d.status;

  final mine = d.connectedId ?? prefs.lastDeviceId;
  if (mine != null) {
    seen.add(mine);
    final here = d.isConnected && d.connectedId == mine;
    rows.add({
      'id': mine,
      'kind': 'machine',
      // Своя машина зовётся так, как её назвал хозяин, а не как она
      // представляется в эфире.
      'name': prefs.deviceName,
      'rssi': null,
      'connected': here,
      'known': true,
      'status': here
          ? t.deviceConnected
          : d.isSeeking
          ? t.connecting
          : d.discovered.any((e) => e.id == mine)
          ? t.deviceAvailable
          : t.notConnected,
      'battery': here ? status?.batteryLevel : null,
      'batteryPercent': null,
      'charging': here && status?.charge == ChargeState.charging,
    });
  }

  final myScale = scale.connectedId ?? prefs.lastScaleId;
  if (myScale != null) {
    seen.add(myScale);
    final here = scale.isConnected && scale.connectedId == myScale;
    rows.add({
      'id': myScale,
      'kind': 'scale',
      'name': prefs.scaleName,
      'rssi': null,
      'connected': here,
      'known': true,
      'status': _scaleStatus(t, d, scale, myScale),
      // Весы отдают процент, а не деления: рисуем его числом, без шкалы.
      'battery': null,
      'batteryPercent': here ? scale.batteryPercent : null,
      'charging': false,
    });
  }

  for (final e in d.discovered) {
    if (!seen.add(e.id)) continue;
    // Посторонняя мелочь в эфире часам не нужна: подключаться к ней некуда.
    final kind = switch (e.kind) {
      DeviceKind.machine => 'machine',
      DeviceKind.scale => 'scale',
      DeviceKind.other => null,
    };
    if (kind == null) continue;
    rows.add({
      'id': e.id,
      'kind': kind,
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

/// Одной строкой: где сейчас весы.
///
/// «Спят» — не поломка: весы гасятся по своему таймауту, линия при этом
/// остаётся, и разбудить их можно только с кнопки на самих весах. Сказать об
/// этом честно дешевле, чем показывать залипшее число как живое.
String _scaleStatus(AppL10n t, K2Device d, ScaleDevice scale, String id) {
  if (scale.isLive) return t.deviceConnected;
  if (scale.isAsleep) return t.scaleAsleep;
  if (scale.isConnected || scale.isSeeking) return t.connecting;
  return d.discovered.any((e) => e.id == id)
      ? t.deviceAvailable
      : t.notConnected;
}

/// Весы как прибор: то, ради чего на часах открывают их экран.
///
/// null — весов телефон не знает вовсе: ни подключённых, ни запомненных. Тогда
/// на часах нет ни строки в списке, ни ряда веса.
Map<String, Object?>? _scale(
  AppL10n t,
  K2Device d,
  ScaleDevice scale,
  Prefs prefs,
) {
  final id = scale.connectedId ?? prefs.lastScaleId;
  if (id == null) return null;
  final g = prefs.gravimetry;
  return {
    'id': id,
    'name': prefs.scaleName,
    'connected': scale.isConnected,
    // Верить числу можно только здесь: `connected` значит лишь, что линия
    // есть, а отсчёты могли и кончиться.
    'live': scale.isLive,
    'asleep': scale.isAsleep,
    'status': _scaleStatus(t, d, scale, id),
    'grams': scale.isLive ? _g(scale.grams) : null,
    'unit': t.gramsUnit,
    'batteryPercent': scale.isConnected ? scale.batteryPercent : null,
    'target': _g(g.targetG),
    'stopOnYield': g.stopOnYield,
    // Переключать отсечку имеет смысл, только когда есть чем мерить и машина
    // не в работе: уставок на ходу она не принимает.
    'canAutoStop': scale.isLive && !d.isBusy,
    'tareEnabled': scale.isLive,
  };
}

/// Ряд веса в пайплайне.
///
/// Появляется вместе с весами и ровно по тому же правилу, что на телефоне: не
/// «включена отсечка», а «весы есть». Показывать цель, которую нечем измерить,
/// значит обещать несделанное.
///
/// Два лица у ряда те же. По времени — живой вес и приглушённый тон: весы
/// смотрят со стороны и в цикл не вмешиваются. По весу — «набрано из цели»,
/// цвет воды и кольцо: пролив кончится здесь.
Map<String, Object?>? _weight(
  AppL10n t,
  K2Device d,
  ScaleDevice scale,
  Prefs prefs,
) {
  if (!scale.isConnected) return null;
  final g = prefs.gravimetry;
  final auto = g.stopOnYield && scale.isLive;
  final running = d.isBusy;
  final fraction = g.targetG <= 0
      ? 0.0
      : (scale.grams / g.targetG).clamp(0.0, 1.0);

  return {
    'id': 'weight',
    'icon': 'scale',
    'label': t.stepWeight.toUpperCase(),
    'value': !scale.isLive
        ? t.scaleAsleep
        : auto
        ? (running
              ? t.weightOf(_g(scale.grams), _g(g.targetG))
              : t.weightGrams(_g(g.targetG)))
        : t.weightGrams(_g(scale.grams)),
    'tone': auto ? WatchPalette.water : WatchPalette.amber,
    // В очереди фаз вес не участвует: у машины такой фазы нет, и «пройдено»
    // ему взяться неоткуда. Пока отсечка выключена, ряд и вовсе только
    // показывает.
    'mark': auto && running ? 'active' : 'upcoming',
    'progress': auto && running ? fraction : null,
    'highlighted': auto,
    // Уставку веса машина не хранит, поэтому её можно править и на ходу —
    // в отличие от всего остального в пайплайне.
    'editable': true,
    'editor': 'weight',
    // Десятые доли грамма целым числом: у часов один редактор на все шаги, и
    // дробей он не знает. `decimals` говорит ему, где поставить запятую.
    'editValue': (g.targetG * 10).round(),
    'min': (kYieldMin * 10).round(),
    'max': (kYieldMax * 10).round(),
    'step': (kYieldStep * 10).round(),
    'decimals': 1,
    'unit': t.gramsUnit,
    'hint': t.descYield,
  };
}

String _g(double v) => v.toStringAsFixed(1);

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
    CtaKind.start => (
      // На часах манеру нажатия показывает сам орган — ручка слева и ход
      // вправо, — а не подпись: «удерживайте для запуска» в капсулу на 41 мм
      // не влезает и обрывается на полуслове. Режим тут же, рядом, строкой
      // выше, поэтому в подписи хватает одного глагола.
      m.mode == WorkMode.brew ? t.startMode(m.mode.label(t)) : t.ctaStart,
      accent,
      WatchPalette.onAccent,
    ),
    CtaKind.stop => (t.ctaStop, WatchPalette.danger, WatchPalette.onDanger),
    CtaKind.cancelAlarm => (
      t.cancelAlarm,
      WatchPalette.danger,
      WatchPalette.onDanger,
    ),
    CtaKind.done => (t.ctaDone, WatchPalette.success, WatchPalette.onSuccess),
    CtaKind.blocked => (
      m.blockingFault.action(t),
      WatchPalette.danger,
      WatchPalette.onDanger,
    ),
  };
  return {
    'kind': m.cta.name,
    'label': label,
    'bg': bg,
    'fg': fg,
    // «Готово» и «Подключиться» ничего не ждут — крутить там нечего.
    'busy': busy && (m.cta == CtaKind.start || m.cta == CtaKind.stop),
    // Намеренный жест: часы рисуют под этим флагом сдвиг вместо касания.
    //
    // И на пуске, и на остановке. Остановку сперва оставили касанием — из
    // опасения запереть человека наедине с работающим кипятильником, — но на
    // запястье её оказалось слишком легко задеть рукавом, а сорванный посреди
    // экстракции пролив уже не вернуть. Запереть при этом не выйдет: под
    // ожиданием часы возвращают обычную кнопку, и второй «Стоп» — просто
    // касание.
    'hold':
        (m.cta == CtaKind.start && m.mode != WorkMode.brew) ||
        m.cta == CtaKind.stop,
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
  'timer': t.timer,
  'timerOff': t.timerOff,
  'byTime': t.timerByTime,
  // Подписи над колёсами времени: «10 : 30» с двоеточиями на часах
  // читалось так, будто у минут отрезали секунды.
  'hours': t.hoursShort,
  'minutes': t.minutesShort,
  'mode': t.runMode,
  'enable': t.scheduleEnabled,
  'disable': t.cancel,
  'connecting': t.connecting,
  'empty': t.searchNearby,
  'scale': t.weightTitle,
  'tare': t.weightTare,
  'weight': t.stepWeight,
  'target': t.weightTarget,
  'autoStop': t.weightStopByWeight,
  'noScale': t.weightNotConnected,
  'asleep': t.scaleAsleep,
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
