import ActivityKit
import Flutter
import Foundation

/// Мост Live Activity: Flutter решает, когда пролив начался, обновился и
/// кончился, а этот класс переводит это в вызовы ActivityKit.
///
/// Здесь, как и в [WatchBridge], нет ни одного правила про кофе: приходит
/// готовое состояние, уходит — заявка системе. Живёт столько же, сколько
/// приложение: канал держать надо всегда.
///
/// Всё завёрнуто в `if #available(iOS 16.2, *)`: ActivityKit появился там, а
/// само приложение собирается с минимумом 15.0.
final class LiveActivityBridge: NSObject {
  private let channel: FlutterMethodChannel

  /// Текущая активность. Хранится как `Any?`, потому что её тип доступен лишь
  /// с 16.1, а хранимым свойствам аннотацию доступности не поставить.
  private var boxed: Any?

  /// Через сколько карточка объявляет себя протухшей.
  ///
  /// Это страховка от осиротевших активностей: если приложение убили посреди
  /// цикла, обновлять карточку больше некому, а секундомер в ней заведён от
  /// абсолютного времени и тикал бы до вечера. По этому сроку система метит
  /// карточку устаревшей, а вьюха гасит счётчик. Пять минут: заведомо дольше
  /// любого пролива и заведомо короче терпения.
  private static let staleAfter: TimeInterval = 5 * 60

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "k2pro/liveactivity",
      binaryMessenger: messenger
    )
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result)
    }
  }

  private func handle(_ call: FlutterMethodCall, _ result: FlutterResult) {
    guard #available(iOS 16.2, *) else { return result(nil) }
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "sync": sync(args)
    case "start": start(args)
    case "update": update(args)
    case "end": end(args)
    default: return result(FlutterMethodNotImplemented)
    }
    result(nil)
  }

  @available(iOS 16.2, *)
  private var activity: Activity<K2BrewAttributes>? {
    get { boxed as? Activity<K2BrewAttributes> }
    set { boxed = newValue }
  }

  @available(iOS 16.2, *)
  private func contentState(_ a: [String: Any]) -> K2BrewAttributes.ContentState {
    let ms = (a["startedAtMs"] as? NSNumber)?.doubleValue ?? 0
    return K2BrewAttributes.ContentState(
      stateLabel: a["stateLabel"] as? String ?? "",
      phase: a["phase"] as? String ?? "brew",
      accentHex: a["accentHex"] as? String ?? "#FFB100",
      detail: a["detail"] as? String,
      startedAt: Date(timeIntervalSince1970: ms / 1000),
      running: a["running"] as? Bool ?? true
    )
  }

  /// Живое содержимое со сроком протухания.
  @available(iOS 16.2, *)
  private func content(_ a: [String: Any]) -> ActivityContent<K2BrewAttributes.ContentState> {
    ActivityContent(
      state: contentState(a),
      staleDate: Date().addingTimeInterval(Self.staleAfter)
    )
  }

  /// Прибраться после прошлой жизни процесса.
  ///
  /// Live Activity переживает и выгрузку приложения, и его падение — ради того
  /// она и сделана, но нам это выходит боком: ссылку на неё процесс уносит с
  /// собой, а вернуть её ничем нельзя, кроме как спросив систему. Не спросив,
  /// мы получаем осиротевшую карточку, которую уже не закрыть, и рядом с ней
  /// вторую — от нового пролива.
  ///
  /// Идёт ли пролив на самом деле, знает только Flutter, он и говорит. Если
  /// идёт — усыновляем свежайшую карточку и продолжаем в неё писать; если нет
  /// — закрываем всё, что нашлось.
  @available(iOS 16.2, *)
  private func sync(_ a: [String: Any]) {
    let running = a["running"] as? Bool ?? false
    var found = Activity<K2BrewAttributes>.activities
      .sorted { $0.content.state.startedAt > $1.content.state.startedAt }
    let keep = running ? found.first : nil
    if keep != nil { found.removeFirst() }
    dismiss(found)
    activity = keep
    if let keep {
      watch(keep)
      update(a)
    }
  }

  @available(iOS 16.2, *)
  private func start(_ a: [String: Any]) {
    // Активность уже есть — это не старт, а обновление: цикл мог просто
    // сменить фазу до того, как приехал первый снимок.
    if activity != nil { return update(a) }
    guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
    // Чужие карточки от прошлых запусков: обновить их мы уже не можем, а рядом
    // с новой они читались бы как второй пролив.
    dismiss(Activity<K2BrewAttributes>.activities)
    let attributes = K2BrewAttributes(
      machineName: a["machineName"] as? String ?? "K2 Pro"
    )
    activity = try? Activity.request(attributes: attributes, content: content(a))
    if let act = activity { watch(act) }
  }

  @available(iOS 16.2, *)
  private func update(_ a: [String: Any]) {
    guard let act = activity else { return start(a) }
    Task { await act.update(content(a)) }
  }

  @available(iOS 16.2, *)
  private func end(_ a: [String: Any]) {
    guard let act = activity else { return }
    activity = nil
    let content = ActivityContent(state: contentState(a), staleDate: nil)
    // Держим «Готово» на экране недолго после конца — увидеть итог, но не
    // засорять экран блокировки надолго.
    Task { await act.end(content, dismissalPolicy: .after(.now + 8)) }
  }

  @available(iOS 16.2, *)
  private func dismiss(_ activities: [Activity<K2BrewAttributes>]) {
    for act in activities {
      Task { await act.end(nil, dismissalPolicy: .immediate) }
    }
  }

  /// Карточку могли закрыть без нас — человек смахнул её, или вышел срок
  /// показа. Ссылку на закрытую надо отпустить: писать в неё бесполезно, а
  /// пока она у нас в руках, следующий пролив не заведёт новую и не покажется
  /// вовсе.
  @available(iOS 16.2, *)
  private func watch(_ act: Activity<K2BrewAttributes>) {
    Task { [weak self] in
      for await state in act.activityStateUpdates {
        guard state == .dismissed || state == .ended else { continue }
        await MainActor.run {
          guard #available(iOS 16.2, *), self?.activity?.id == act.id else { return }
          self?.activity = nil
        }
        return
      }
    }
  }
}
