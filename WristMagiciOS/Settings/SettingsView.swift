import SwiftUI
import WristMagicCore

struct SettingsView: View {
  @Bindable var model: AppModel
  var body: some View {
    Form {
      Section("反馈") {
        Toggle("声音", isOn: preference(\.sound))
        Toggle("触感", isOn: preference(\.haptics))
        Toggle("减少动态", isOn: preference(\.reducedMotion))
      }
      Section("学习与连接") {
        Button("动作教学") { model.showTutorial() }
        Text("请在手表打开腕术，并让两端保持前台。切换模式后需重新连接和蓄力。")
      }
      Section { Button("完成") { model.home() } }
    }.navigationTitle("设置")
  }
  private func preference(_ key: KeyPath<WristMagicCore.SettingsPayload, Bool>) -> Binding<Bool> {
    Binding(get: { model.settings.snapshot[keyPath: key] }, set: { value in
      let current = model.settings.snapshot
      model.updateSettings(sound: key == \.sound ? value : current.sound,
                           haptic: key == \.haptics ? value : current.haptics,
                           reduceMotion: key == \.reducedMotion ? value : current.reducedMotion)
    })
  }
}
