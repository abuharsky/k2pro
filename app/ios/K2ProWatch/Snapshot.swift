import Foundation

/// Зеркало контракта из `lib/watch/watch_snapshot.dart`.
///
/// Здесь нет ни одного правила про кофе: ни какие шаги бывают, ни что нагрева
/// не бывает при холодном проливе, ни в каких границах живёт температура. Всё
/// это решает телефон и присылает готовым. Проверка простая: если у машины
/// появится восьмой шаг, часы покажут его без единой правки в Swift.
struct Snapshot: Codable, Equatable {
  /// Версия контракта. Чужую не рисуем — лучше честная заглушка, чем экран с
  /// перепутанными полями.
  static let supportedVersion = 3

  var v: Int

  /// Когда телефон собрал снимок, в миллисекундах эпохи.
  ///
  /// Нужна ровно для честности виджета: снимок может приехать не из эфира, а
  /// из хранилища системы — там лежит последний контекст, и ему бывает час
  /// отроду. Необязательное: снимок мог собрать телефон постарше.
  var at: Double?

  var link: String
  var scanning: Bool
  var accent: String
  var accentText: String
  var devices: [DeviceRow]
  var device: Machine?

  /// Весы, если телефон их знает. Отсутствуют — значит нет ни строки в
  /// списке, ни ряда веса в пайплайне.
  var scale: Scale?
  var steps: [Step]
  var modes: [ModeOption]
  var cta: Cta
  var timer: Timer?
  var strings: [String: String]

  /// Возраст снимка. Без метки считаем его свежим: старый телефон её не шлёт,
  /// а вечно протухшим виджетом делу не поможешь.
  var stampedAt: Date { at.map { Date(timeIntervalSince1970: $0 / 1000) } ?? Date() }

  var isConnected: Bool { link == "connected" }
  var isConnecting: Bool { link == "connecting" }

  /// Ряд по идентификатору — в том числе вложенный в группу.
  func step(_ id: String) -> Step? {
    for row in steps {
      if row.id == id { return row }
      if let hit = row.children?.first(where: { $0.id == id }) { return hit }
    }
    return nil
  }
}

struct DeviceRow: Codable, Equatable, Identifiable {
  var id: String

  /// `machine` или `scale`. Решает, куда ведёт тап: машина открывает
  /// пайплайн, весы — свой прибор.
  var kind: String

  var name: String
  var rssi: Int?
  var connected: Bool

  /// Своя машина: подключена сейчас или запомнена телефоном. Такая строка есть
  /// в списке всегда, даже когда эфир пуст.
  var known: Bool
  var status: String
  var battery: Int?
  var batteryPercent: Int?
  var charging: Bool

  var isScale: Bool { kind == "scale" }
}

/// Весы как прибор. Всё уже посчитано и отформатировано телефоном: часы
/// показывают строку, а не пересчитывают граммы.
struct Scale: Codable, Equatable {
  var id: String
  var name: String
  var connected: Bool

  /// Отсчёты идут. Только в этом состоянии числу можно верить: линия может
  /// быть, а весы — уже спать.
  var live: Bool
  var asleep: Bool
  var status: String

  /// Живой вес, готовой строкой. nil — верить нечему, показываем прочерк.
  var grams: String?
  var unit: String
  var batteryPercent: Int?

  /// Цель по весу, той же строкой.
  var target: String
  var stopOnYield: Bool

  /// Переключать отсечку сейчас можно: есть чем мерить и машина не в работе.
  var canAutoStop: Bool
  var tareEnabled: Bool
}

struct Machine: Codable, Equatable {
  var id: String?
  var name: String
  var battery: Int?
  var batteryPercent: Int?
  var charging: Bool
  var state: String?
  var running: Bool

  var model: String?
  var error: String?
}

/// Ряд пайплайна. `editor` решает, какой экран откроется по тапу, а границы
/// приезжают вместе со значением — своих часы не выдумывают.
struct Step: Codable, Equatable, Identifiable {
  var id: String
  var icon: String
  var label: String
  var value: String
  var tone: String
  var mark: String
  var progress: Double?
  var highlighted: Bool
  var editable: Bool
  var editor: String
  var editValue: Int
  var min: Int
  var max: Int
  var step: Int
  var unit: String
  var hint: String

  /// Сколько знаков после запятой в значении редактора. Отсутствует — число
  /// целое. Цель по весу приезжает в десятых долях грамма, потому что
  /// редактор на часах один на все шаги и дробей не знает.
  var decimals: Int?

  /// Вложенные ряды. Есть только у групп — например, у пролива, который на
  /// часах свёрнут в одну строку и раскрывается на своём экране.
  var children: [Step]?

  /// Значение редактора так, как его читает человек: с запятой, если
  /// телефон попросил, и с приписанной единицей.
  func text(_ raw: Int) -> String {
    guard let decimals, decimals > 0 else { return "\(raw)\(unit)" }
    let divisor = pow(10.0, Double(decimals))
    let number = String(format: "%.\(decimals)f", Double(raw) / divisor)
    return unit.isEmpty ? number : "\(number) \(unit)"
  }

  var isActive: Bool { mark == "active" }
  var isPassed: Bool { mark == "passed" }
  var isError: Bool { mark == "error" }
}

struct ModeOption: Codable, Equatable, Identifiable {
  var value: Int
  var label: String
  var icon: String
  var accent: String
  var accentText: String
  var selected: Bool

  var id: Int { value }
}

struct Cta: Codable, Equatable {
  var kind: String
  var label: String
  var bg: String
  var fg: String

  /// Команда ушла, машина ещё не подтвердила: вместо подписи — ожидание.
  var busy: Bool
  var hold: Bool?

  /// Пока машина не на связи, единственное осмысленное действие — подключиться.
  var isConnect: Bool { kind == "connect" }
}

/// Таймер готовности. Всё уже посчитано телефоном: часы показывают пресеты,
/// а когда взведён — тикают отсчёт от `readyInSeconds` сами.
struct Timer: Codable, Equatable {
  var armed: Bool

  /// Пресеты «готов через N минут».
  var presets: [Int]

  /// «мин» под крупным числом пресета.
  var presetUnit: String
  var hint: String

  /// Минуты от полуночи — начальное положение колёс «своё время».
  var byTime: Int

  var readyLabel: String

  /// Сколько секунд до готовности на момент снимка. nil — не взведён.
  var readyInSeconds: Int?

  /// «Старт в 07:20 · Полный», готовой строкой. nil — не взведён.
  var startLine: String?

  var cancel: String
  var enable: String
}
