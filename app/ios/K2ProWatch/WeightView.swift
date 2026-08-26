import SwiftUI
import WatchKit

/// Ряд «вес» пайплайна: чем кончится пролив.
///
/// Отдельный экран, а не общий редактор числа, потому что цифра тут не одна:
/// цель без отсечки — просто справка, а отсечка без цели ничего не значит.
/// Порядок тот же, что в телефоне: сначала «рубить по весу», под ним цель.
///
/// Отсечка стоит первой и по смыслу: весы на связи ещё не значат, что они
/// участвуют в проливе, — они могут просто лежать на столе.
struct WeightView: View {
  @EnvironmentObject private var link: WatchLink

  /// Локальная копия цели — по той же причине, что и в общем редакторе:
  /// телеметрия идёт раз в секунду, и число под пальцем прыгало бы назад.
  @State private var value: Int?
  @State private var crown: Double = 0

  private var step: Step? { link.snapshot?.step("weight") }
  private var scale: Scale? { link.snapshot?.scale }

  var body: some View {
    Group {
      if let step {
        editor(step)
      } else {
        NoPhoneView()
      }
    }
    .navigationTitle(step.map { $0.label.capitalizedFirst } ?? "")
    .navigationBarTitleDisplayMode(.inline)
  }

  private func editor(_ step: Step) -> some View {
    let current = value ?? step.editValue
    let armed = scale?.stopOnYield ?? false
    let canArm = scale?.canAutoStop ?? false

    return VStack(spacing: 6) {
      Spacer(minLength: 0)

      Text(step.text(current))
        .font(K.F.bigValue)
        .foregroundStyle(Color(hex: step.tone))
        .minimumScaleFactor(0.6)
        .lineLimit(1)

      // Живой вес важнее подсказки: с него видно, доедет ли пролив до цели.
      Text(liveHint(step))
        .font(K.F.hint)
        .foregroundStyle(K.secondary)
        .lineLimit(1)

      Spacer(minLength: 0)

      HStack(spacing: 6) {
        RoundButton(symbol: "minus", enabled: current > step.min) {
          bump(step, by: -step.stride)
        }
        RoundButton(symbol: "plus", enabled: current < step.max) {
          bump(step, by: step.stride)
        }
      }

      Button { toggle(armed) } label: {
        HStack(spacing: 6) {
          Image(systemName: armed ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 15, weight: .semibold))
          Text(link.string("autoStop"))
            .font(K.F.rowLabel)
            .lineLimit(1)
        }
        .foregroundStyle(canArm ? (armed ? K.text : K.secondary) : K.dim)
        .frame(maxWidth: .infinity)
        .frame(height: K.M.ctaHeight)
        .background(K.control, in: Capsule())
      }
      .buttonStyle(.plain)
      .disabled(!canArm)
    }
    .padding(.horizontal, 4)
    .padding(.bottom, 2)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(K.bg)
    .focusable()
    .digitalCrownRotation(
      $crown,
      from: Double(step.min),
      through: Double(step.max),
      by: Double(step.stride),
      sensitivity: .medium,
      isContinuous: false
    )
    .onAppear {
      value = step.editValue
      crown = Double(step.editValue)
    }
    .onChange(of: crown) { _, now in
      let next = Int(now.rounded())
      guard next != (value ?? step.editValue) else { return }
      value = next
      push(next)
    }
  }

  /// Что писать под целью. Пока весы живые — сколько на них сейчас; иначе то,
  /// что с ними не так, потому что без них цель ни на что не влияет.
  private func liveHint(_ step: Step) -> String {
    guard let scale else { return step.hint }
    if let grams = scale.grams, scale.live {
      return "\(grams) \(scale.unit)"
    }
    return scale.status
  }

  private func bump(_ step: Step, by delta: Int) {
    let next = min(step.max, max(step.min, (value ?? step.editValue) + delta))
    guard next != value else { return }
    value = next
    crown = Double(next)
    WKInterfaceDevice.current().play(delta > 0 ? .directionUp : .directionDown)
    push(next)
  }

  /// Цель уезжает десятыми долями грамма: редактор целочисленный, а полграмма
  /// на выходе — разница, которую слышно в чашке.
  private func push(_ next: Int) {
    link.send("setYield", ["value": next])
  }

  private func toggle(_ armed: Bool) {
    WKInterfaceDevice.current().play(.click)
    link.send("setAutoStop", ["on": !armed])
  }
}
