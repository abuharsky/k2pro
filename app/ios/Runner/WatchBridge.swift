import Flutter
import Foundation
import WatchConnectivity

/// Мост между Flutter-приложением на телефоне и приложением на Apple Watch.
///
/// Здесь нет ни одного правила про кофе: наверх уезжает готовая JSON-строка,
/// вниз приезжают команды. Всё, что мост умеет решать сам, — каким из каналов
/// WatchConnectivity воспользоваться.
final class WatchBridge: NSObject {
  private let channel: FlutterMethodChannel
  private var session: WCSession?

  /// Последний снимок. Нужен, когда часы просыпаются: они спрашивают «что
  /// сейчас», и ответить надо не дожидаясь следующего кадра телеметрии.
  private var latest: String?

  /// Когда последний раз обновляли applicationContext.
  ///
  /// Он переживает и выгрузку приложения на часах, и потерю досягаемости, но
  /// стоит дорого и коалесцируется системой. Живой поток идёт через
  /// sendMessage, а сюда кладём резервную копию раз в пару секунд — чтобы
  /// проснувшиеся часы увидели свежее, а не то, что было полчаса назад.
  private var lastContextAt: Date = .distantPast
  private static let contextInterval: TimeInterval = 2

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "k2pro/watch", binaryMessenger: messenger)
    super.init()

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return result(nil) }
      switch call.method {
      case "push":
        if let json = call.arguments as? String { self.push(json) }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    guard WCSession.isSupported() else { return }
    let s = WCSession.default
    s.delegate = self
    s.activate()
    session = s
  }

  // MARK: - Телефон → часы

  private func push(_ json: String) {
    latest = json
    guard let s = session, s.activationState == .activated else { return }

    // Часы открыты и слушают — отдаём немедленно.
    if s.isReachable {
      s.sendMessage(["s": json], replyHandler: nil, errorHandler: nil)
    }

    // И на всякий случай оставляем последнее известное состояние там, откуда
    // его достанут после пробуждения.
    let now = Date()
    guard now.timeIntervalSince(lastContextAt) >= Self.contextInterval else { return }
    lastContextAt = now
    try? s.updateApplicationContext(["s": json])
  }

  // MARK: - Часы → телефон

  private func forward(_ json: String) {
    DispatchQueue.main.async { [weak self] in
      self?.channel.invokeMethod("command", arguments: json)
    }
  }
}

extension WatchBridge: WCSessionDelegate {
  func session(
    _ session: WCSession,
    activationDidCompleteWith state: WCSessionActivationState,
    error: Error?
  ) {}

  func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
    if let json = message["cmd"] as? String { forward(json) }
  }

  /// Команда, отправленная с часов в очередь.
  ///
  /// Так они шлют всё, что не удалось отдать напрямую: сессия ещё не
  /// активировалась, телефон вне досягаемости или приложение на нём выгружено.
  /// Именно этот путь будит нас в фоне — без него часы, открытые раньше
  /// телефона, молчали бы в пустоту.
  func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
    if let json = userInfo["cmd"] as? String { forward(json) }
  }

  /// Часы снова слышат — отдаём последнее известное состояние немедленно,
  /// не дожидаясь следующего кадра телеметрии.
  func sessionReachabilityDidChange(_ session: WCSession) {
    guard session.isReachable, let json = latest else { return }
    session.sendMessage(["s": json], replyHandler: nil, errorHandler: nil)
  }

  func session(
    _ session: WCSession,
    didReceiveMessage message: [String: Any],
    replyHandler: @escaping ([String: Any]) -> Void
  ) {
    if let json = message["cmd"] as? String { forward(json) }
    // Отвечаем последним снимком: часам после команды нужна свежая картинка,
    // а отдельный запрос на неё — лишний круг по эфиру.
    replyHandler(latest.map { ["s": $0] } ?? [:])
  }

  /// Телефон может остаться без пары или сменить часы — переактивируем сессию,
  /// иначе она молча перестанет доставлять.
  func sessionDidBecomeInactive(_ session: WCSession) {}

  func sessionDidDeactivate(_ session: WCSession) {
    session.activate()
  }
}
