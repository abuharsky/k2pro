import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../ble/k2_device.dart';
import '../ble/protocol.dart';
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
    required this.prefs,
    required this.editor,
    required this.l10n,
  }) {
    _channel.setMethodCallHandler(_onCall);
    device.addListener(_schedulePush);
    prefs.addListener(_schedulePush);
    editor.addListener(_schedulePush);
  }

  static const MethodChannel _channel = MethodChannel('k2pro/watch');

  final K2Device device;
  final Prefs prefs;
  final RecipeEditor editor;

  /// Строки берём отложенно: язык может смениться в настройках.
  final AppL10n Function() l10n;

  Timer? _throttle;
  bool _pending = false;

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
    try {
      await _channel.invokeMethod<void>('push', jsonEncode(snapshot));
    } on MissingPluginException {
      // Не iOS или мост не поднялся — молча живём дальше.
    } on PlatformException catch (e) {
      debugPrint('watch: push failed: ${e.message}');
    }
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
        if (id is String) {
          await device.connect(id);
          // Часы подключаются к тому, что видят в эфире, — машина оттуда
          // тоже должна попасть в список добавленных.
          prefs.remember(
            id,
            device.discovered
                    .where((e) => e.id == id)
                    .map((e) => e.advertisedName)
                    .firstOrNull ??
                '',
          );
        }

      case 'disconnect':
        await device.disconnect();

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
    }
    // Немедленный ответ: часы рисуют оптимистично, но правду ждут отсюда.
    _schedulePush();
    return null;
  }

  /// Пуск в том режиме, который действительно отработает.
  Future<void> _start() async {
    Trace.instance.ui('ТАП пуск с часов');
    // Уставки должны лечь в машину раньше, чем она начнёт по ним работать —
    // и не только накопленная правка: пока машина не ответила ни разу, на
    // экране кэш прошлого сеанса, а что внутри неё, неизвестно.
    await editor.push();
    final mode = device.appointment.enabled
        ? device.appointment.mode.asWorkMode
        : prefs.runMode;
    await switch (mode) {
      WorkMode.heatAndBrew => device.heatAndBrew(),
      WorkMode.heat => device.heat(),
      WorkMode.brew => device.brew(),
    };
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
