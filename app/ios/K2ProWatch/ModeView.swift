import SwiftUI
import WatchKit

/// Выбор режима: три ячейки, выбранная залита своим акцентом.
///
/// Режим общий — он действует и на ручной пуск, и на отложенный. Если таймер
/// уже взведён, телефон перепишет задание в машину сам: здесь об этом знать
/// не нужно.
struct ModeView: View {
  @EnvironmentObject private var link: WatchLink
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    Group {
      if let snap = link.snapshot {
        list(snap)
      } else {
        NoPhoneView()
      }
    }
    .navigationTitle(link.string("mode"))
    .navigationBarTitleDisplayMode(.inline)
  }

  private func list(_ snap: Snapshot) -> some View {
    ScrollView {
      LazyVStack(spacing: 6) {
        ForEach(snap.modes) { m in
          Button {
            WKInterfaceDevice.current().play(.click)
            link.send("setMode", ["value": m.value])
            // Одно решение из трёх — задерживаться в списке незачем.
            dismiss()
          } label: {
            row(m)
          }
          .buttonStyle(.plain)
        }
      }
      .padding(.horizontal, 4)
    }
    .background(K.bg)
  }

  private func row(_ m: ModeOption) -> some View {
    let accent = Color(hex: m.accentText)
    return HStack(spacing: 8) {
      PipeIcon(name: m.icon, color: accent)
      Text(m.label)
        .font(K.F.deviceName)
        .foregroundStyle(K.text)
        .lineLimit(2)
      Spacer(minLength: 2)
      if m.selected {
        Image(systemName: "checkmark")
          .font(.system(size: 12, weight: .bold))
          .foregroundStyle(accent)
      }
    }
    .padding(K.M.cellPadding)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: K.M.cellRadius)
        .fill(m.selected ? Color(hex: m.accent).opacity(0.18) : K.cell)
    )
  }
}
