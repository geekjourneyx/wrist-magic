import SwiftUI

@main @MainActor struct WristMagicApp: App {
  @State private var model: AppModel?
  @State private var startupError = false
  @Environment(\.scenePhase) private var scenePhase
  var body: some Scene {
    WindowGroup {
      NavigationStack {
        if let model {
          root(model)
        } else {
          VStack(spacing: 20) {
            Text("腕术").font(.largeTitle)
            if startupError {
              Text("无法打开本地短片或图形舞台。请检查空间后重试；手表仍可独立练习。")
              Button("重试") { initialize() }
            } else { ProgressView("正在准备") }
          }.padding()
        }
      }.preferredColorScheme(.dark)
        .tint(.orange)
        .task { if model == nil { initialize() }; model?.sceneActive(scenePhase == .active) }
        .onChange(of: scenePhase) { _, phase in model?.sceneActive(phase == .active) }
    }
  }
  private func initialize() {
    do { model = try AppModel(); startupError = false }
    catch { startupError = true; NSLog("App initialization failed: %@", String(describing: error)) }
  }
  @ViewBuilder private func root(_ model: AppModel) -> some View {
    switch model.route {
    case .connection: ConnectionView(model: model)
    case .tutorial: TutorialView(model: model)
    case .home: HomeView(model: model)
    case .settings: SettingsView(model: model)
    case .reality, .showOff: ShowOffView(model: model)
    case .review: if let record = model.clip { ClipReviewView(model: model, record: record) }
    case .recovery: RecoveryView(model: model)
    }
  }
}
