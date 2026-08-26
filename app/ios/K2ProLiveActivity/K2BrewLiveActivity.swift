import ActivityKit
import SwiftUI
import WidgetKit

/// Live Activity «идёт пролив»: экран блокировки, баннер и Dynamic Island.
///
/// Считать здесь нечего — всё пришло готовым в [K2BrewAttributes]. Время
/// секундомера рисует система из `startedAt`, поэтому пока идёт цикл, обновлять
/// активность ради тикающих секунд не нужно: только на смене статуса и веса.
///
/// Начинка вынесена в [BrewCard] и его соседей: той же вьюхой снимаются
/// скриншоты в приложении, без запуска реальной активности.
@available(iOS 16.1, *)
struct K2BrewLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: K2BrewAttributes.self) { context in
      LockScreenView(context: context)
        .activityBackgroundTint(Color.black.opacity(0.55))
        .activitySystemActionForegroundColor(.white)
    } dynamicIsland: { context in
      let accent = Color(hexString: context.state.accentHex)
      let live = brewIsLive(context)
      return DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          PhaseGlyph(phase: context.state.phase, color: accent, size: 24)
        }
        DynamicIslandExpandedRegion(.trailing) {
          TimeBadge(
            running: live,
            startedAt: context.state.startedAt,
            color: accent,
            size: 22
          )
        }
        DynamicIslandExpandedRegion(.bottom) {
          VStack(alignment: .leading, spacing: 2) {
            Text(context.state.stateLabel)
              .font(.headline)
              .foregroundStyle(accent)
            Text(context.attributes.machineName)
              .font(.caption)
              .foregroundStyle(.secondary)
            if let detail = context.state.detail {
              Text(detail)
                .font(.system(.body, design: .rounded).monospacedDigit())
                .foregroundStyle(.primary)
            }
          }
        }
      } compactLeading: {
        // Слева — что происходит с водой…
        PhaseGlyph(phase: context.state.phase, color: accent, size: 16)
      } compactTrailing: {
        // …справа — живой секундомер, как в системном таймере: это самое
        // полезное с одного взгляда. Мелкий кегль держит пилюлю узкой —
        // пролив идёт полминуты-минуту, число короткое.
        TimeBadge(
          running: live,
          startedAt: context.state.startedAt,
          color: accent,
          size: 13,
          weight: .semibold
        )
        .foregroundStyle(accent)
      } minimal: {
        PhaseGlyph(phase: context.state.phase, color: accent, size: 16)
      }
      .keylineTint(accent)
    }
  }
}

/// Ещё ли карточке верить.
///
/// Секундомер в бейдже тикает сам от абсолютной метки — обновлений для этого
/// не нужно, и в этом же ловушка: карточку, осиротевшую после смерти
/// приложения, некому остановить, и она считает до вечера. Срок протухания
/// система знает от нас (см. `LiveActivityBridge`), а мы по нему замираем: в
/// цифры уже нельзя верить, а галочка честнее бегущих секунд.
@available(iOS 16.1, *)
func brewIsLive(_ context: ActivityViewContext<K2BrewAttributes>) -> Bool {
  guard context.state.running else { return false }
  if #available(iOS 16.2, *) { return !context.isStale }
  return true
}

/// Экран блокировки и баннер: та же [BrewCard], только запитанная из
/// системного контекста активности.
@available(iOS 16.1, *)
struct LockScreenView: View {
  let context: ActivityViewContext<K2BrewAttributes>

  var body: some View {
    BrewCard(
      machineName: context.attributes.machineName,
      stateLabel: context.state.stateLabel,
      phase: context.state.phase,
      accentHex: context.state.accentHex,
      detail: context.state.detail,
      startedAt: context.state.startedAt,
      running: brewIsLive(context)
    )
  }
}
