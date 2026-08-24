import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../ble/k2_device.dart';
import '../ble/protocol.dart';
import '../ble/trace.dart';
import '../ble/transport.dart';
import '../l10n/app_l10n.dart';
import '../l10n/l10n_ext.dart';
import '../model/brew_phase.dart';
import '../model/pipeline.dart' as pipe;
import '../model/recipe.dart';
import '../store/prefs.dart';
import '../store/recipe_editor.dart';
import 'scan_sheet.dart';
import 'scene/machine_scene.dart';
import 'scene/scene_state.dart';
import 'sheets/device_sheet.dart';
import 'sheets/mode_sheet.dart';
import 'sheets/pour_sheet.dart';
import 'sheets/temperature_sheet.dart';
import 'sheets/timer_sheet.dart';
import 'theme.dart';
import 'widgets/bottom_bar.dart';
import 'widgets/cycle_timeline.dart';
import 'widgets/k_icons.dart';
import 'widgets/phase_aura.dart';
import 'widgets/top_bar.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.device,
    required this.prefs,
    this.editor,
  });

  final K2Device device;
  final Prefs prefs;

  /// Общий с часами редактор уставок. null — экран заводит свой: так удобнее
  /// тестам, где часов нет.
  final RecipeEditor? editor;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _autoConnectTried = false;

  /// Уставки, набранные локально, пока запись ещё не ушла в машину. Общие с
  /// часами: крутить одно и то же число могут и там, и здесь.
  late final RecipeEditor _editor;
  late final bool _ownsEditor;

  /// Пуск или остановка отправлены, но машина ещё не отчиталась о смене
  /// состояния: на кнопке крутится спиннер, иначе тап выглядит потерянным.
  bool? _awaitingBusy;
  Timer? _awaitTimeout;

  /// «Готово ✓» на кнопке. Машина держит состояние «готово» до следующей
  /// команды, а зелёная кнопка — это итог цикла: через три секунды она
  /// возвращается в обычный пуск.
  bool _doneBadge = false;
  bool _doneSeen = false;
  Timer? _doneTimer;

  @override
  void initState() {
    super.initState();
    _ownsEditor = widget.editor == null;
    _editor =
        widget.editor ??
        RecipeEditor(device: widget.device, prefs: widget.prefs);
    widget.device.addListener(_syncAwaiting);
    widget.device.addListener(_syncDone);
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoConnect());
  }

  @override
  void dispose() {
    widget.device.removeListener(_syncAwaiting);
    widget.device.removeListener(_syncDone);
    if (_ownsEditor) _editor.dispose();
    _awaitTimeout?.cancel();
    _doneTimer?.cancel();
    super.dispose();
  }

  /// Подхватываем машину, к которой подключались в прошлый раз, без клика.
  Future<void> _autoConnect() async {
    final id = widget.prefs.lastDeviceId;
    if (id == null || _autoConnectTried) return;
    _autoConnectTried = true;
    Trace.instance.ui('автоподключение к $id');

    final d = widget.device;
    final done = Completer<void>();
    void check() {
      if (done.isCompleted) return;
      if (d.discovered.any((x) => x.id == id)) done.complete();
    }

    d.addListener(check);
    try {
      await d.startScan();
      await done.future.timeout(const Duration(seconds: 12));
      await d.stopScan();
      await d.connect(id);
      widget.prefs.remember(id, widget.prefs.nameOf(id) ?? '');
    } catch (e) {
      // Машины нет в эфире — пользователь откроет список сам.
      Trace.instance.ui('автоподключение не вышло: $e');
      await d.stopScan();
    } finally {
      d.removeListener(check);
    }
  }

  // ---- уставки ----------------------------------------------------------

  /// Состояние сцены из телеметрии. Настоящие данные — фаза и её доля; уровень
  /// воды в баке сцена показывает декоративно.
  SceneState _sceneOf(K2Device d) {
    final p = d.progress;
    return SceneState(
      connected: d.isConnected,
      phase: p.phase,
      phaseFraction: p.fraction ?? 0,
      cupFill: switch (p.phase) {
        BrewPhase.extraction => p.fraction ?? 0,
        BrewPhase.done => 1,
        _ => 0,
      },
      live: d.isBusy,
      mode: _runningMode(d),
    );
  }

  /// Каким режимом машина занята на самом деле. Своё состояние она сообщает
  /// сама, и это надёжнее выбранного в интерфейсе: пока цикл идёт, кнопку
  /// режима никто не держит, а сцене важно знать, будет ли вообще пролив.
  WorkMode _runningMode(K2Device d) => switch (d.status?.state) {
    MachineState.heating || MachineState.heatDone => WorkMode.heat,
    MachineState.brewing || MachineState.brewDone => WorkMode.brew,
    MachineState.heatBrewing ||
    MachineState.heatBrewDone => WorkMode.heatAndBrew,
    _ => widget.prefs.runMode,
  };

  /// Запуск в выбранном режиме. Параметры уже лежат в машине, досылать нечего.
  Future<void> _run(WorkMode mode) => _start(mode, switch (mode) {
    WorkMode.heatAndBrew => widget.device.heatAndBrew,
    WorkMode.heat => widget.device.heat,
    WorkMode.brew => widget.device.brew,
  });

  /// После осознанного нажатия проверяем только то, что нельзя выразить
  /// самой кнопкой: хватит ли заряда на нагрев. Удержание от случайного
  /// запуска реализовано в CTA, а холодный пролив остаётся быстрым тапом.
  Future<void> _requestStart(WorkMode mode) async {
    final d = widget.device;
    final needsHeat = mode != WorkMode.brew;
    final batteryLow = (d.status?.batteryLevel ?? 4) <= 1;
    if (needsHeat && batteryLow) {
      final t = context.t;
      final proceed = await showGlassDialog<bool>(
        context,
        title: t.lowBatteryStartTitle,
        message: t.lowBatteryStartBody,
        actions: [
          KDialogButton(
            label: t.cancel,
            onTap: () => Navigator.pop(context, false),
          ),
          KDialogButton(
            label: t.startAnyway,
            danger: true,
            onTap: () => Navigator.pop(context, true),
          ),
        ],
      );
      if (proceed != true || !mounted) return;
    }
    _awaitBusy(true);
    unawaited(_run(mode));
  }

  /// Меню машины: гамбургер и тап по имени ведут сюда же.
  Future<void> _openDeviceMenu(BuildContext context) async {
    final d = widget.device;
    final action = await showDeviceSheet(
      context,
      device: d,
      prefs: widget.prefs,
      recipe: _editor.active,
    );
    if (!context.mounted || action == null) return;
    switch (action) {
      case DeviceAction.rename:
        await _rename(context);
      case DeviceAction.choose:
        await _openScan(context);
      case DeviceAction.forget:
        await _forget(context);
      case DeviceAction.factoryReset:
        await _confirmReset(context);
      case DeviceAction.language:
        await showLanguageSheet(context, widget.prefs);
      case DeviceAction.disconnect:
        await d.disconnect();
    }
  }

  /// Сброс машины к заводским — необратимо, поэтому спрашиваем.
  Future<void> _confirmReset(BuildContext context) async {
    final t = context.t;
    final ok = await showGlassDialog<bool>(
      context,
      title: t.restoreDefaultsQuestion,
      message: t.restoreDefaultsBody,
      actions: [
        KDialogButton(
          label: t.cancel,
          onTap: () => Navigator.pop(context, false),
        ),
        KDialogButton(
          label: t.reset,
          danger: true,
          onTap: () => Navigator.pop(context, true),
        ),
      ],
    );
    if (ok ?? false) await widget.device.resetToDefaults();
  }

  Future<void> _rename(BuildContext context) async {
    final t = context.t;
    final c = TextEditingController(text: widget.prefs.deviceName);
    final name = await showGlassDialog<String>(
      context,
      title: t.deviceNameTitle,
      content: TextField(
        controller: c,
        autofocus: true,
        style: const TextStyle(color: K.text, fontSize: 15),
        cursorColor: K.amber,
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 12,
          ),
          filled: true,
          fillColor: K.glassFill,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: K.glassBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: K.amber.withValues(alpha: 0.6)),
          ),
        ),
      ),
      actions: [
        KDialogButton(label: t.cancel, onTap: () => Navigator.pop(context)),
        KDialogButton(
          label: t.save,
          onTap: () => Navigator.pop(context, c.text.trim()),
        ),
      ],
    );
    if (name != null && name.isNotEmpty) widget.prefs.deviceName = name;
  }

  /// Ждать подтверждения от машины. Таймаут нужен: команда может потеряться,
  /// и вечный спиннер был бы хуже, чем просто неотработавшая кнопка.
  void _awaitBusy(bool expected) {
    Trace.instance.ui('жду от машины isBusy=$expected');
    setState(() => _awaitingBusy = expected);
    _awaitTimeout?.cancel();
    _awaitTimeout = Timer(const Duration(seconds: 8), () {
      Trace.instance.ui('ожидание сорвалось: машина не подтвердила за 8 с');
      if (mounted) setState(() => _awaitingBusy = null);
    });
  }

  void _syncAwaiting() {
    final want = _awaitingBusy;
    if (want == null || widget.device.isBusy != want) return;
    Trace.instance.ui('машина подтвердила isBusy=$want, экран разблокирован');
    _awaitTimeout?.cancel();
    setState(() => _awaitingBusy = null);
  }

  /// Зелёное «Готово ✓» живёт ровно три секунды на цикл.
  void _syncDone() {
    final done = widget.device.status?.state.isDone ?? false;
    if (!done) {
      if (!_doneSeen && !_doneBadge) return;
      _doneTimer?.cancel();
      _doneTimer = null;
      setState(() {
        _doneSeen = false;
        _doneBadge = false;
      });
      return;
    }
    if (_doneSeen) return;
    _doneSeen = true;
    setState(() => _doneBadge = true);
    _doneTimer = Timer(const Duration(seconds: 3), () {
      _doneTimer = null;
      if (mounted) setState(() => _doneBadge = false);
    });
  }

  /// Любой запуск: сначала записать уставки, потом пускать.
  ///
  /// Пишем всегда, а не только когда правка не успела уехать. Совпадение
  /// экрана с машиной гарантировано лишь после её ответа; когда она отмолчала
  /// рукопожатие, на экране кэш прошлого сеанса — и что лежит в ней самой,
  /// неизвестно. Два лишних кадра дешевле неверного пролива.
  Future<void> _start(WorkMode mode, Future<void> Function() run) async {
    Trace.instance.ui('ТАП пуск: ${mode.name}');
    await _editor.push();
    if (!mounted) return;
    await run();
    Trace.instance.ui('пуск: кадр ушёл');
  }

  Future<void> _openTemperature(BuildContext context) async {
    Trace.instance.ui('шторка температуры открыта');
    final lim = widget.device.tempLimits;
    await showTemperatureSheet(
      context,
      celsius: _editor.active.temperatureC,
      min: lim.min,
      max: lim.max,
      fahrenheit: widget.prefs.fahrenheit,
      onChanged: (c) => _editor.edit(temperatureC: c),
    );
  }

  Future<void> _openPour(BuildContext context) async {
    Trace.instance.ui('шторка пролива открыта');
    await showPourSheet(
      context,
      recipe: _editor.active,
      params: widget.device.workParams,
      onChanged: (r) => _editor.edit(
        extractionSeconds: r.extractionSeconds,
        preInfusionSeconds: r.preInfusionSeconds,
        standstillSeconds: r.standstillSeconds,
        pressure: r.pressure,
      ),
    );
  }

  /// Режим — одно решение из трёх, поэтому лист, а не переключатель.
  Future<void> _openMode(BuildContext context) async {
    final d = widget.device;
    final a = d.appointment;
    // Пока таймер взведён, режимом распоряжается он: карточка показывает его
    // режим, и менять надо тоже его. Иначе выбор молча уходил в настройки, а
    // на экране ничего не менялось — выглядело так, будто карточка не
    // нажимается вовсе.
    final current = a.enabled ? a.mode.asWorkMode : widget.prefs.runMode;
    final m = await showModeSheet(context, selected: current);
    if (!mounted || m == null) return;
    if (a.enabled) {
      d.setSchedule(a.copyWith(mode: m.asScheduleMode), immediate: true);
    }
    widget.prefs.runMode = m;
  }

  Future<void> _openScan(BuildContext context) async {
    // Лист сам записывает машину в список — здесь ловить нечего.
    await showScanSheet(context, widget.device, widget.prefs);
  }

  /// Убрать машину из списка. Единственный способ это сделать — отсюда.
  Future<void> _forget(BuildContext context) async {
    final t = context.t;
    final target = await pickDeviceToForget(context, widget.prefs);
    if (target == null || !context.mounted) return;

    final ok = await showGlassDialog<bool>(
      context,
      title: t.forgetDeviceQuestion(target.name),
      message: t.forgetDeviceBody,
      actions: [
        KDialogButton(
          label: t.cancel,
          onTap: () => Navigator.pop(context, false),
        ),
        KDialogButton(
          label: t.forget,
          danger: true,
          onTap: () => Navigator.pop(context, true),
        ),
      ],
    );
    if (ok != true) return;
    if (widget.device.connectedId == target.id) {
      await widget.device.disconnect();
    }
    widget.prefs.forget(target.id);
  }

  // ---- экран ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([widget.device, widget.prefs, _editor]),
      builder: (context, _) {
        final t = context.t;
        final d = widget.device;
        final p = widget.prefs;
        final status = d.status;
        final recipe = _editor.active;
        final phase = d.progress.phase;
        final editable = d.isConnected && !d.isBusy;

        // Пока будильник заведён, машину запустит он — и режимом распорядится
        // тоже он. Таймлайн показывает то, что действительно случится.
        final armed = d.appointment.enabled;
        final mode = armed ? d.appointment.mode.asWorkMode : p.runMode;

        // SafeArea сама по себе сажает шапку вплотную к вырезу, а на экране
        // без выреза — вообще в самый край. Держим гарантированный воздух
        // сверху и снизу.
        final safe = MediaQuery.paddingOf(context);
        final topInset = math.max(safe.top, 20.0) + 8;
        final bottomInset = math.max(safe.bottom, 12.0);

        return Scaffold(
          body: AppBackground(
            // Пока машина работает, пятна фона подхватывают цвет фазы.
            tint: d.isBusy ? PhaseAura.solidOf(phase) : null,
            child: Padding(
              padding: EdgeInsets.only(top: topInset, bottom: bottomInset),
              child: Stack(
                children: [
                  // Зона машины: всё между шапкой и нижним рядом.
                  Positioned(
                    top: TopBar.height + 4,
                    left: 0,
                    right: 0,
                    bottom: BottomBar.height,
                    child: Stack(
                      children: [
                        // Аура стоит позади машины, а машина сдвинута вправо —
                        // левую треть занимает таймлайн.
                        Positioned.fill(
                          child: Padding(
                            padding: const EdgeInsets.only(left: _machineLeft),
                            child: PhaseAura(phase: phase, running: d.isBusy),
                          ),
                        ),
                        Positioned.fill(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(
                              _machineLeft,
                              14,
                              0,
                              14,
                            ),
                            child: Center(
                              // Машина занимает не весь отведённый прямоугольник:
                              // впритык к шапке и нижнему ряду она смотрелась
                              // тяжело, поэтому оставляем вокруг воздух.
                              child: FractionallySizedBox(
                                widthFactor: _machineScale,
                                heightFactor: _machineScale,
                                child: MachineScene(
                                  state: _sceneOf(d),
                                  accent: PhaseAura.solidOf(phase),
                                ),
                              ),
                            ),
                          ),
                        ),
                        // Таймлайн — колонка карточек по левому краю: он и
                        // статус, и настройки цикла разом.
                        Positioned(
                          left: _sideInset,
                          top: 0,
                          bottom: 0,
                          child: Center(
                            child: CycleTimeline(
                              steps: _steps(t, d, recipe, mode, editable),
                              running: d.isBusy,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Шапка.
                  Positioned(
                    top: 0,
                    left: _sideInset,
                    right: _sideInset,
                    child: TopBar(
                      name: p.deviceName,
                      connected: d.isConnected,
                      connecting: d.link == LinkState.connecting,
                      asleep: d.isAsleep,
                      status: status,
                      onMenu: () => _openDeviceMenu(context),
                      onName: () => _openDeviceMenu(context),
                      onLink: () => _openScan(context),
                    ),
                  ),

                  // Ошибка гаснет в телеметрии через пару пакетов, поэтому
                  // висит рядом с рядом кнопок, а не в прокручиваемой части.
                  if (d.lastFault != MachineError.none)
                    Positioned(
                      left: 10,
                      right: 10,
                      bottom: BottomBar.height,
                      child: _ErrorBanner(
                        error: d.lastFault,
                        at: d.lastFaultAt,
                        onDismiss: d.clearFault,
                      ),
                    ),

                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: BottomBar(cta: _cta(t, d, mode, armed)),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Отступ машины слева: под ним проходит колонка таймлайна.
  static const double _machineLeft = 56;

  /// Поля экрана по краям. Шапка и таймлайн начинаются от одной линии, иначе
  /// гамбургер и колонка карточек стоят с разным отступом и это видно.
  static const double _sideInset = 18;

  /// Сколько от своей зоны занимает машина.
  static const double _machineScale = 0.9;

  // ---- шаги цикла -------------------------------------------------------

  /// Из чего состоит цикл прямо сейчас. Состав шагов решает [pipe.buildPipeline]
  /// — тот же, что рисует пайплайн на часах. Здесь остаётся только перевод в
  /// карточки таймлайна: значки, цвета фаз и куда ведёт тап.
  ///
  /// Карточек всего четыре: таймер, режим, нагрев и пролив. Первые две — не
  /// шаги во времени, а условия прогона. Пролив собран из трёх фаз модели:
  /// пока он идёт, карточка по очереди показывает смачивание, паузу и
  /// экстракцию, а тап открывает лист, где все три и настраиваются.
  List<CycleStep> _steps(
    AppL10n t,
    K2Device d,
    Recipe recipe,
    WorkMode mode,
    bool editable,
  ) {
    final model = pipe.buildPipeline(
      d: d,
      t: t,
      recipe: recipe,
      mode: mode,
      fahrenheit: widget.prefs.fahrenheit,
      editable: editable,
    );

    final steps = <CycleStep>[];

    // 1. Таймер: он срабатывает раньше всего остального, поэтому и первый.
    final alarm = model.byId(pipe.StepId.alarm);
    if (alarm != null) {
      steps.add(
        CycleStep(
          kind: StepKind.alarm,
          // Когда запуск взведён, важнее всего не повторить слово «запуск»,
          // а сразу сказать, сегодня он произойдёт или уже завтра.
          label: (model.armed ? _scheduleDay(t, d) : alarm.label).toUpperCase(),
          value: alarm.value,
          icon: KIcon.alarm,
          tone: model.armed ? PhaseTone.amber : PhaseTone.muted,
          // Взведённое ожидание — шаг целиком: кольцо замкнуто.
          progress: model.armed ? 1 : null,
          mark: model.armed ? _markOf(alarm.mark) : StepMark.setting,
          onTap: alarm.editable
              ? () => showTimerSheet(context, d)
              : d.isConnected && !model.running
              ? () => showTimerSheet(context, d)
              : null,
        ),
      );
    }

    // 2. Режим: он решает, что будет ниже.
    final m = model.byId(pipe.StepId.mode);
    if (m != null) {
      steps.add(
        CycleStep(
          kind: StepKind.mode,
          label: m.label.toUpperCase(),
          // Полное «Нагрев + пролив» в карточку не лезет.
          value: _modeShort(t, model.mode),
          icon: _modeIcon(model.mode),
          tone: ModeStyle.of(model.mode).tone,
          mark: StepMark.setting,
          // Режим — единственная уставка, которая живёт в телефоне, а не в
          // машине: выбрать его можно и без связи. Заперт он только на ходу,
          // когда менять уже нечего.
          onTap: model.running ? null : () => _openMode(context),
        ),
      );
    }

    // 3. Нагрев — всюду, кроме холодного пролива.
    final heat = model.byId(pipe.StepId.heat);
    if (heat != null) {
      steps.add(
        CycleStep(
          kind: StepKind.heat,
          label: heat.label.toUpperCase(),
          value: heat.value,
          icon: KIcon.coil,
          tone: PhaseTone.heat,
          mark: _markOf(heat.mark),
          progress: heat.progress,
          onTap: heat.editable ? () => _openTemperature(context) : null,
        ),
      );
    }

    // 4. Пролив: три фазы модели в одной карточке.
    final pour = [
      for (final id in const [
        pipe.StepId.wetting,
        pipe.StepId.pause,
        pipe.StepId.extraction,
      ])
        ?model.byId(id),
    ];
    if (pour.isNotEmpty) {
      // Пока идёт одна из фаз, карточка показывает именно её: имя, время и
      // кольцо — её. В покое на ней стоит вся длина пролива.
      final live = pour
          .where((s) => s.mark == pipe.StepMark.active)
          .firstOrNull;
      final total =
          recipe.preInfusionSeconds +
          recipe.standstillSeconds +
          recipe.extractionSeconds;
      steps.add(
        CycleStep(
          kind: StepKind.pour,
          label: (live?.label ?? t.stepPour).toUpperCase(),
          value: live?.value ?? t.seconds(total),
          icon: live == null ? KIcon.streams : _iconOf(live.id),
          tone: live == null ? PhaseTone.amber : _toneOf(live.tone, model.mode),
          mark: live != null
              ? StepMark.active
              : pour.every((s) => s.mark == pipe.StepMark.passed)
              ? StepMark.passed
              : StepMark.upcoming,
          progress: live?.progress,
          onTap: pour.any((s) => s.editable) ? () => _openPour(context) : null,
        ),
      );
    }

    return steps;
  }

  KIcon _iconOf(pipe.StepId id) => switch (id) {
    pipe.StepId.alarm => KIcon.alarm,
    pipe.StepId.heat || pipe.StepId.mode => KIcon.coil,
    pipe.StepId.wetting => KIcon.droplet,
    pipe.StepId.pause => KIcon.pause,
    pipe.StepId.extraction => KIcon.streams,
    pipe.StepId.flow => KIcon.speedometer,
  };

  PhaseTone _toneOf(pipe.StepTone tone, WorkMode mode) => switch (tone) {
    pipe.StepTone.heat => PhaseTone.heat,
    pipe.StepTone.water => PhaseTone.water,
    pipe.StepTone.amber || pipe.StepTone.mode => PhaseTone.amber,
  };

  StepMark _markOf(pipe.StepMark mark) => switch (mark) {
    pipe.StepMark.upcoming => StepMark.upcoming,
    pipe.StepMark.active => StepMark.active,
    pipe.StepMark.passed => StepMark.passed,
    pipe.StepMark.error => StepMark.error,
  };

  /// Короткое имя режима: полное «Нагрев + пролив» в карточку не лезет.
  static String _modeShort(AppL10n t, WorkMode mode) => switch (mode) {
    WorkMode.heat => t.modeHeatShort,
    WorkMode.heatAndBrew => t.modeFullShort,
    WorkMode.brew => t.modeBrewShort,
  };

  static String _scheduleDay(AppL10n t, K2Device d) {
    final at = d.scheduledAt;
    if (at == null) return t.stepAlarm;
    final now = d.currentTime;
    final sameDay =
        at.year == now.year && at.month == now.month && at.day == now.day;
    return sameDay ? t.scheduleToday : t.scheduleTomorrow;
  }

  static KIcon _modeIcon(WorkMode mode) => switch (mode) {
    WorkMode.heat => KIcon.coil,
    WorkMode.heatAndBrew => KIcon.heatBrew,
    WorkMode.brew => KIcon.droplet,
  };

  /// Главная кнопка: подключиться, снять таймер, старт, стоп или «готово».
  BarCta _cta(AppL10n t, K2Device d, WorkMode mode, bool armed) {
    if (!d.isConnected) {
      final busy = d.link == LinkState.connecting;
      return BarCta(
        kind: CtaKind.connect,
        label: t.connect,
        mode: mode,
        busy: busy,
        onTap: busy ? null : () => _openScan(context),
      );
    }

    if (d.isBusy) {
      final awaiting = _awaitingBusy != null;
      return BarCta(
        kind: CtaKind.stop,
        label: t.ctaStop,
        mode: mode,
        busy: awaiting,
        onTap: awaiting
            ? null
            : () {
                Trace.instance.ui('ТАП стоп');
                _awaitBusy(false);
                unawaited(d.stop());
              },
      );
    }

    // Машина ждёт своего часа: единственное осмысленное действие — снять
    // ожидание, иначе она всё равно запустится сама.
    if (armed) {
      return BarCta(
        kind: CtaKind.cancelAlarm,
        label: t.cancelAlarm,
        mode: mode,
        onTap: () => d.setSchedule(
          d.appointment.copyWith(enabled: false),
          immediate: true,
        ),
      );
    }

    // Последняя ошибка остаётся на экране, пока человек явно не нажмёт
    // «Проверить». До этого повторный потенциально опасный запуск недоступен.
    final fault = d.lastFault;
    if (pipe.faultBlocksMode(fault, mode)) {
      return BarCta(kind: CtaKind.start, label: fault.action(t), mode: mode);
    }

    // Машина отчиталась «готово»: три секунды показываем итог без второго
    // скрытого действия. Затем на этом месте снова появится безопасный пуск.
    if (_doneBadge) {
      return BarCta(kind: CtaKind.done, label: t.ctaDone, mode: mode);
    }

    final slide = mode != WorkMode.brew;
    return BarCta(
      kind: CtaKind.start,
      label: slide ? t.slideToStart : t.startMode(_modeShort(t, mode)),
      mode: mode,
      busy: _awaitingBusy != null,
      slideToConfirm: slide,
      onTap: _awaitingBusy != null
          ? null
          : () => unawaited(_requestStart(mode)),
    );
  }
}

/// Что случилось с машиной. Гаснет по тапу и сама — как только телеметрия
/// перестаёт повторять код ошибки.
class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.error, this.at, this.onDismiss});

  final MachineError error;
  final DateTime? at;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final time = at;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: ShapeDecoration(
        color: const Color(0x24D63B2F),
        shape: kSquircle(
          K.rCard,
          side: const BorderSide(color: Color(0x59FF7052)),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: Color(0xFFFF7052),
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  error.label(t),
                  style: const TextStyle(color: K.text, fontSize: 13),
                ),
                if (time != null)
                  Text(
                    '${_two(time.hour)}:${_two(time.minute)} · '
                    '${t.errCode(error.code)}',
                    style: const TextStyle(color: K.textDim, fontSize: 11),
                  ),
              ],
            ),
          ),
          if (onDismiss != null) ...[
            const SizedBox(width: 8),
            KTap(
              onTap: onDismiss,
              semanticLabel: t.checkAgain,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: Text(
                  t.checkAgain,
                  style: const TextStyle(
                    color: Color(0xFFFF9B83),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _two(int v) => v.toString().padLeft(2, '0');
}
