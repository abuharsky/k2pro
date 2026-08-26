import SwiftUI
import WatchKit

/// Весы как прибор: одна крупная цифра и тара.
///
/// Настраивать здесь нечего — всё, что весы умеют, это показывать вес и
/// обнуляться. Цель по весу и отсечка живут не тут, а в пайплайне машины:
/// это про пролив, а не про взвешивание зерна.
///
/// Экран намеренно пустой. На него смотрят с ложкой в руке, сверху вниз и
/// мельком, поэтому цифре отдано всё место, какое есть.
struct ScaleView: View {
  @EnvironmentObject private var link: WatchLink

  private var scale: Scale? { link.snapshot?.scale }

  var body: some View {
    Group {
      if let scale {
        body(scale)
      } else {
        NoPhoneView()
      }
    }
    .navigationTitle(scale?.name ?? link.string("scale"))
    .navigationBarTitleDisplayMode(.inline)
  }

  private func body(_ s: Scale) -> some View {
    VStack(spacing: 0) {
      Spacer(minLength: 0)

      // Прочерк вместо числа — это не «ноль граммов». Весы могли уснуть по
      // своему таймауту, и показывать их последний вес как живой нельзя.
      Text(s.grams ?? "—")
        .font(K.F.bigValue)
        .foregroundStyle(s.live ? K.text : K.dim)
        .minimumScaleFactor(0.5)
        .lineLimit(1)

      Text(s.live ? s.unit : s.status)
        .font(K.F.hint)
        .foregroundStyle(K.secondary)
        .lineLimit(1)

      Spacer(minLength: 0)

      Button(action: tare) {
        Text(link.string("tare"))
          .font(K.F.cta)
          .foregroundStyle(s.tareEnabled ? K.text : K.dim)
          .frame(maxWidth: .infinity)
          .frame(height: K.M.ctaHeight)
          .background(K.control, in: Capsule())
      }
      .buttonStyle(.plain)
      .disabled(!s.tareEnabled)
      .padding(.horizontal, 10)
      .padding(.bottom, 8)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(K.bg)
    .ignoresSafeArea(edges: .bottom)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        HStack(spacing: 3) {
          StatusDot(
            color: s.live ? K.ready : Color.white.opacity(0.25),
            size: K.M.headerDot
          )
          if let percent = s.batteryPercent {
            Text("\(percent)%").font(K.F.battery).foregroundStyle(K.secondary)
          }
        }
      }
    }
  }

  private func tare() {
    // Отклик здесь важнее обычного: подтверждения весы не шлют, а ноль на
    // экране появится только со следующим отсчётом.
    WKInterfaceDevice.current().play(.success)
    link.send("tare")
  }
}
