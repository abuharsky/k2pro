import '../ble/protocol.dart';
import 'recipe.dart';

/// Фаза цикла заваривания.
///
/// ВАЖНО: машина НЕ сообщает, в какой фазе она находится. В ответе 0x00 есть
/// только общее состояние (нагрев / экстракция / готово) и текущая температура.
/// Разбивку на предсмачивание → выдержку → экстракцию приложение строит само
/// из рецепта и момента, когда температура дошла до заданной. Это оценка, а не
/// телеметрия: если машина отработает не по заданным секундам, таймер разойдётся
/// с реальностью.
enum BrewPhase {
  idle,
  heating,
  preInfusion,
  standstill,
  extraction,
  done,
  error,
}

class BrewProgress {
  const BrewProgress({
    required this.phase,
    this.elapsed = Duration.zero,
    this.total,
    this.fromTemperature,
    this.toTemperature,
  });

  final BrewPhase phase;
  final Duration elapsed;

  /// null у фазы нагрева — сколько он продлится, заранее неизвестно.
  final Duration? total;

  final int? fromTemperature;
  final int? toTemperature;

  double? get fraction {
    final t = total;
    if (t == null || t.inMilliseconds == 0) return null;
    return (elapsed.inMilliseconds / t.inMilliseconds).clamp(0.0, 1.0);
  }

  static const BrewProgress idle = BrewProgress(phase: BrewPhase.idle);
}

/// Пересчитывает фазу из состояния машины, рецепта и локального секундомера.
class BrewPhaseEstimator {
  DateTime? _cycleStart;
  DateTime? _timedStart;
  MachineState _lastState = MachineState.standby;

  /// Сообщить о новом состоянии машины. Возвращает true, если цикл начался.
  bool onState(MachineState state, {required DateTime now}) {
    final wasBusy = _lastState.isBusy;
    _lastState = state;
    if (state.isBusy && !wasBusy) {
      _cycleStart = now;
      _timedStart = null;
      return true;
    }
    if (!state.isBusy) {
      _cycleStart = null;
      _timedStart = null;
    }
    return false;
  }

  /// Отметить момент, когда температура впервые достигла заданной.
  void markHeatReached(DateTime now) => _timedStart ??= now;

  void reset() {
    _cycleStart = null;
    _timedStart = null;
    _lastState = MachineState.standby;
  }

  BrewProgress compute({
    required MachineState state,
    required MachineError error,
    required int currentTemperature,
    required Recipe recipe,
    required DateTime now,
  }) {
    if (error != MachineError.none) {
      return const BrewProgress(phase: BrewPhase.error);
    }
    if (state.isDone) return const BrewProgress(phase: BrewPhase.done);
    if (!state.isBusy) return BrewProgress.idle;

    // Холодная экстракция греть не должна — сразу таймлайн.
    final needsHeat = state != MachineState.brewing;
    // `_timedStart == null` тут обязательно: как только машина один раз дошла до
    // уставки, обратно в нагрев мы не возвращаемся. Без этого условия экран врал
    // дважды. Машина у цели колеблется ±1°, и на каждом провале ниже уставки
    // подпись прыгала «пролив → нагрев → пролив», а вместе с ней прыгало и число
    // секунд. А когда шёл сам пролив, температура падала на десяток градусов —
    // и мы показывали «нагрев» до конца цикла, хотя вода уже кончилась.
    if (needsHeat &&
        _timedStart == null &&
        currentTemperature < recipe.temperatureC) {
      return BrewProgress(
        phase: BrewPhase.heating,
        elapsed: now.difference(_cycleStart ?? now),
        fromTemperature: currentTemperature,
        toTemperature: recipe.temperatureC,
      );
    }
    if (needsHeat) markHeatReached(now);

    // Только нагрев — фаз пролива нет.
    if (state == MachineState.heating) {
      return BrewProgress(
        phase: BrewPhase.heating,
        elapsed: now.difference(_cycleStart ?? now),
        fromTemperature: currentTemperature,
        toTemperature: recipe.temperatureC,
      );
    }

    final start = _timedStart ?? _cycleStart ?? now;
    var left = now.difference(start);

    final pre = Duration(seconds: recipe.preInfusionSeconds);
    if (left < pre) {
      return BrewProgress(
        phase: BrewPhase.preInfusion,
        elapsed: left,
        total: pre,
      );
    }
    left -= pre;

    final still = Duration(seconds: recipe.standstillSeconds);
    if (left < still) {
      return BrewProgress(
        phase: BrewPhase.standstill,
        elapsed: left,
        total: still,
      );
    }
    left -= still;

    final ext = Duration(seconds: recipe.extractionSeconds);
    return BrewProgress(
      phase: BrewPhase.extraction,
      elapsed: left < ext ? left : ext,
      total: ext,
    );
  }
}
