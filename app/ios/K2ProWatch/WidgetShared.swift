import SwiftUI
import WidgetKit

/// Компактный статус для Smart Stack.
///
/// Пишет его часовое приложение в общий контейнер App Group, читает виджет.
/// Здесь, как и везде на часах, нет правил про кофе: приложение уже всё решило
/// в снимке, а сюда легли только готовые строки, цвет и — если есть чему тикать
/// — абсолютный срок готовности.
///
/// Карточка не притворяется живой. Виджету на часах никто не может доставить
/// поправку в срок: первоклассное пробуждение телефон получает, только если
/// приложение стоит на активном циферблате, а в Smart Stack — обычная очередь,
/// которая доезжает когда доедет. Поэтому здесь нет ни полос, ни расписаний:
/// имя машины, последнее, что мы знали, и приглашение открыть.
struct WidgetStatus: Codable, Equatable {
  /// Когда часы в последний раз что-то знали. По нему считается устаревание:
  /// в Smart Stack виджет живёт своей жизнью и снимок приходит не каждый миг.
  var updatedAt: Date

  /// running | armed | idle | none — что показывать.
  var kind: String
  var title: String
  var line: String

  /// Имя SF Symbol слева.
  var symbol: String
  var accentHex: String

  /// Абсолютный час готовности — единственное, что здесь тикает.
  ///
  /// Ему доставки и не нужны: время назначил человек, оно стоит на месте, и
  /// система отсчитывает до него сама. Всё остальное живое пришлось убрать —
  /// врать оно начинало быстрее, чем мы успевали поправить.
  var deadline: Date?

  static let appGroup = "group.ru.bukharskiy.k2pro"
  static let key = "widgetStatus"

  /// Тот же идентификатор виджета — по нему приложение просит перерисовку.
  static let kind = "K2ProWatchWidget"

  /// Сколько живёт спокойное утверждение о машине.
  static let staleAfter: TimeInterval = 15 * 60

  /// Сколько живёт «идёт пролив».
  ///
  /// Цикл короче трёх минут, и поправить карточку в его конце нечем. Пусть
  /// лучше она молча станет запускалкой, чем будет уверять, что пролив идёт,
  /// когда чашка давно выпита.
  static let runningStaleAfter: TimeInterval = 3 * 60

  var freshFor: TimeInterval {
    kind == "running" ? WidgetStatus.runningStaleAfter : WidgetStatus.staleAfter
  }

  /// Час, после которого верить статусу нельзя.
  var expiresAt: Date { updatedAt.addingTimeInterval(freshFor) }

  var isStale: Bool { Date() >= expiresAt }

  static func load() -> WidgetStatus? {
    guard let data = UserDefaults(suiteName: appGroup)?.data(forKey: key) else {
      return nil
    }
    return try? JSONDecoder().decode(WidgetStatus.self, from: data)
  }

  func save() {
    guard let store = UserDefaults(suiteName: WidgetStatus.appGroup),
          let data = try? JSONEncoder().encode(self)
    else { return }
    store.set(data, forKey: WidgetStatus.key)
  }

  /// Тот же статус, но без утверждений: имя и цвет машины остаются, всё
  /// остальное гаснет. Таким провайдер кладёт кадр на час устаревания — чтобы
  /// карточка потускнела сама, без единой доставки.
  var faded: WidgetStatus {
    var copy = self
    copy.kind = "none"
    copy.line = ""
    copy.symbol = "cup.and.saucer.fill"
    copy.deadline = nil
    return copy
  }
}

// MARK: - Вьюхи (общие для виджета и стенда скриншотов)

/// Прямоугольный виджет Smart Stack — главный формат.
///
/// Это ярлык, а не приборная панель: значок в кружке цвета режима, имя машины
/// и одна строка под ним. Строка говорит последнее, что мы знали, — а когда
/// знать перестали, честно приглашает открыть приложение.
struct WidgetRectangular: View {
  let status: WidgetStatus?

  var body: some View {
    let s = status
    let live = s != nil && !s!.isStale
    let accent = live ? Color(hexString: s!.accentHex) : Color.secondary

    HStack(spacing: 9) {
      ZStack {
        Circle().fill(accent.opacity(0.22))
        Image(systemName: live ? s!.symbol : "cup.and.saucer.fill")
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(accent)
      }
      .frame(width: 30, height: 30)

      VStack(alignment: .leading, spacing: 1) {
        Text(s?.title ?? "K2 Pro")
          .font(.headline)
          .lineLimit(1)
        subtitle(live: live, s: s, accent: accent)
      }

      Spacer(minLength: 0)
    }
  }

  /// Вторая строка. У взведённого таймера — подпись и живой отсчёт: час
  /// готовности назначил человек, он абсолютен, и система докручивает секунды
  /// сама. Во всех прочих случаях — готовая строка с телефона, а если её нет
  /// или ей уже нельзя верить, приглашение открыть.
  @ViewBuilder
  private func subtitle(live: Bool, s: WidgetStatus?, accent: Color) -> some View {
    if live, s!.kind == "armed", let deadline = s!.deadline, deadline > Date() {
      HStack(alignment: .firstTextBaseline, spacing: 4) {
        Text(s!.line)
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(1)
        Text(deadline, style: .timer)
          .font(.system(.caption, design: .rounded).weight(.semibold).monospacedDigit())
          .foregroundStyle(accent)
          .lineLimit(1)
          // Без этого SwiftUI ужимает счётчик до нечитаемого: он резервирует
          // место под самое широкое значение, а в тесной строке отыгрывается
          // на кегле. Пусть лучше подпись слева укоротится — она вторична.
          .fixedSize()
      }
    } else if live, !s!.line.isEmpty {
      Text(s!.line)
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    } else {
      Text("Открыть")
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
  }
}

/// Круглый виджет: значок машины на подложке. Тоже ярлык — крутить тут нечему.
struct WidgetCircular: View {
  let status: WidgetStatus?

  var body: some View {
    let s = status
    let live = s != nil && !s!.isStale
    ZStack {
      AccessoryWidgetBackground()
      Image(systemName: live ? s!.symbol : "cup.and.saucer.fill")
        .font(.system(size: 20))
        .foregroundStyle(live ? Color(hexString: s!.accentHex) : .primary)
    }
  }
}

/// Угловой формат — только для циферблата, в Smart Stack его не бывает.
/// Значок в углу и короткая подпись по дуге.
struct WidgetCorner: View {
  let status: WidgetStatus?

  var body: some View {
    let s = status
    let live = s != nil && !s!.isStale
    Image(systemName: live ? s!.symbol : "cup.and.saucer.fill")
      .font(.title2)
      .foregroundStyle(live ? Color(hexString: s!.accentHex) : .primary)
      .widgetLabel(live && !s!.line.isEmpty ? s!.line : (s?.title ?? "K2 Pro"))
  }
}

/// Строчный виджет: одна строка над временем.
struct WidgetInline: View {
  let status: WidgetStatus?

  var body: some View {
    let s = status
    if let s, !s.isStale {
      Label(s.line.isEmpty ? s.title : "\(s.title) · \(s.line)", systemImage: s.symbol)
    } else {
      // Устарело — знакомое имя машины, если оно есть: «Открывать» человек и
      // так знает, а вот какую машину — подскажем.
      Label(status?.title ?? "K2 Pro", systemImage: "cup.and.saucer.fill")
    }
  }
}

extension Color {
  /// `#RRGGBB`. Непонятную строку не подменяем тихо чёрным — серый заметен.
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
