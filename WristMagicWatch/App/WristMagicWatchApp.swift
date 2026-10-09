import SwiftUI
import WristMagicCore
@main
struct WristMagicWatchApp: App {
    var body: some Scene {
        WindowGroup {
            VStack(spacing: 8) {
                Text("腕术").font(.title2)
                Text("开发基线").font(.caption)
                Text("协议 \(CoreBaseline.protocolVersion)").font(.caption2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(Color(red: 0.90, green: 0.77, blue: 0.53))
            .background(.black)
        }
    }
}
