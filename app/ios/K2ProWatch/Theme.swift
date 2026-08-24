import SwiftUI

/// Хром интерфейса: фон, ячейки, текст.
///
/// Здесь только структурные цвета. Всё, что несёт смысл — акцент режима, цвет
/// фазы, заливка кнопки — приезжает с телефона строкой `#RRGGBB`, чтобы
/// палитра жила в одном месте, а не в двух.
enum K {
  static let bg = Color.black
  static let cell = Color(hex: "#1C1F26")
  static let cellPassed = Color(hex: "#262A31")
  static let control = Color(hex: "#2A2E36")

  static let text = Color(hex: "#F2F4F7")
  static let secondary = Color(hex: "#8B919A")
  static let dim = Color(hex: "#6E7681")

  static let ready = Color(hex: "#5EC26A")

  /// Спецификация нарисована в 2× от логических точек Apple Watch 45 мм.
  /// Всё, что взято из неё в пикселях, делится пополам — вот эти числа.
  enum M {
    static let cellRadius: CGFloat = 14
    static let cellPadding: CGFloat = 8
    static let rowIcon: CGFloat = 18
    /// Спецификация просит 84 px (42 pt), но на 45 мм это восьмая часть
    /// экрана под одну кнопку. Тридцать четыре и палец находит, и список
    /// не душит.
    static let ctaHeight: CGFloat = 40

    /// «Стоп» на экране работы. В него целятся на ходу и вслепую, поэтому он
    /// заметно крупнее обычного действия.
    static let stopHeight: CGFloat = 58
    static let stepperHeight: CGFloat = 42
    static let shiftHeight: CGFloat = 32
    static let progressBar: CGFloat = 3.5
    static let statusDot: CGFloat = 7
    static let headerDot: CGFloat = 6
  }

  /// Кегли крупнее, чем в спецификации.
  ///
  /// Спецификация нарисована для разглядывания макета на мониторе, а часы
  /// смотрят мельком и с вытянутой руки. Одиннадцать пунктов подписи там
  /// читаются, на запястье — нет.
  enum F {
    static let screenTitle = Font.system(size: 17, weight: .bold)
    static let rowLabel = Font.system(size: 13, weight: .semibold)
    static let rowValue = Font.system(size: 21, weight: .bold).monospacedDigit()
    static let deviceName = Font.system(size: 17, weight: .bold)
    static let bigValue = Font.system(size: 46, weight: .light).monospacedDigit()
    static let bigTime = Font.system(size: 42, weight: .light).monospacedDigit()
    static let cta = Font.system(size: 17, weight: .bold)
    static let stop = Font.system(size: 22, weight: .bold)
    static let hint = Font.system(size: 15)
    static let shift = Font.system(size: 15, weight: .semibold)
    static let battery = Font.system(size: 13, weight: .semibold).monospacedDigit()
  }
}

extension Color {
  /// `#RRGGBB` с телефона. Непонятную строку не подменяем тихо на чёрный —
  /// серый заметен и не выглядит как «так и было задумано».
  init(hex: String) {
    let raw = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
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

/// Заряд машины: четыре деления — ровно столько же, сколько светится на её
/// корпусе. Процент под ними — то же самое число словами.
struct BatteryGauge: View {
  let level: Int
  let percent: Int?
  var charging = false

  var body: some View {
    VStack(spacing: 2) {
      HStack(spacing: 1.5) {
        ForEach(0..<4, id: \.self) { i in
          RoundedRectangle(cornerRadius: 1)
            .fill(i < level ? K.text : Color.white.opacity(0.18))
            .frame(width: 3.5, height: 6)
        }
      }
      .padding(1.5)
      .overlay(
        RoundedRectangle(cornerRadius: 3.5)
          .stroke(Color.white.opacity(0.28), lineWidth: 1)
      )
      if let percent {
        Text(charging ? "\(percent)%⚡︎" : "\(percent)%")
          .font(K.F.battery)
          .foregroundStyle(K.secondary)
      }
    }
  }
}

/// Точка состояния: зелёная — машина готова, акцентная — работает.
struct StatusDot: View {
  let color: Color
  var size: CGFloat = K.M.statusDot

  var body: some View {
    Circle().fill(color).frame(width: size, height: size)
  }
}
