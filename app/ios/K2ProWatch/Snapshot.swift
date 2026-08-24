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
  static let supportedVersion = 1

  var v: Int
  var link: String
  var scanning: Bool
  var accent: String
  var accentText: String
  var devices: [DeviceRow]
  var device: Machine?
  var steps: [Step]
  var modes: [ModeOption]
  var cta: Cta
  var strings: [String: String]

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

  /// Вложенные ряды. Есть только у групп — например, у пролива, который на
  /// часах свёрнут в одну строку и раскрывается на своём экране.
  var children: [Step]?

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

  /// Пока машина не на связи, единственное осмысленное действие — подключиться.
  var isConnect: Bool { kind == "connect" }
}
