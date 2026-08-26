import ActivityKit
import Foundation

/// Контракт Live Activity «идёт пролив».
///
/// Общий для двух сторон: приложение (`Runner`) его заводит и обновляет,
/// расширение (`K2ProLiveActivity`) — рисует. Как и у часов, здесь нет ни
/// одного правила про кофе: и статус, и цвет, и подпись приезжают готовыми из
/// Flutter, а Swift только показывает.
///
/// Помечен доступностью 16.1: ActivityKit появился там. В расширении минимум и
/// так 16.1, а в приложении (минимум 15.0) все обращения к типу стоят под
/// `if #available`.
@available(iOS 16.1, *)
struct K2BrewAttributes: ActivityAttributes {
  public struct ContentState: Codable, Hashable {
    /// Крупная строка: «Нагрев», «Пролив», «Готово».
    var stateLabel: String

    /// Ключ фазы для значка: heat | brew | done.
    var phase: String

    /// Акцент строкой `#RRGGBB` — палитра живёт на телефоне.
    var accentHex: String

    /// Вторая строка: «36 → 40 г», когда есть весы; иначе nil.
    var detail: String?

    /// Когда пошёл цикл. От этой метки бейдж тикает время сам, без потока
    /// обновлений: обновляем только когда меняется статус или вес.
    var startedAt: Date

    /// Идёт ли ещё. false — «Готово», секундомер замирает.
    var running: Bool
  }

  /// Имя машины — не меняется за цикл, поэтому в статике, а не в состоянии.
  var machineName: String
}
