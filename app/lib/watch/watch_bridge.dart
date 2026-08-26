import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../ble/k2_device.dart';
import '../ble/protocol.dart';
import '../ble/scale/scale_device.dart';
import '../ble/transport.dart';
import '../model/gravimetry.dart';
import '../ble/trace.dart';
import '../l10n/app_l10n.dart';
import '../l10n/l10n_ext.dart';
import '../store/prefs.dart';
import '../store/recipe_editor.dart';
import 'watch_snapshot.dart';

/// Связь с приложением на Apple Watch.
///
/// Часы — тонкая проекция: вся логика остаётся здесь, туда уезжает готовый
/// снимок, обратно приезжают команды. Ни BLE, ни протокола на той стороне нет.
///
/// Канал односторонне безопасен: если часов нет или watchOS их не разбудила,
/// [_push] просто ничего не делает.
class WatchBridge {
  WatchBridge({
    required this.device,
    required this.scale,
    required this.prefs,
    required this.editor,
    required this.l10n,
  }) {
    _channel.setMethodCallHandler(_onCall);
    device.addListener(_schedulePush);
    prefs.addListener(_schedulePush);
    editor.addListener(_schedulePush);
    scale.addListener(_onScale);
  }

  static const MethodChannel _channel = MethodChannel('k2pro/watch');

  final K2Device device;

  /// Весы. Отдельное устройство и отдельная линия: их может не быть вовсе, и
  /// тогда на часах просто нет ни строки в списке, ни ряда веса.
  final ScaleDevice scale;

  final Prefs prefs;
  final RecipeEditor editor;

  /// Строки берём отложенно: язык может смениться в настройках.
  final AppL10n Function() l10n;

  Timer? _throttle;
  bool _pending = false;

  /// То, что от весов реально попадёт на экран часов.
  ///
  /// Весы шлют отсчёты около десяти раз в секунду, а видно из них одну цифру
  /// с десятой долей грамма. Гнать снимок на каждый кадр значит держать радио
  /// занятым ради числа, которое не изменилось, — поэтому сравниваем не сырой
  /// вес, а ровно то, что нарисуется.
  String? _scaleDigest;

  void _onScale() {
    final next = [
      scale.isLive ? scale.grams.toStringAsFixed(1) : '-',
      scale.sessionState.name,
      scale.batteryPercent,
    ].join('|');
    if (next == _scaleDigest) return;
    _scaleDigest = next;
    _schedulePush();
  }

  /// Идёт поиск. Машина об этом не сообщает, а часам показать надо —
  /// поэтому засекаем сами.
  Timer? _scanTimer;
  bool _scanning = false;

  /// Часы шлют телеметрию раз в секунду; чаще этого снимок не нужен, но и
  /// ждать секунду после нажатия кнопки нельзя. Триста миллисекунд —
  /// компромисс: нажатие ощущается мгновенным, поток не захлёбывается.
  static const Duration _minInterval = Duration(milliseconds: 300);

  void dispose() {
    device.removeListener(_schedulePush);
    prefs.removeListener(_schedulePush);
    editor.removeListener(_schedulePush);
    scale.removeListener(_onScale);
    _throttle?.cancel();
    _scanTimer?.cancel();
  }

  // ---- телефон → часы ----------------------------------------------------

  void _schedulePush() {
    if (_throttle != null) {
      _pending = true;
      return;
    }
    _push();
    _throttle = Timer(_minInterval, () {
      _throttle = null;
      if (_pending) {
        _pending = false;
        _schedulePush();
      }
    });
  }

  /// Снимок уходит одной JSON-строкой, а не словарём.
  ///
  /// WatchConnectivity принимает только plist-совместимую нагрузку, а `null`
  /// из Dart приезжает туда как `NSNull` и роняет отправку целиком. Городить
  /// вычистку пустых полей на каждом уровне вложенности — лишняя работа: JSON
  /// умеет null сам, а на часах он раскладывается в Codable-структуры.
  Future<void> _push() async {
    final Map<String, Object?> snapshot;
    try {
      snapshot = buildWatchSnapshot(
        d: device,
        scale: scale,
        t: l10n(),
        prefs: prefs,
        recipe: editor.active,
        scanning: _scanning,
        ctaBusy: device.cycleState.isPending,
      );
    } catch (e, st) {
      // Снимок не должен ронять приложение на телефоне: часы — не главное.
      debugPrint('watch: snapshot failed: $e\n$st');
      return;
    }
    final wake = _wakeDigest(snapshot);
    final significant = wake != _lastWake;
    _lastWake = wake;
    try {
      await _channel.invokeMethod<void>('push', {
        's': jsonEncode(snapshot),
        'wake': significant,
      });
    } on MissingPluginException {
      // Не iOS или мост не поднялся — молча живём дальше.
    } on PlatformException catch (e) {
      debugPrint('watch: push failed: ${e.message}');
    }
  }

  String? _lastWake;

  /// Что стоит того, чтобы поднять часы из сна.
  ///
  /// Виджет Smart Stack пишет приложение на часах, а оно почти всегда спит:
  /// разбудить его — единственный способ обновить статус. Будильник у
  /// WatchConnectivity суточный и небогатый, поэтому дёргаем его не на каждый
  /// снимок, а на смену смысла: связь, работа, фаза, отказ, взведённый таймер.
  ///
  /// Бегущих величин здесь нарочно нет. Вес и проценты меняются десять раз в
  /// секунду и квоту сожгли бы за минуту, а срок готовности часы докручивают
  /// сами от абсолютного времени в `startLine` — оно и стоит вместо остатка.
  String _wakeDigest(Map<String, Object?> s) {
    final dev = s['device'] as Map<String, Object?>?;
    final timer = s['timer'] as Map<String, Object?>?;
    final steps = s['steps'] as List<Object?>? ?? const [];
    String? active;
    for (final row in steps) {
      if (row is Map && row['mark'] == 'active') {
        active = row['id'] as String?;
        break;
      }
    }
    return [
      s['link'] == 'connected',
      dev?['name'],
      dev?['running'],
      dev?['state'],
      dev?['error'],
      active,
      timer?['armed'],
      timer?['startLine'],
    ].join('|');
  }

  // ---- часы → телефон ----------------------------------------------------

  Future<Object?> _onCall(MethodCall call) async {
    if (call.method != 'command') return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(call.arguments as String);
    } catch (e) {
      debugPrint('watch: bad command: $e');
      return null;
    }
    if (decoded is! Map) return null;
    final raw = decoded;
    final cmd = raw['cmd'];
    if (cmd is! String) return null;

    switch (cmd) {
      // Часы проснулись и просят актуальную картинку.
      case 'hello':
        await _push();

      case 'scan':
        _scanning = true;
        _scanTimer?.cancel();
        // Столько же держит поиск в листе на телефоне.
        _scanTimer = Timer(const Duration(seconds: 12), () {
          _scanning = false;
          unawaited(device.stopScan());
          _schedulePush();
        });
        _schedulePush();
        await device.startScan();

      case 'connect':
        final id = raw['id'];
        if (id is String) await _connect(id, raw['kind'] as String?);

      case 'disconnect':
        if (raw['kind'] == 'scale') {
          await scale.disconnect();
        } else {
          await device.disconnect();
        }

      case 'tare':
        await scale.tare();

      case 'setYield':
        _setYield(_int(raw['value']));

      case 'setAutoStop':
        _setAutoStop(raw['on'] == true);

      case 'start':
        // Ожидание подтверждения считает машина цикла — она же и толкнёт
        // снимок, как только состояние сменится. Своей копии здесь больше нет:
        // экран и часы расходились ровно на ней.
        await _start();

      case 'stop':
        await device.stop();

      case 'setStep':
        _setStep(raw['id'] as String?, _int(raw['value']));

      case 'setMode':
        _setMode(_int(raw['value']));

      case 'setTimer':
        _setTimer(_int(raw['minutes']), raw['on'] == true);

      case 'armPreset':
        _armPreset(_int(raw['minutes']));
    }
    // Немедленный ответ: часы рисуют оптимистично, но правду ждут отсюда.
    _schedulePush();
    return null;
  }

  /// Пуск в том режиме, который действительно отработает.
  Future<void> _start() async {
    Trace.instance.ui('ТАП пуск с часов');
    final mode = device.appointment.enabled
        ? device.appointment.mode.asWorkMode
        : prefs.runMode;
    // Уставки должны лечь в машину раньше, чем она начнёт по ним работать —
    // и не только накопленная правка: пока машина не ответила ни разу, на
    // экране кэш прошлого сеанса, а что внутри неё, неизвестно. Порядок и
    // ожидание держит [K2Device.start] — один на телефон и на часы.
    await device.start(mode, apply: editor.commit());
  }

  /// Подключение к тому, что часы выбрали в списке.
  ///
  /// Род приезжает вместе с командой, но полагаться только на него нельзя:
  /// снимок мог быть от прошлой версии контракта. Если рода нет — смотрим,
  /// чем это устройство представилось в эфире.
  Future<void> _connect(String id, String? kind) async {
    final k = kind ?? _kindOf(id);
    // Подключились с часов — устройство должно оказаться и в списке
    // добавленных на телефоне: часы не заводят себе отдельной памяти.
    final name =
        device.discovered
            .where((e) => e.id == id)
            .map((e) => e.advertisedName)
            .firstOrNull ??
        '';
    if (k == 'scale') {
      await scale.connect(id);
      prefs.rememberScale(id, name);
      return;
    }
    await device.connect(id);
    prefs.remember(id, name);
  }

  String _kindOf(String id) {
    for (final e in device.discovered) {
      if (e.id == id) return e.kind == DeviceKind.scale ? 'scale' : 'machine';
    }
    // Ничего не нашли — значит это запомненное устройство, а запоминаем мы их
    // по отдельности.
    return id == prefs.lastScaleId ? 'scale' : 'machine';
  }

  /// Цель по весу приезжает в десятых долях грамма: у часов один числовой
  /// редактор на все шаги, и дробей он не знает.
  void _setYield(int? tenths) {
    if (tenths == null) return;
    prefs.gravimetry = prefs.gravimetry.copyWith(
      targetG: (tenths / 10).clamp(kYieldMin, kYieldMax),
    );
  }

  /// Включить или выключить отсечку по весу.
  ///
  /// Ровно то же, что делает телефон: включение подменяет время экстракции
  /// потолком — секунды перестают быть целью и становятся предохранителем.
  /// Прежнее число запоминается, иначе выключение отсечки стирало бы
  /// подобранную человеком уставку навсегда.
  void _setAutoStop(bool on) {
    final g = prefs.gravimetry;
    final range = device.workParams.extraction;
    final now = editor.active.extractionSeconds;

    if (on) {
      prefs.gravimetry = g.copyWith(
        stopOnYield: true,
        secondsBeforeAutoStop: now,
      );
      if (now < range.max) editor.edit(extractionSeconds: range.max);
    } else {
      final back = g.secondsBeforeAutoStop;
      prefs.gravimetry = g.copyWith(stopOnYield: false, dropSavedSeconds: true);
      if (back != null) editor.edit(extractionSeconds: range.clamp(back));
    }
  }

  /// Уставка шага. Имена совпадают с `StepId` — они же уехали в снимке.
  void _setStep(String? id, int? value) {
    if (id == null || value == null) return;
    switch (id) {
      case 'heat':
        // На часах температура в тех же единицах, что и на телефоне.
        editor.edit(temperatureC: fromDisplayTemp(value, prefs.fahrenheit));
      case 'wetting':
        editor.edit(preInfusionSeconds: value);
      case 'pause':
        editor.edit(standstillSeconds: value);
      case 'extraction':
        editor.edit(extractionSeconds: value);
      case 'flow':
        editor.edit(pressure: value);
    }
  }

  /// Смена режима. Если таймер взведён, режим принадлежит ему — значит задание
  /// надо переписать в машину целиком, иначе она отработает старым.
  void _setMode(int? code) {
    if (code == null) return;
    final mode = WorkMode.values.firstWhere(
      (m) => m.code == code,
      orElse: () => WorkMode.heatAndBrew,
    );
    prefs.runMode = mode;
    final a = device.appointment;
    if (a.enabled) {
      device.setSchedule(
        a.copyWith(mode: mode.asScheduleMode),
        immediate: true,
      );
    }
  }

  /// Взвести пресет готовности: срок = сейчас + N, старт = срок − цикл (но не
  /// в прошлое). Ровно то же считает лист таймера на телефоне; держать это в
  /// мосте, а не гонять на часы, — потому что решение «когда стартовать» про
  /// кофе, а часам про кофе знать нечего.
  void _armPreset(int? minutes) {
    if (minutes == null) return;
    final a = device.appointment;
    final mode = prefs.runMode;
    final now = device.currentTime;
    final cycle = watchCycleSeconds(editor.active, mode);
    var start = now
        .add(Duration(minutes: minutes))
        .subtract(Duration(seconds: cycle));
    // Пресет короче цикла — стартуем как можно раньше, прямо сейчас.
    if (start.isBefore(now)) start = now;
    device.setSchedule(
      a.copyWith(
        mode: mode.asScheduleMode,
        hour: start.hour,
        minute: start.minute,
        enabled: true,
      ),
      immediate: true,
    );
  }

  void _setTimer(int? minutes, bool on) {
    final a = device.appointment;
    final m = minutes ?? a.hour * 60 + a.minute;
    device.setSchedule(
      a.copyWith(
        hour: (m ~/ 60) % 24,
        minute: m % 60,
        enabled: on,
        // Взводим тем режимом, который выбран сейчас: на часах таймер и режим
        // стоят рядом, и человек ожидает, что запустится именно он.
        mode: on ? prefs.runMode.asScheduleMode : a.mode,
      ),
      // Взвод и снятие — решение, а не кручение колеса: ждать паузы незачем.
      immediate: true,
    );
  }

  static int? _int(Object? v) => v is int ? v : (v is num ? v.toInt() : null);
}
