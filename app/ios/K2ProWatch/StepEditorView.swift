import SwiftUI
import WatchKit

/// Общий редактор числового шага: большое значение, подсказка, минус и плюс.
///
/// Экран один на все шаги — он не знает, что крутит. Границы, шаг и приписку к
/// числу присылает телефон вместе с самим шагом.
struct StepEditorView: View {
  @EnvironmentObject private var link: WatchLink
  let stepId: String

  /// Локальная копия значения.
  ///
  /// Она намеренно не переспрашивает снимок, пока экран открыт: телефон
  /// присылает телеметрию раз в секунду, и число под пальцем прыгало бы назад
  /// на каждом кадре, пока правка идёт в машину.
  @State private var value: Int?
  @State private var crown: Double = 0

  private var step: Step? { link.snapshot?.step(stepId) }

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
    return VStack(spacing: 4) {
      Spacer(minLength: 0)
      Text("\(current)\(step.unit)")
        .font(K.F.bigValue)
        .foregroundStyle(Color(hex: step.tone))
      Text(step.hint)
        .font(K.F.hint)
        .foregroundStyle(K.secondary)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 6)
      Spacer(minLength: 0)

      HStack(spacing: 6) {
        RoundButton(symbol: "minus", enabled: current > step.min) {
          bump(step, by: -step.stride)
        }
        RoundButton(symbol: "plus", enabled: current < step.max) {
          bump(step, by: step.stride)
        }
      }
    }
    .padding(.horizontal, 4)
    .padding(.bottom, 2)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(K.bg)
    // Колесо — то, чего от часов ждут: 70 секунд экстракции кнопками это 70
    // нажатий, а короной — одно движение.
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
      push(step, next)
    }
  }

  private func bump(_ step: Step, by delta: Int) {
    let next = min(step.max, max(step.min, (value ?? step.editValue) + delta))
    guard next != value else { return }
    value = next
    crown = Double(next)
    WKInterfaceDevice.current().play(delta > 0 ? .directionUp : .directionDown)
    push(step, next)
  }

  private func push(_ step: Step, _ next: Int) {
    link.send("setStep", ["id": step.id, "value": next])
  }
}

extension Step {
  /// Шаг изменения. Ноль в контракте означает «на единицу» — так проще на
  /// стороне телефона, где у большинства уставок шаг именно такой.
  var stride: Int { step > 0 ? step : 1 }
}

extension String {
  var capitalizedFirst: String {
    guard let f = first else { return self }
    return f.uppercased() + dropFirst().lowercased()
  }
}

/// Круглая кнопка редактора.
struct RoundButton: View {
  let symbol: String
  var enabled = true
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: 24, weight: .medium))
        .foregroundStyle(enabled ? K.text : K.dim)
        .frame(maxWidth: .infinity)
        .frame(height: K.M.stepperHeight)
        .background(K.control, in: Capsule())
    }
    .buttonStyle(.plain)
    .disabled(!enabled)
  }
}
