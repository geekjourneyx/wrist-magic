import SwiftUI
import UIKit
import WristMagicCore

struct RecoveryView: View {
  @Bindable var model: AppModel
  var body: some View {
    ScrollView {
      VStack(spacing: 24) {
        Image(systemName: "pause.circle").font(.system(size: 64)).accessibilityHidden(true)
        Text("稍停一下").font(.largeTitle.bold())
        Text(model.message).multilineTextAlignment(.center)
        if model.capture.state == .processing {
          ProgressView("正在保留可用片段")
        } else {
          if model.clip != nil { Button("查看保留的短片") { model.reviewRecovered() }.buttonStyle(.borderedProminent) }
          if model.failure == .audioFailed {
            Button("重试声音处理") { Task { await model.retry() } }
            Button("明确导出静音版") { Task { await model.silentExport() } }.buttonStyle(.bordered)
          } else {
            Button("重新准备") { Task { await model.retry() } }.buttonStyle(.borderedProminent)
          }
          if model.failure == .cameraDenied {
            Button("打开系统设置") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
          }
          Button("返回主页 / 手表练习") { model.home() }
        }
      }.padding(24)
    }.navigationTitle("恢复")
  }
}
