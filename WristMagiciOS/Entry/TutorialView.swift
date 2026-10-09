import SwiftUI

struct TutorialView: View {
  @Bindable var model: AppModel
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        Text(model.tutorialSuccess ? "这次成功了" : "从手腕开始").font(.largeTitle.bold())
        Image(systemName: model.tutorialSuccess ? "checkmark.circle.fill" : "arrow.up.forward").font(.system(size: 72)).frame(maxWidth: .infinity).accessibilityHidden(true)
        Text("1. 在手表选择练习，点“准备”。\n2. 转动 Digital Crown 蓄满。\n3. 按当前术的轨迹挥腕，或轻点施法。")
        Text("抬腕停顿是姿势指导。腕术不识别拳头、掌心或手部姿势。请留出安全空间。")
        if !model.tutorialSuccess { Text("完成一次手表接受的动作后，这里显示结果。无需相机权限。") }
        Button(model.tutorialSuccess ? "开始玩" : "先进入主页") { model.home() }.buttonStyle(.borderedProminent)
      }.padding(24)
    }.navigationTitle("动作教学")
  }
}
