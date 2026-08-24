import SwiftUI

@main
struct K2ProWatchApp: App {
  @StateObject private var link = WatchLink()

  var body: some Scene {
    WindowGroup {
      RootView().environmentObject(link)
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
}

struct RootView: View {
  @EnvironmentObject private var link: WatchLink
  @State private var path: [Route] = []
  @Environment(\.scenePhase) private var phase

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
          }
        }
    }
    .tint(K.text)
    .onAppear { link.hello() }
    .onChange(of: phase) { _, now in
      // Вернулись на экран — картинка могла устареть, пока часы спали.
      if now == .active { link.hello() }
    }
    .onChange(of: link.snapshot?.isConnected ?? false) { _, connected in
      // Связь с машиной пропала — держать открытым пайплайн не на чем.
      if !connected, path.contains(.pipeline) { path.removeAll() }
    }
  }
}

/// Телефон недоступен. Показывать при этом последние известные числа нельзя:
/// устаревшая температура хуже отсутствующей.
struct NoPhoneView: View {
  @EnvironmentObject private var link: WatchLink

  var body: some View {
    VStack(spacing: 8) {
      PipeIcon(name: "?", size: 26, color: K.dim)
      Text(link.string("noPhone", "—"))
        .font(K.F.rowLabel)
        .foregroundStyle(K.secondary)
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(K.bg)
  }
}
