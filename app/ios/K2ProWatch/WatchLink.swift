import Foundation
import SwiftUI
import WatchConnectivity

/// Связь с телефоном. Всё состояние приходит оттуда одним снимком.
///
/// Часы ничего не хранят и ничего не вычисляют: нажатие уезжает командой, а
/// правда приезжает следующим снимком. Это снимает целый класс рассинхронов —
/// если машина зажала уставку по своим границам, мы просто покажем её число.
@MainActor
final class WatchLink: NSObject, ObservableObject {
  @Published private(set) var snapshot: Snapshot?

  /// Телефон отвечает. Пока нет — рисовать нечего: показываем это честно, а не
  /// залипшие числа получасовой давности.
  @Published private(set) var reachable = false

  /// Подписи с прошлого сеанса. Когда телефон недоступен, сказать об этом надо
  /// на языке пользователя, а спросить уже не у кого.
  @Published private(set) var cachedStrings: [String: String] = [:]

  private var session: WCSession?
  private static let stringsKey = "cachedStrings"

  override init() {
    super.init()
    cachedStrings =
      UserDefaults.standard.dictionary(forKey: Self.stringsKey) as? [String: String] ?? [:]

    guard WCSession.isSupported() else { return }
    let s = WCSession.default
    s.delegate = self
    s.activate()
    session = s
  }

  func string(_ key: String, _ fallback: String = "") -> String {
    snapshot?.strings[key] ?? cachedStrings[key] ?? fallback
  }

  // MARK: - Команды

  /// Отправить команду телефону.
  ///
  /// Когда телефон досягаем, `sendMessage` доставляет её сразу и возвращает
  /// свежий снимок ответом — лишний круг по эфиру не нужен. Когда нет,
  /// `transferUserInfo` ставит команду в очередь и будит приложение на
  /// телефоне в фоне: обратной дороги (телефон → часы) у пробуждения нет, а
  /// эта — есть.
  func send(_ cmd: String, _ extra: [String: Any] = [:]) {
    var body = extra
    body["cmd"] = cmd
    guard let data = try? JSONSerialization.data(withJSONObject: body),
          let json = String(data: data, encoding: .utf8),
          let s = session, s.activationState == .activated
    else { return }

    if s.isReachable {
      s.sendMessage(["cmd": json]) { [weak self] reply in
        guard let raw = reply["s"] as? String else { return }
        Task { @MainActor in self?.apply(raw) }
      } errorHandler: { [weak self] _ in
        Task { @MainActor in self?.reachable = false }
        s.transferUserInfo(["cmd": json])
      }
    } else {
      s.transferUserInfo(["cmd": json])
    }
  }

  /// Часы открылись — просим телефон прислать актуальную картинку.
  func hello() { send("hello") }

  // MARK: - Приём

  private func apply(_ json: String) {
    guard let data = json.data(using: .utf8),
          let next = try? JSONDecoder().decode(Snapshot.self, from: data)
    else { return }
    // Телефон новее нас: поля могли переехать, рисовать вслепую нельзя.
    guard next.v == Snapshot.supportedVersion else { return }

    reachable = true
    if next.strings != cachedStrings {
      cachedStrings = next.strings
      UserDefaults.standard.set(next.strings, forKey: Self.stringsKey)
    }
    if snapshot != next { snapshot = next }
  }
}

extension WatchLink: WCSessionDelegate {
  nonisolated func session(
    _ session: WCSession,
    activationDidCompleteWith state: WCSessionActivationState,
    error: Error?
  ) {
    Task { @MainActor in
      self.reachable = session.isReachable
      if state == .activated { self.hello() }
    }
  }

  nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
    let now = session.isReachable
    Task { @MainActor in
      self.reachable = now
      // Телефон снова слышит — спрашиваем, что изменилось, пока нас не было.
      if now { self.hello() }
    }
  }

  nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
    guard let json = message["s"] as? String else { return }
    Task { @MainActor in self.apply(json) }
  }

  nonisolated func session(
    _ session: WCSession,
    didReceiveApplicationContext context: [String: Any]
  ) {
    guard let json = context["s"] as? String else { return }
    Task { @MainActor in self.apply(json) }
  }
}
