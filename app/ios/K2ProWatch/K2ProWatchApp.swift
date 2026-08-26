import SwiftUI
import WatchConnectivity
import WatchKit

/// Делегат нужен ровно за одним: поднять связь с телефоном в момент запуска
/// процесса, а не в момент отрисовки первого экрана.
///
/// Часы будят в фоне, чтобы обновить Smart Stack. В таком запуске сцены нет, а
/// значит нет и `@StateObject` — снимок приехал бы в пустоту, и виджет остался
/// бы с позавчерашним статусом. Здесь мы просто трогаем общую связь: её
/// инициализатор активирует сессию и ставит делегата.
final class WatchAppDelegate: NSObject, WKApplicationDelegate {
  /// Задачи очереди WatchConnectivity, которые ещё рано закрывать.
  private var pending: [WKWatchConnectivityRefreshBackgroundTask] = []

  /// Сколько раз уже заглядывали, всё ли доехало. Ждать бесконечно нельзя:
  /// незакрытая задача — та же беда, от которой мы лечимся.
  private var looks = 0

  /// Как часто просыпаться самим. Чаще watchOS всё равно не пустит, а реже —
  /// значит показывать позавчерашнее.
  private static let selfWake: TimeInterval = 15 * 60

  func applicationDidFinishLaunching() {
    MainActor.assumeIsolated { _ = WatchLink.shared }
    Self.scheduleSelfWake()
  }

  /// Фоновые задачи.
  ///
  /// Без этого метода Smart Stack и не мог обновляться. watchOS будит
  /// приложение задачей и ждёт, что её закроют; пока она не закрыта,
  /// приложение считается зависшим, а незакрытые задачи система запоминает и
  /// урезает будущие пробуждения. Мы же раньше просто не отвечали: снимок
  /// доезжал до делегата, а дописать статус виджету процесс уже не успевал.
  func handle(_ tasks: Set<WKRefreshBackgroundTask>) {
    for task in tasks {
      switch task {
      case let t as WKWatchConnectivityRefreshBackgroundTask:
        // Данные отдаёт делегат сессии, и отдаёт не мгновенно. Закрыть задачу
        // раньше времени — значит уснуть на полуслове.
        pending.append(t)
        drain()
      case let t as WKApplicationRefreshBackgroundTask:
        MainActor.assumeIsolated { WatchLink.shared.catchUp() }
        Self.scheduleSelfWake()
        t.setTaskCompletedWithSnapshot(false)
      default:
        task.setTaskCompletedWithSnapshot(false)
      }
    }
  }

  /// Закрыть задачи, когда сессия всё доставила.
  private func drain() {
    let s = WCSession.default
    let ready = s.activationState == .activated && !s.hasContentPending
    guard ready || looks >= 40 else {
      looks += 1
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.drain() }
      return
    }
    looks = 0
    let done = pending
    pending.removeAll()
    // Снимок экрана приложения нам не нужен: обновляем виджет, а не витрину.
    for t in done { t.setTaskCompletedWithSnapshot(false) }
  }

  /// Попроситься проснуться самим.
  ///
  /// Страховка на случай, когда телефон нас не будит: очередь WatchConnectivity
  /// поднимает часы только по своему усмотрению, а живой канал требует, чтобы
  /// приложение уже было открыто. Здесь мы хотя бы раз в четверть часа
  /// перечитаем последний контекст и перепишем статус.
  static func scheduleSelfWake() {
    WKApplication.shared().scheduleBackgroundRefresh(
      withPreferredDate: Date().addingTimeInterval(selfWake),
      userInfo: nil,
      scheduledCompletion: { _ in }
    )
  }
}

@main
struct K2ProWatchApp: App {
  @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var delegate
  @StateObject private var link = WatchLink.shared

  var body: some Scene {
    WindowGroup {
      #if DEBUG
      if let route = PreviewHarness.route {
        PreviewRoot(route: route).environmentObject(link)
      } else {
        RootView().environmentObject(link)
      }
      #else
      RootView().environmentObject(link)
      #endif
    }
  }
}

/// Куда можно уйти с корневого экрана. Навигация целиком локальная: гонять
/// каждый переход через WatchConnectivity — значит сделать часы вялыми.
enum Route: Hashable {
  case pipeline
  case timer
  case mode
  case step(String)
  case group(String)

  /// Весы как прибор: взвесить и обнулить. Открываются с корневого экрана,
  /// минуя машину, — к ней они отношения могут и не иметь.
  case scale

  /// Ряд «вес» пайплайна: цель и отсечка.
  case weight
}

struct RootView: View {
  @EnvironmentObject private var link: WatchLink
  @State private var path: [Route] = []
  @Environment(\.scenePhase) private var phase

  /// Уже показали статус в этом сеансе.
  ///
  /// Если машина на связи, список машин человеку не нужен: он её уже выбрал, и
  /// открывать часы, чтобы ткнуть в единственную строку, — лишний шаг. Но
  /// вернуться в список должно быть можно, поэтому переход одноразовый: до
  /// следующего пробуждения часов больше не сработает.
  @State private var landed = false

  var body: some View {
    NavigationStack(path: $path) {
      MachinesView(path: $path)
        .navigationDestination(for: Route.self) { route in
          switch route {
          case .pipeline: PipelineView(path: $path)
          case .timer: TimerView()
          case .mode: ModeView()
          case .step(let id): StepEditorView(stepId: id)
          case .group(let id): GroupView(groupId: id, path: $path)
          case .scale: ScaleView()
          case .weight: WeightView()
          }
        }
    }
    .tint(K.text)
    .onAppear {
      link.hello()
      land()
    }
    .onChange(of: phase) { _, now in
      // Вернулись на экран — картинка могла устареть, пока часы спали.
      if now == .active {
        link.hello()
        land()
      }
      if now == .background {
        landed = false
        // Уходим в сон — пусть система разбудит нас снова.
        WatchAppDelegate.scheduleSelfWake()
      }
    }
    .onChange(of: link.snapshot?.isConnected ?? false) { _, connected in
      // Связь с машиной пропала — держать открытым пайплайн не на чем.
      if !connected, path.contains(.pipeline) { path.removeAll() }
      // А появилась — снимок мог доехать уже после открытия экрана.
      land()
    }
  }

  /// Открыть статус, если есть что показывать.
  ///
  /// Только с корня: человек мог уйти в весы или в редактор шага, и выдёргивать
  /// его оттуда нельзя.
  private func land() {
    guard !landed, path.isEmpty, link.snapshot?.isConnected == true else { return }
    landed = true
    path.append(.pipeline)
  }
}

/// Телефон недоступен. Показывать при этом последние известные числа нельзя:
/// устаревшая температура хуже отсутствующей.
struct NoPhoneView: View {
  @EnvironmentObject private var link: WatchLink

  var body: some View {
    VStack(spacing: 8) {
      PipeIcon(name: "?", size: 26, color: K.dim)
      Text(link.string("noPhone"))
        .font(K.F.rowLabel)
        .foregroundStyle(K.secondary)
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(K.bg)
  }
}
