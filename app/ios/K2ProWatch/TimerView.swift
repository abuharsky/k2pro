import SwiftUI
import WatchKit

/// Отложенный старт: время крупно, сдвиг по четверти часа и один тумблер.
///
/// Значение — минуты от полуночи, как в контракте. Шаг и границы тоже оттуда:
/// своих часы не выдумывают.
struct TimerView: View {
  @EnvironmentObject private var link: WatchLink
  @Environment(\.dismiss) private var dismiss

  @State private var minutes: Int?

  private var step: Step? {
    link.snapshot?.steps.first { $0.editor == "timer" }
  }

  /// Взведён ли таймер сейчас. Признак — подсветка ряда: телефон её ставит
  /// ровно тогда, когда машина ждёт своего часа.
  private var armed: Bool { step?.highlighted ?? false }

  var body: some View {
    Group {
      if let step {
        editor(step)
      } else {
        NoPhoneView()
      }
    }
    .navigationTitle(link.string("timer"))
    .navigationBarTitleDisplayMode(.inline)
  }

  private func editor(_ step: Step) -> some View {
    let current = minutes ?? step.editValue
    return VStack(spacing: 4) {
      Spacer(minLength: 0)
      Text(clock(current))
        .font(K.F.bigTime)
        .foregroundStyle(armed ? Color(hex: step.tone) : K.text)
      Text(step.hint)
        .font(K.F.hint)
        .foregroundStyle(K.secondary)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 6)
      Spacer(minLength: 0)

      HStack(spacing: 6) {
        ShiftButton(label: "−\(step.stride)") { shift(step, -step.stride) }
        ShiftButton(label: "+\(step.stride)") { shift(step, step.stride) }
      }

      Button {
        WKInterfaceDevice.current().play(armed ? .stop : .start)
        link.send("setTimer", ["minutes": current, "on": !armed])
        // Решение принято — возвращаемся к пайплайну.
        dismiss()
      } label: {
        Text(armed ? link.string("disable") : link.string("enable"))
          .font(K.F.cta)
          .foregroundStyle(armed ? K.text : Color(hex: "#0D0F12"))
          .frame(maxWidth: .infinity)
          .frame(height: K.M.ctaHeight)
          .background(armed ? K.control : Color(hex: step.tone), in: Capsule())
      }
      .buttonStyle(.plain)
    }
    .padding(.horizontal, 4)
    .padding(.bottom, 2)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(K.bg)
    .onAppear { minutes = step.editValue }
  }

  /// Время идёт по кругу: с 23:45 плюс четверть часа — это 00:00.
  private func shift(_ step: Step, _ delta: Int) {
    let span = step.max + 1
    let next = (((minutes ?? step.editValue) + delta) % span + span) % span
    minutes = next
    WKInterfaceDevice.current().play(delta > 0 ? .directionUp : .directionDown)
    // Пока таймер взведён, крутить время — значит переносить срабатывание.
    if armed { link.send("setTimer", ["minutes": next, "on": true]) }
  }

  private func clock(_ m: Int) -> String {
    String(format: "%02d:%02d", (m / 60) % 24, m % 60)
  }
}

struct ShiftButton: View {
  let label: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(label)
        .font(K.F.shift)
        .foregroundStyle(K.text)
        .frame(maxWidth: .infinity)
        .frame(height: K.M.shiftHeight)
        .background(K.control, in: RoundedRectangle(cornerRadius: 16))
    }
    .buttonStyle(.plain)
  }
}
