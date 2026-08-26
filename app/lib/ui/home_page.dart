import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../ble/demo.dart';
import '../ble/k2_device.dart';
import '../ble/protocol.dart';
import '../ble/scale/scale_device.dart';
import '../ble/trace.dart';
import '../l10n/app_l10n.dart';
import '../l10n/l10n_ext.dart';
import '../model/brew_phase.dart';
import '../model/pipeline.dart' as pipe;
import '../model/pipeline.dart' show CtaKind;
import '../model/recipe.dart';
import '../model/shot_runner.dart';
import '../store/prefs.dart';
import '../store/shot_store.dart';
import '../store/recipe_editor.dart';
import 'brew_advice_page.dart';
import 'journal_page.dart';
import 'weight_dialog.dart';
import 'scan_sheet.dart';
import 'scene/machine_scene.dart';
import 'scene/scene_state.dart';
import 'sheets/device_sheet.dart';
import 'sheets/mode_sheet.dart';
import 'sheets/pour_sheet.dart';
import 'sheets/temperature_sheet.dart';
import 'sheets/timer_sheet.dart';
import 'sheets/weight_sheet.dart';
import 'theme.dart';
import 'widgets/bottom_bar.dart';
import 'widgets/cycle_timeline.dart';
import 'widgets/k_icons.dart';
import 'widgets/phase_aura.dart';
import 'widgets/scale_button.dart';
import 'widgets/top_bar.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.device,
    required this.scale,
    required this.prefs,
    this.editor,
    this.store,
    this.demo,
  });

  final K2Device device;

  /// Весы. Всё, что с ними связано, появляется на экране только когда они
  /// на связи и шлют отсчёты.
  final ScaleDevice scale;

  final Prefs prefs;

  /// Общий с часами редактор уставок. null — экран заводит свой: так удобнее
  /// тестам, где часов нет.
  final RecipeEditor? editor;

  /// Где лежат кривые проливов. null — обычная папка приложения; своё
  /// хранилище подставляют снимки экранов, чтобы показать настоящий график.
  final ShotStore? store;

  /// Демо-режим. null — демо в этой сборке недоступно: так собраны тесты и
  /// снимки экранов, где транспорт задаётся напрямую.
  final Demo? demo;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _autoConnectTried = false;

  /// Уставки, набранные локально, пока запись ещё не ушла в машину. Общие с
  /// часами: крутить одно и то же число могут и там, и здесь.
  late final RecipeEditor _editor;
  late final bool _ownsEditor;

  /// Ведение пролива по весу. Живёт здесь, а не в модели экрана: слушать он
  /// должен и машину, и весы, а решение о стопе принимает по отсчёту весов —
  /// независимо от того, нарисован ли кто-нибудь на экране.
  late final ShotRunner _shots;

  /// Кривые проливов на диске. Один на приложение: и пишущий их бегунок, и
  /// журнал должны смотреть в одну папку.
  late final ShotStore _store = widget.store ?? ShotStore();

  /// Совет после готовности закрыли вручную — не показываем до следующего
  /// пролива. См. [_watchBrew]: новый пролив снимает эту метку.
  /// Пролив оборвала ошибка — советовать по нему нечего.
  bool _shotFaulted = false;
  bool _wasBusy = false;

  @override
  void initState() {
    super.initState();
    _ownsEditor = widget.editor == null;
    _editor =
        widget.editor ??
        RecipeEditor(device: widget.device, prefs: widget.prefs);
    _shots = ShotRunner(
      device: widget.device,
      scale: widget.scale,
      prefs: widget.prefs,
      store: _store,
    );
    widget.device.addListener(_watchBrew);
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoConnect());
  }

  @override
  void dispose() {
    widget.device.removeListener(_watchBrew);
    _shots.dispose();
    if (_ownsEditor) _editor.dispose();
    super.dispose();
  }

  /// Следим за проливом ради одной вещи: сорвался он или прошёл.
  ///
  /// Показывать баннер решает не это, а сам итог — [ShotRunner.lastShot]:
  /// он появляется и после ручного стопа, и после отсечки по весу, и после
  /// таймаута. А вот после аварии спрашивать «как получилось?» не о чем: в
  /// чашке ничего нет, и вопрос звучал бы издевательством.
  void _watchBrew() {
    final d = widget.device;
    final busy = d.status?.state.isBusy ?? false;
    if (busy && !_wasBusy) {
      _wasBusy = true;
      if (_shotFaulted) setState(() => _shotFaulted = false);
    } else if (!busy) {
      _wasBusy = false;
    }
    if (d.lastFault != MachineError.none && !_shotFaulted) {
      setState(() => _shotFaulted = true);
    }
  }

  /// Подхватываем машину, к которой подключались в прошлый раз, без клика.
  ///
  /// Весы подхватываем следом и тем же скроллом эфира: искать их отдельным
  /// сканом нельзя — радиоканал один, и второй поиск погасил бы первый.
  Future<void> _autoConnect() async {
    final id = widget.prefs.lastDeviceId;
    if (id == null || _autoConnectTried) return;
    // В демо подключаться некуда: машину уже подставил сам демо-режим.
    if (widget.demo?.on ?? false) return;
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
      final scaleId = widget.prefs.lastScaleId;
      final scaleSeen =
          scaleId != null && d.discovered.any((x) => x.id == scaleId);
      await d.stopScan();
      await d.connect(id);
      widget.prefs.remember(id, '');
      // Весы вторыми и без ожидания: не поднялись — не беда, машина работает
      // и без них, а человек откроет список сам.
      if (scaleSeen) {
        unawaited(
          widget.scale
              .connect(scaleId)
              .catchError(
                (Object e) => Trace.instance.ui('весы не подхватились: $e'),
              ),
        );
      }
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

  /// Запуск в выбранном режиме.
  ///
  /// Порядок «уставки, потом пуск» и ожидание на кнопке — забота [K2Device]:
  /// нажать могут и с часов, а ждать при этом должны оба экрана.
  Future<void> _run(WorkMode mode) async {
    Trace.instance.ui('ТАП пуск: ${mode.name}');
    await widget.device.start(mode, apply: _editor.commit());
  }

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
      demo: widget.demo,
    );
    if (!context.mounted || action == null) return;
    switch (action) {
      case DeviceAction.journal:
        _openJournal(context);
      case DeviceAction.advice:
        await openBrewAdvice(
          context,
          editor: _editor,
          device: widget.device,
          scale: widget.scale,
          prefs: widget.prefs,
        );
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
        // Из демо выходят тем же действием, что и отключаются от машины:
        // вошли в него подключением, выходим отключением.
        final demo = widget.demo;
        if (demo?.on ?? false) {
          await demo!.leave();
        } else {
          await d.disconnect();
        }
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

  /// Уставки шага «вес». Сами весы как прибор живут на своём экране — сюда
  /// заезжает только то, чем кончится пролив.
  Future<void> _openWeight(
    BuildContext context, {
    required bool running,
  }) async {
    Trace.instance.ui('шторка веса открыта');
    await showWeightSheet(
      context,
      scale: widget.scale,
      prefs: widget.prefs,
      // Уставок на ходу машина не берёт, а включение отсечки как раз меняет
      // время экстракции — поэтому на ходу переключатель заперт.
      onAutoStop: running ? null : _setAutoStop,
    );
  }

  /// Взвешивание: диалог по центру. Положил зерно, посмотрел, закрыл —
  /// занятие на десять секунд, и целого экрана оно не стоит.
  Future<void> _openWeightDialog(BuildContext context) async {
    Trace.instance.ui('весы открыты');
    await showWeightDialog(context, scale: widget.scale, prefs: widget.prefs);
  }

  /// Журнал проливов с графиками. В диалог он не влезает и не должен: это про
  /// историю, а не про то, что лежит на весах сейчас.
  void _openJournal(BuildContext context) {
    Trace.instance.ui('журнал открыт');
    openJournal(context, prefs: widget.prefs, store: _store);
  }

  /// Включить или выключить отсечку по весу.
  ///
  /// Включение подменяет время экстракции потолком: секунды перестают быть
  /// целью и становятся предохранителем. Прежнее число запоминаем — человек
  /// его, может, полгода подбирал, и терять его при выключении нельзя.
  void _setAutoStop(bool on) {
    final p = widget.prefs;
    final g = p.gravimetry;
    final range = widget.device.workParams.extraction;
    final now = _editor.active.extractionSeconds;

    if (on) {
      p.gravimetry = g.copyWith(stopOnYield: true, secondsBeforeAutoStop: now);
      if (now < range.max) _editor.edit(extractionSeconds: range.max);
    } else {
      final back = g.secondsBeforeAutoStop;
      p.gravimetry = g.copyWith(stopOnYield: false, dropSavedSeconds: true);
      if (back != null) _editor.edit(extractionSeconds: range.clamp(back));
    }
    Trace.instance.ui('отсечка по весу: ${on ? 'включена' : 'выключена'}');
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
    final m = await showModeSheet(
      context,
      selected: current,
      // Под каждым режимом — его запомненные уставки: сразу видно, что
      // «нагрев + пролив» это эспрессо с паузами, а «пролив» — голый кипяток.
      summary: (mode) => _modeSummary(context.t, mode),
    );
    if (!mounted || m == null) return;
    if (a.enabled) {
      d.setSchedule(a.copyWith(mode: m.asScheduleMode), immediate: true);
    }
    await _editor.selectMode(m);
  }

  /// Короткая сводка набора режима для листа выбора: температура там, где режим
  /// греет, и структура пролива там, где он льёт.
  String _modeSummary(AppL10n t, WorkMode mode) {
    final r = widget.prefs.recipeFor(mode);
    final f = widget.prefs.fahrenheit;
    final unit = f ? '°F' : '°C';
    final temp = '${toDisplayTemp(r.temperatureC, f)}$unit';
    final pour =
        '${r.preInfusionSeconds}/${r.standstillSeconds}/${r.extractionSeconds} ${t.secondsUnit}';
    return switch (mode) {
      WorkMode.heat => temp,
      WorkMode.heatAndBrew => '$temp · $pour',
      WorkMode.brew => pour,
    };
  }

  Future<void> _openScan(BuildContext context) async {
    // Лист сам записывает машину в список — здесь ловить нечего.
    await showScanSheet(
      context,
      widget.device,
      widget.scale,
      widget.prefs,
      demo: widget.demo,
    );
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
      listenable: Listenable.merge([
        widget.device,
        widget.scale,
        _shots,
        widget.prefs,
        _editor,
        widget.demo,
      ]),
      builder: (context, _) {
        final t = context.t;
        final d = widget.device;
        final p = widget.prefs;
        final status = d.status;
        final recipe = _editor.active;
        final phase = d.progress.phase;
        final editable = d.isConnected && !d.isBusy;
        final demo = widget.demo?.on ?? false;

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
                        // левую треть занимает таймлайн. Сдвиг общий на обе:
                        // аура — свечение самой машины и ездит вместе с ней.
                        Positioned.fill(
                          child: Transform.translate(
                            offset: const Offset(_machineShift, 0),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(
                                    left: _machineLeft,
                                  ),
                                  child: PhaseAura(
                                    phase: phase,
                                    running: d.isBusy,
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    _machineLeft,
                                    14,
                                    0,
                                    14,
                                  ),
                                  child: Center(
                                    // Машина занимает не весь отведённый
                                    // прямоугольник: впритык к шапке и нижнему
                                    // ряду она смотрелась тяжело, поэтому
                                    // оставляем вокруг воздух.
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
                              ],
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
                      // В демо имя своё: показывать над симулятором имя, которым
                      // назвали настоящую машину, значит выдавать одно за другое.
                      // Что это симулятор, говорит метка рядом, а не имя.
                      name: demo ? t.appTitle : p.deviceName,
                      demo: demo,
                      connected: d.isConnected,
                      connecting: d.isSeeking,
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
                    _BannerSlot(
                      child: _ErrorBanner(
                        error: d.lastFault,
                        code: d.lastFaultCode,
                        at: d.lastFaultAt,
                        onDismiss: d.clearFault,
                      ),
                    )
                  // Пролив прошёл — мягко предлагаем разобрать чашку.
                  // Некритично: закрыл, и до следующего не покажем. Ошибка
                  // важнее, поэтому не рядом с ней, а вместо неё.
                  //
                  // Признак — записанный итог, а не «готово» от машины: после
                  // ручного стопа она встаёт в покой, а кофе в чашке при этом
                  // есть, просто короче. Раньше на таком баннер не выходил
                  // вовсе.
                  else if (_shots.lastShot != null &&
                      !_shotFaulted &&
                      p.adviceBanner)
                    _BannerSlot(
                      child: _AdviceBanner(
                        onTune: () => openBrewAdvice(
                          context,
                          editor: _editor,
                          device: d,
                          scale: widget.scale,
                          prefs: widget.prefs,
                        ),
                        // Закрыть итог — это же и вернуть бегунок в покой:
                        // фаза и баннер живут врозь, но убираются заодно.
                        onDismiss: _shots.dismiss,
                      ),
                    ),

                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: BottomBar(
                      cta: _cta(t, d, mode, armed),
                      // Весы встают в тот же ряд, что и пуск, и только когда
                      // они есть: пустая кнопка ничего не сообщает.
                      leading: widget.scale.isConnected
                          ? ScaleButton(
                              scale: widget.scale,
                              onTap: () => _openWeightDialog(context),
                            )
                          : null,
                    ),
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

  /// Машину с аурой сдвигаем правее центра зоны: слева проходит колонка
  /// таймлайна, и в портрете без сдвига они смотрятся вплотную. Сдвиг, а не
  /// поле слева: поле съело бы ширину зоны и заодно уменьшило саму машину.
  static const double _machineShift = 16;

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
              ? () => showTimerSheet(
                  context,
                  d,
                  recipe: _editor.active,
                  runMode: widget.prefs.runMode,
                )
              : d.isConnected && !model.running
              ? () => showTimerSheet(
                  context,
                  d,
                  recipe: _editor.active,
                  runMode: widget.prefs.runMode,
                )
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
      // При отсечке по весу секунды перестают быть целью: цель — граммы, а
      // машина просто не даст лить дольше. Поэтому в покое карточка называется
      // пределом и не горит, а на самой экстракции с неё уезжает кольцо —
      // долю показывает карточка веса. Секунды при этом остаются: время шота
      // смотрят всегда, просто теперь это секундомер, а не обратный отсчёт.
      final byWeight = _autoStopArmed;
      final onExtraction = live?.id == pipe.StepId.extraction;
      steps.add(
        CycleStep(
          kind: StepKind.pour,
          label: (live?.label ?? (byWeight ? t.weightLimit : t.stepPour))
              .toUpperCase(),
          value: byWeight && onExtraction
              ? t.seconds(d.progress.elapsed.inSeconds)
              : live?.value ?? t.seconds(total),
          icon: live == null ? KIcon.streams : _iconOf(live.id),
          tone: live == null
              ? (byWeight ? PhaseTone.muted : PhaseTone.amber)
              : _toneOf(live.tone, model.mode),
          mark: live != null
              ? StepMark.active
              : pour.every((s) => s.mark == pipe.StepMark.passed)
              ? StepMark.passed
              : StepMark.upcoming,
          progress: byWeight && onExtraction ? null : live?.progress,
          onTap: pour.any((s) => s.editable) ? () => _openPour(context) : null,
        ),
      );
    }

    // 5. Вес: карточки нет, пока нет весов. Подключены они или нет — вопрос
    // не режима, а наличия: показывать цель, которую нечем измерить, значит
    // обещать несделанное.
    final weight = _weightStep(t, model.running);
    if (weight != null) steps.add(weight);

    return steps;
  }

  /// Отсечка по весу действительно работает: человек её включил и весы живы.
  ///
  /// Одного переключателя мало — весы могут просто лежать на столе и не иметь
  /// к машине отношения, а могут отвалиться посреди пролива. Во всех этих
  /// случаях пролив идёт по времени, и врать про это карточкам нельзя.
  bool get _autoStopArmed =>
      widget.prefs.gravimetry.stopOnYield && widget.scale.isLive;

  /// Карточка веса. Два лица: наблюдение и отсечка.
  CycleStep? _weightStep(AppL10n t, bool running) {
    final scale = widget.scale;
    if (!scale.isConnected) return null;

    final g = widget.prefs.gravimetry;
    final auto = _autoStopArmed;
    final phase = _shots.phase;
    final settling = phase == ShotPhase.settling;
    final done = phase == ShotPhase.done;

    String grams(double v) => t.weightGrams(v.toStringAsFixed(1));

    return CycleStep(
      kind: StepKind.weight,
      label: (settling ? t.weightSettling : t.stepWeight).toUpperCase(),
      // По времени карточка показывает живой вес и больше ничего: цели она не
      // заказывала. По весу — сколько набрано из заказанного.
      value: !auto
          ? grams(scale.grams)
          : _shots.isRunning || done
          ? t.weightOf(
              scale.grams.toStringAsFixed(1),
              g.targetG.toStringAsFixed(1),
            )
          : grams(g.targetG),
      icon: KIcon.scale,
      tone: auto ? PhaseTone.water : PhaseTone.muted,
      // `setting` — карточка стоит в колонке, но в очереди фаз не участвует:
      // ни линии сверху, ни «пройдено». Ровно то, что нужно наблюдению.
      mark: !auto
          ? StepMark.setting
          : done
          ? StepMark.passed
          : _shots.isRunning
          ? StepMark.active
          : StepMark.upcoming,
      // Кольцо живёт здесь только при отсечке — и не гаснет на осадке: пролив
      // уже пройден, а вес ещё доползает, и это последнее, что видно живым.
      progress: auto && (_shots.isRunning || done) ? _shots.fraction : null,
      // Цель горит цветом воды с самого покоя: по этой цифре и видно, что
      // пролив пойдёт по весу, а не по секундам.
      accent: auto,
      onTap: () => _openWeight(context, running: running),
    );
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
    final kind = pipe.ctaKindOf(d, armed: armed, mode: mode);
    // Ожидание — свойство цикла, а не кнопки: команда могла уйти и с часов.
    final pending = d.cycleState.isPending;
    // Жестом подтверждаются оба необратимых действия. Пуск с нагревом включает
    // кипятильник, стоп рубит пролив на середине — и то, и другое переделать
    // нельзя, а кнопка внизу широкая и попадается под палец сама.
    final slide =
        kind == CtaKind.stop ||
        (kind == CtaKind.start && mode != WorkMode.brew);

    return BarCta(
      kind: kind,
      mode: mode,
      slideToConfirm: slide,
      busy: switch (kind) {
        CtaKind.connect => d.isSeeking,
        CtaKind.start || CtaKind.stop => pending,
        _ => false,
      },
      label: switch (kind) {
        CtaKind.connect => t.connect,
        CtaKind.stop => t.slideToStop,
        CtaKind.done => t.ctaDone,
        CtaKind.cancelAlarm => t.cancelAlarm,
        // Последняя ошибка остаётся на экране, пока человек явно не нажмёт
        // «Проверить». До этого повторный пуск недоступен.
        CtaKind.blocked => d.lastFault.action(t),
        CtaKind.start =>
          slide ? t.slideToStart : t.startMode(_modeShort(t, mode)),
      },
      onTap: switch (kind) {
        CtaKind.connect => d.isSeeking ? null : () => _openScan(context),
        CtaKind.stop =>
          pending
              ? null
              : () {
                  Trace.instance.ui('ТАП стоп');
                  unawaited(d.stop());
                },
        CtaKind.cancelAlarm => () => d.setSchedule(
          d.appointment.copyWith(enabled: false),
          immediate: true,
        ),
        CtaKind.start => pending ? null : () => unawaited(_requestStart(mode)),
        CtaKind.done || CtaKind.blocked => null,
      },
    );
  }
}

/// Место баннера над рядом пуска.
///
/// Ширина ограничена, а сам баннер стоит по центру: строка во весь планшет
/// заставляет глаз бежать через весь экран ради полутора слов. Колонкой её
/// держат и лист настроек, и ряд пуска — баннер встаёт в тот же столбец.
class _BannerSlot extends StatelessWidget {
  const _BannerSlot({required this.child});

  final Widget child;

  /// Чуть шире ряда пуска под ним (`BottomBar`: 300 одной кнопкой, 394 с
  /// весами) — баннер и кнопка читаются одним столбцом, а не двумя разными
  /// вещами, случайно оказавшимися рядом.
  static const double maxWidth = 400;

  @override
  Widget build(BuildContext context) => Positioned(
    left: 10,
    right: 10,
    // Приподнят над рядом пуска: впритык баннер читается как часть кнопки.
    bottom: BottomBar.height + 10,
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    ),
  );
}

/// Что случилось с машиной. Гаснет по тапу и сама — как только телеметрия
/// перестаёт повторять код ошибки.
class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({
    required this.error,
    required this.code,
    this.at,
    this.onDismiss,
  });

  final MachineError error;

  /// Сырой код от машины. У знакомой ошибки он совпадает с [MachineError.code],
  /// у незнакомой — единственное, что о ней известно.
  final int code;
  final DateTime? at;
  final VoidCallback? onDismiss;

  /// Тёплый красный кромки и значка. Заливка того же цвета, но глубже: под
  /// размытием стекла яркая плёнка выглядела бы наклейкой.
  static const Color _accent = Color(0xFFFF8A6B);

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final time = at;
    // У знакомой ошибки номер известен из неё самой; сырое число нужно только
    // незнакомой — по нему её и будут искать в сервисе.
    final shown = error == MachineError.unknown ? code : error.code;
    return Glass(
      radius: K.rCard,
      tone: GlassTone.panel,
      fill: const Color(0x2ED63B2F),
      border: _accent.withValues(alpha: 0.55),
      // Своё свечение вместо нейтральной тени: полоса всплывает над рядом
      // кнопок, и красный ореол отделяет её от них лучше любой рамки.
      shadow: const [
        BoxShadow(
          color: Color(0x4DD63B2F),
          blurRadius: 24,
          offset: Offset(0, 8),
        ),
      ],
      padding: const EdgeInsets.fromLTRB(14, 11, 6, 11),
      child: Row(
        children: [
          const KIconView(KIcon.alert, size: 19, color: _accent),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  error.label(t),
                  style: K.rowTitle.copyWith(color: K.text, fontSize: 13.5),
                ),
                const SizedBox(height: 2),
                Text(
                  time == null
                      ? t.errCode(shown)
                      : '${_two(time.hour)}:${_two(time.minute)} · '
                            '${t.errCode(shown)}',
                  style: K.caption.copyWith(color: K.textDim),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                child: Text(
                  t.checkAgain,
                  style: K.menuChip.copyWith(color: _accent, fontSize: 12),
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

/// Мягкое предложение разобрать чашку после готовности. Некритично: «Настроить»
/// открывает советы, крестик — гасит до следующего пролива.
class _AdviceBanner extends StatelessWidget {
  const _AdviceBanner({required this.onTune, required this.onDismiss});

  final VoidCallback onTune;
  final VoidCallback onDismiss;

  static const Color _accent = K.amber;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Glass(
      radius: K.rCard,
      tone: GlassTone.panel,
      fill: const Color(0x1FFFB000),
      border: _accent.withValues(alpha: 0.5),
      shadow: const [
        BoxShadow(
          color: Color(0x33FFB000),
          blurRadius: 22,
          offset: Offset(0, 8),
        ),
      ],
      padding: const EdgeInsets.fromLTRB(14, 11, 6, 11),
      child: Row(
        children: [
          const KIconView(KIcon.cup, size: 19, color: _accent),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.adviceHeadline,
                  style: K.rowTitle.copyWith(color: K.text, fontSize: 13.5),
                ),
                const SizedBox(height: 2),
                Text(
                  t.adviceBannerBody,
                  style: K.caption.copyWith(color: K.textDim),
                ),
              ],
            ),
          ),
          KTap(
            onTap: onTune,
            semanticLabel: t.adviceTune,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Text(
                t.adviceTune,
                style: K.menuChip.copyWith(color: _accent, fontSize: 12),
              ),
            ),
          ),
          KTap(
            onTap: onDismiss,
            semanticLabel: MaterialLocalizations.of(context).closeButtonLabel,
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: KIconView(KIcon.close, size: 15, color: K.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}
