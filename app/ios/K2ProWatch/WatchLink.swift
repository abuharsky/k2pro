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
  /// Один на процесс.
  ///
  /// Телефон будит часы в фоне ради Smart Stack, и делегат сессии должен стоять
  /// с первой миллисекунды запуска. При фоновом пробуждении сцена не рисуется
  /// вовсе, `@StateObject` в ней не создаётся — принять снимок было бы некому.
  /// Поэтому связь заводит делегат приложения, а экраны берут готовое.
  static let shared = WatchLink()

  @Published private(set) var snapshot: Snapshot?

  /// Телефон отвечает. Пока нет — рисовать нечего: показываем это честно, а не
  /// залипшие числа получасовой давности.
  @Published private(set) var reachable = false

  /// Подписи с прошлого сеанса. Когда телефон недоступен, сказать об этом надо
  /// на языке пользователя, а спросить уже не у кого.
  @Published private(set) var cachedStrings: [String: String] = [:]

  private var session: WCSession?
  private static let stringsKey = "cachedStrings"

  private override init() {
    super.init()
    cachedStrings =
      UserDefaults.standard.dictionary(forKey: Self.stringsKey) as? [String: String] ?? [:]

    guard WCSession.isSupported() else { return }
    let s = WCSession.default
    s.delegate = self
    s.activate()
    session = s
  }

  /// Подпись по ключу.
  ///
  /// Сначала свежий снимок, за ним подписи прошлого сеанса, и только потом —
  /// собственный перевод часов. У первых двух язык тот, что выбран в
  /// приложении на телефоне; у последнего — системный, потому что телефон мог
  /// выставить язык вручную, а спросить об этом, пока он молчит, некого.
  func string(_ key: String) -> String {
    snapshot?.strings[key] ?? cachedStrings[key] ?? NSLocalizedString(key, comment: "")
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

  /// Проснулись сами, без снимка на руках.
  ///
  /// Спрашивать телефон бесполезно: живой канал работает только когда его
  /// приложение открыто. Зато последний контекст система хранит за нас — он
  /// может быть и часовой давности, но у снимка есть своя метка времени, и
  /// виджет по ней сам решит, верить числам или показать себя устаревшим.
  func catchUp() {
    guard let s = session, s.activationState == .activated else { return }
    if let json = s.receivedApplicationContext["s"] as? String { apply(json) }
    if s.isReachable { hello() }
  }

  #if DEBUG
  /// Подсунуть готовый снимок для съёмки экранов на симуляторе, где телефона
  /// рядом нет. Только в отладке — в релиз этот путь не собирается.
  func injectPreview(_ s: Snapshot) { snapshot = s }
  #endif

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
    // Обновляем Smart Stack тем же снимком: писатель сам отсеет незначимое,
    // чтобы не будить WidgetKit на каждый кадр веса.
    WidgetStatusWriter.publish(next)
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
      guard state == .activated else { return }
      // Пробуждение в фоне: сцены нет, спросить телефон некому и незачем —
      // берём последнее, что система придержала для нас, и пишем виджету.
      if self.snapshot == nil,
         let json = session.receivedApplicationContext["s"] as? String {
        self.apply(json)
      }
      self.hello()
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

  /// Снимок, присланный очередью.
  ///
  /// Этим путём телефон будит нас в фоне ради виджета: живое сообщение до
  /// спящих часов не доходит, а очередь — доходит и поднимает процесс. Всё,
  /// что дальше, делает общий [apply]: он же перепишет статус Smart Stack.
  nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
    guard let json = userInfo["s"] as? String else { return }
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
