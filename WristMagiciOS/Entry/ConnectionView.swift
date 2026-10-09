import SwiftUI

struct ConnectionView: View {
  @Bindable var model: AppModel
  var body: some View {
    ScrollView {
      VStack(spacing: 24) {
        Image(systemName: "applewatch.radiowaves.left.and.right").font(.system(size: 64)).accessibilityHidden(true)
        Text("腕术").font(.largeTitle.bold())
        Text("让腕上的动作，来到眼前。").font(.title2)
        Text(model.message).multilineTextAlignment(.center)
        Text("在 Apple Watch 上打开腕术，选择与手机相同的模式。请让两端保持前台。")
        Button("查看动作教学") { model.showTutorial() }.buttonStyle(.borderedProminent)
        Button("进入主页") { model.home() }.buttonStyle(.bordered)
        Text("没有手表也能查看教学；在手表上可独立离线练习。").font(.footnote).foregroundStyle(.secondary)
      }.padding(24)
    }.navigationTitle("连接")
  }
}
