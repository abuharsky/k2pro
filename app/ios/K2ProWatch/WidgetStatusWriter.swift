import Foundation
import WidgetKit

/// Перекладывает снимок с телефона в компактный статус Smart Stack.
///
/// Здесь и только здесь знают про поля снимка: виджет их уже не видит, ему
/// достаётся готовый [WidgetStatus]. Ни грамма логики про кофе — что «идёт
/// пролив», решено на телефоне полем `running`, что «взведён таймер» — полем
/// `armed`; мы лишь выбираем, какой из этих готовых фактов показать.
enum WidgetStatusWriter {
  /// Чтобы не будить WidgetKit на каждый кадр веса, сравниваем не сырой
  /// статус, а его смысловой отпечаток: бегущие числа система докрутит сама.
  private static var lastDigest: String?

  static func publish(_ snapshot: Snapshot?) {
    let status = derive(snapshot)
    let digest = digestOf(status)
    guard digest != lastDigest else { return }
    lastDigest = digest
    status.save()
    WidgetCenter.shared.reloadTimelines(ofKind: WidgetStatus.kind)
  }

  private static func derive(_ snapshot: Snapshot?) -> WidgetStatus {
    // Время снимка, а не наше: он мог пролежать в хранилище системы час, и
    // выдать его за свежий значило бы соврать про «идёт пролив».
    let now = snapshot?.stampedAt ?? Date()
    guard let snap = snapshot, snap.isConnected, let dev = snap.device else {
      return WidgetStatus(
        updatedAt: now, kind: "none", title: "K2 Pro", line: "",
        symbol: "cup.and.saucer.fill", accentHex: "#FFB000", deadline: nil
      )
    }

    // Идёт пролив. Ни полосы, ни секунд: поправить их на часах нечем, и живое
    // здесь стухало быстрее, чем успевало доехать. Строка с телефона — и всё;
    // через три минуты она сама погаснет до запускалки.
    if dev.running {
      return WidgetStatus(
        updatedAt: now, kind: "running", title: dev.name,
        line: dev.state ?? "", symbol: "drop.fill", accentHex: snap.accent,
        deadline: nil
      )
    }

    // Взведён таймер готовности — единственный честный отсчёт: час назначил
    // человек, он стоит на месте, и система докручивает его сама.
    if let timer = snap.timer, timer.armed, let secs = timer.readyInSeconds {
      return WidgetStatus(
        updatedAt: now, kind: "armed", title: dev.name,
        line: timer.readyLabel, symbol: "clock", accentHex: snap.accent,
        deadline: now.addingTimeInterval(TimeInterval(secs))
      )
    }

    // На связи и в покое — имя и последнее состояние, запуск по тапу.
    return WidgetStatus(
      updatedAt: now, kind: "idle", title: dev.name,
      line: dev.state ?? "", symbol: "cup.and.saucer.fill",
      accentHex: snap.accent, deadline: nil
    )
  }

  /// Отпечаток без бегущих величин.
  ///
  /// Срок готовности телефон пересчитывает от «сейчас», и он дрожит на доли
  /// секунды: перерисовывать из-за этого виджет незачем — берём его с
  /// точностью до минуты.
  private static func digestOf(_ s: WidgetStatus) -> String {
    let deadline = s.deadline.map { Int($0.timeIntervalSince1970 / 60) } ?? -1
    return [
      s.kind, s.title, s.line, s.symbol, s.accentHex, "\(deadline)",
    ].joined(separator: "|")
  }
}
