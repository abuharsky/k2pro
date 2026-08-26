import 'dart:async';

import 'package:flutter/services.dart';

import '../ble/k2_device.dart';
import '../ble/scale/scale_device.dart';
import '../l10n/app_l10n.dart';
import '../l10n/l10n_ext.dart';
import '../model/brew_phase.dart';
import '../store/prefs.dart';
import '../watch/watch_snapshot.dart' show WatchPalette;

/// Мост Live Activity на iOS.
///
/// Родня [WatchBridge]: слушает машину и весы, а наружу через MethodChannel
/// отдаёт готовое состояние — начать, обновить, кончить. Ни ActivityKit, ни
/// правил про кофе тут нет: решается только «идёт ли пролив и что показать».
///
/// Никакой своей логики цикла: «идёт» — это [K2Device.isBusy], та же истина,
/// по которой часы показывают экран работы. Так телефон, часы и Live Activity
/// говорят об одном и том же одними словами.
class LiveActivityBridge {
  LiveActivityBridge({
    required this.device,
    required this.scale,
    required this.prefs,
    required this.l10n,
  }) {
    device.addListener(_onChange);
    scale.addListener(_onChange);
    _sync();
  }

  final K2Device device;
  final ScaleDevice scale;
  final Prefs prefs;
  final AppL10n Function() l10n;

  static const MethodChannel _channel = MethodChannel('k2pro/liveactivity');

  /// Активность заведена и ещё не закрыта.
  bool _active = false;

  /// Когда пошёл цикл, в миллисекундах эпохи. Считается один раз на старте:
  /// секундомер в бейдже тикает от него сам, и дёргать его каждым кадром
  /// значило бы, что время прыгает под пальцем.
  int? _startedAtMs;

  /// То, что реально видно. Обновляем активность, только когда меняется —
  /// весы шлют вес десять раз в секунду, а на экране блокировки столько
  /// движения ни к чему.
  String? _digest;

  /// Не чаще, чем раз в это время, ходим в ActivityKit: поток веса частый, а
  /// бюджет обновлений у системы не резиновый.
  static const Duration _minInterval = Duration(milliseconds: 400);
  Timer? _throttle;
  bool _pendingUpdate = false;

  void dispose() {
    device.removeListener(_onChange);
    scale.removeListener(_onChange);
    _throttle?.cancel();
  }

  /// Прибраться после прошлой жизни приложения.
  ///
  /// Карточка на экране блокировки переживает и выгрузку, и падение — так она
  /// устроена. Но ссылка на неё живёт только в памяти процесса, и без этого
  /// звонка новый запуск завёл бы рядом вторую, а первая, никем не закрытая,
  /// тикала бы сама по себе. Кто здесь истина, знает только машина: на старте
  /// связи с ней ещё нет, `isBusy` ложно, и всё найденное будет закрыто — а
  /// если пролив и правда идёт, [_onChange] через миг заведёт карточку заново.
  void _sync() {
    final busy = device.isBusy;
    if (busy) {
      _active = true;
      _startedAtMs =
          DateTime.now().millisecondsSinceEpoch -
          device.progress.elapsed.inMilliseconds;
    }
    final payload = _payload(running: busy);
    if (busy) _digest = _digestOf(payload);
    _invoke('sync', payload);
  }

  void _onChange() {
    if (device.isBusy) {
      _startedAtMs ??=
          DateTime.now().millisecondsSinceEpoch -
          device.progress.elapsed.inMilliseconds;
      final payload = _payload(running: true);
      if (!_active) {
        _active = true;
        _digest = _digestOf(payload);
        _invoke('start', payload);
      } else if (_digestOf(payload) != _digest) {
        _digest = _digestOf(payload);
        _scheduleUpdate(payload);
      }
    } else if (_active) {
      _active = false;
      _digest = null;
      _startedAtMs = null;
      _throttle?.cancel();
      _throttle = null;
      _pendingUpdate = false;
      _invoke('end', _payload(running: false));
    }
  }

  /// Коалесцируем обновления: первое уходит сразу, остальные — не чаще
  /// [_minInterval], последнее не теряется.
  void _scheduleUpdate(Map<String, Object?> payload) {
    if (_throttle != null) {
      _pendingUpdate = true;
      return;
    }
    _invoke('update', payload);
    _throttle = Timer(_minInterval, () {
      _throttle = null;
      if (_pendingUpdate && _active) {
        _pendingUpdate = false;
        _scheduleUpdate(_payload(running: true));
      }
    });
  }

  Map<String, Object?> _payload({required bool running}) {
    final t = l10n();
    final state = device.status?.state;
    return {
      'machineName': prefs.deviceName,
      'stateLabel': state?.label(t) ?? '',
      'phase': _phaseKey(device.progress.phase),
      'accentHex': WatchPalette.modeAccent[prefs.runMode]!,
      'detail': _detail(t),
      'startedAtMs': _startedAtMs ?? DateTime.now().millisecondsSinceEpoch,
      'running': running,
    };
  }

  /// Вторая строка: сколько в чашке и куда идём. Без живых весов её нет —
  /// придумывать вес не из чего.
  String? _detail(AppL10n t) {
    if (!scale.isLive) return null;
    final g = scale.grams.toStringAsFixed(1);
    final unit = t.gramsUnit;
    if (prefs.gravimetry.stopOnYield) {
      final target = prefs.gravimetry.targetG.toStringAsFixed(1);
      return '$g → $target $unit';
    }
    return '$g $unit';
  }

  String _phaseKey(BrewPhase phase) => switch (phase) {
    BrewPhase.heating => 'heat',
    BrewPhase.done => 'done',
    _ => 'brew',
  };

  String _digestOf(Map<String, Object?> p) =>
      [p['stateLabel'], p['phase'], p['detail'], p['running']].join('|');

  void _invoke(String method, Map<String, Object?> payload) {
    // Канал односторонне безопасен: нет расширения или iOS старше 16.1 —
    // нативная сторона просто молчит.
    _channel.invokeMethod<void>(method, payload);
  }
}
