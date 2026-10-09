import SwiftUI
import WristMagicCore
@main
@MainActor struct WristMagicApp: App {
    private let coordinator: SessionCoordinator
    private let link: PhoneLink
    @Environment(\.scenePhase) private var scenePhase
    init() {
        let authority = SessionCoordinator()
        coordinator = authority
        link = PhoneLink(coordinator: authority)
    }
    var body: some Scene {
        WindowGroup {
            VStack(spacing: 16) {
                Text("腕术").font(.largeTitle)
                Text("Wrist Magic").font(.title2)
                Text("开发基线 · 协议 \(CoreBaseline.protocolVersion)").font(.caption)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(Color(red: 0.97, green: 0.95, blue: 0.91))
            .background(Color(red: 0.03, green: 0.03, blue: 0.03))
            .preferredColorScheme(.dark)
            .onAppear { coordinator.foreground = scenePhase == .active; link.setForeground(scenePhase == .active) }
            .onChange(of: scenePhase) { _, phase in
                coordinator.foreground = phase == .active
                link.setForeground(phase == .active)
                if phase != .active { coordinator.invalidate(reason: "iPhone inactive") }
            }
        }
    }
}
