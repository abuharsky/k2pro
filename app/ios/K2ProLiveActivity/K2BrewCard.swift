import SwiftUI
import UIKit

/// Карточка пролива — общая начинка Live Activity.
///
/// Свободна от ActivityKit нарочно: этой же вьюхой рисует и экран блокировки
/// (через [LockScreenView]), и стенд для скриншотов в приложении. Данные —
/// простыми полями, а не `ActivityViewContext`, чтобы её можно было собрать
/// где угодно, а не только внутри системного рендера активности.
@available(iOS 16.0, *)
struct BrewCard: View {
  let machineName: String
  let stateLabel: String
  let phase: String
  let accentHex: String
  let detail: String?
  let startedAt: Date
  let running: Bool

  var body: some View {
    let accent = Color(hexString: accentHex)
    HStack(spacing: 14) {
      PhaseGlyph(phase: phase, color: accent, size: 30)

      VStack(alignment: .leading, spacing: 3) {
        Text(stateLabel)
          .font(.headline)
          .foregroundStyle(accent)
        Text(machineName)
          .font(.caption)
          .foregroundStyle(.secondary)
        if let detail {
          Text(detail)
            .font(.system(.subheadline, design: .rounded).monospacedDigit())
            .foregroundStyle(.primary)
        }
      }

      Spacer(minLength: 8)

      TimeBadge(
        running: running,
        startedAt: startedAt,
        color: accent,
        size: 34,
        weight: .semibold
      )
      .foregroundStyle(.primary)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
  }
}

/// Секундомер: пока идёт цикл — тикает сам от `startedAt`; кончился — галочка.
///
/// Ширину задаём сами, и это главное здесь. Системный тикающий текст просит
/// под себя куда больше, чем занимают цифры, и рисует их по левому краю
/// запрошенного: на кегле 13 замер показал коробку в 85 точек под «0:50»
/// шириной 28 — полсотни точек пустоты. От них пилюля Dynamic Island
/// растягивалась почти во весь экран, а на карточке за временем зияла дыра до
/// самого края. Рамка объявляет разметке честную ширину строки «0:00»,
/// померенную тем же шрифтом; цифры в ней встают влево и укладываются с
/// запасом. `fixedSize` сюда не годится — с ним системный текст не рисуется
/// вовсе.
@available(iOS 16.0, *)
struct TimeBadge: View {
  let running: Bool
  let startedAt: Date
  let color: Color

  /// Кегль и насыщенность — свои, а не из окружения: по ним же считается
  /// ширина мерки, и разъехаться они не должны.
  var size: CGFloat
  var weight: Font.Weight = .regular

  private var font: Font {
    .system(size: size, weight: weight, design: .rounded).monospacedDigit()
  }

  /// Мерка. За десять минут цикл переваливает редко, и лишний разряд лучше
  /// показать с напуском вправо, чем всё время держать под него пустоту.
  private var template: String {
    Date().timeIntervalSince(startedAt) >= 600 ? "00:00" : "0:00"
  }

  /// Ширина мерки тем же шрифтом, каким рисуются цифры, плюс запасной разряд.
  ///
  /// Разряд не для красоты: ровно по мерке системный текст срезает первую
  /// цифру — «0:46» превращается в «:46». Запас в один моноширинный знак
  /// снимает это и стоит копейки.
  private var width: CGFloat {
    let base = UIFont.monospacedDigitSystemFont(ofSize: size, weight: uiWeight)
    let rounded = base.fontDescriptor.withDesign(.rounded).map {
      UIFont(descriptor: $0, size: size)
    }
    let font = rounded ?? base
    let measure = { (s: String) in (s as NSString).size(withAttributes: [.font: font]).width }
    return ceil(measure(template) + measure("0"))
  }

  /// Запасной разряд: рисовать его надо, а вот занимать им место — нет.
  private var spare: CGFloat {
    let base = UIFont.monospacedDigitSystemFont(ofSize: size, weight: uiWeight)
    let rounded = base.fontDescriptor.withDesign(.rounded).map {
      UIFont(descriptor: $0, size: size)
    }
    return ceil(("0" as NSString).size(withAttributes: [.font: rounded ?? base]).width)
  }

  private var uiWeight: UIFont.Weight {
    switch weight {
    case .semibold: return .semibold
    case .bold: return .bold
    case .medium: return .medium
    default: return .regular
    }
  }

  var body: some View {
    if running {
      // Час — заведомо больше любого цикла; на конце диапазона счёт замирает,
      // и пусть лучше это будет 60:00, чем всегда пустое место под часы.
      Text(
        timerInterval: startedAt...startedAt.addingTimeInterval(3600),
        countsDown: false,
        showsHours: false
      )
      .font(font)
      .frame(width: width, alignment: .leading)
      .padding(.trailing, -spare)
    } else {
      Image(systemName: "checkmark.circle.fill")
        .font(font)
        .foregroundStyle(color)
    }
  }
}

/// Значок фазы системными символами: расширение лёгкое, свои контуры сюда
/// тащить незачем.
///
/// Размер — кеглем, а не рамкой. Квадратная рамка с `resizable` подгоняла под
/// себя высоту, а ширину оставляла свою: у капли и градусника она заметно
/// меньше квадрата, и по бокам оставался воздух. В пилюле Dynamic Island этот
/// воздух читался как кривой отступ от края.
@available(iOS 16.0, *)
struct PhaseGlyph: View {
  let phase: String
  let color: Color
  var size: CGFloat = 16

  private var symbol: String {
    switch phase {
    case "heat": return "thermometer.medium"
    case "done": return "checkmark.seal.fill"
    default: return "drop.fill"
    }
  }

  var body: some View {
    Image(systemName: symbol)
      .font(.system(size: size))
      .foregroundStyle(color)
  }
}

extension Color {
  /// `#RRGGBB` с телефона. Непонятную строку не подменяем тихо чёрным — серый
  /// заметен и не выглядит как «так и было задумано».
  init(hexString: String) {
    let raw = hexString.hasPrefix("#") ? String(hexString.dropFirst()) : hexString
    guard raw.count == 6, let v = UInt32(raw, radix: 16) else {
      self = Color(white: 0.5)
      return
    }
    self.init(
      red: Double((v >> 16) & 0xFF) / 255,
      green: Double((v >> 8) & 0xFF) / 255,
      blue: Double(v & 0xFF) / 255
    )
  }
}
