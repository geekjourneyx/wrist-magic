import SwiftUI
import WristMagicCore

extension SpellID {
  var title: String { switch self { case .fireball: "火球"; case .lightning: "闪电"; case .forcePush: "推力" } }
  var symbol: String { switch self { case .fireball: "flame.fill"; case .lightning: "bolt.fill"; case .forcePush: "wave.3.right" } }
}
struct HomeView: View {
  @Bindable var model: AppModel
  var body: some View {
    ScrollView {
      VStack(spacing: 24) {
        HStack { Text("腕术").font(.largeTitle.bold()); Spacer(); Button("设置", systemImage: "gearshape") { model.showSettings() } }
        Label(model.connected ? "手表连接可用" : "等待手表", systemImage: model.connected ? "checkmark.circle" : "applewatch")
        Text("选择你的术").font(.title2)
        Image(systemName: model.selectedSpell.symbol).font(.system(size: 84)).foregroundStyle(.orange).accessibilityHidden(true)
        Text(model.selectedSpell.title).font(.title.bold())
        HStack {
          ForEach(SpellID.allCases, id: \.self) { spell in
            Button(spell.title) { model.select(spell) }.buttonStyle(.bordered).tint(spell == model.selectedSpell ? .orange : .gray)
          }
        }.disabled(model.selectingSpell)
        Picker("模式", selection: $model.selectedMode) { Text("Reality").tag(PlayMode.reality); Text("Show Off").tag(PlayMode.showOff) }.pickerStyle(.segmented)
        Text(model.selectedMode == .reality ? "把手机对准现实，手表施法。" : "固定手机，录下一段六秒短片。")
        Text(model.message).font(.footnote).foregroundStyle(.secondary)
        Button("进入舞台") { Task { await model.startStage() } }.buttonStyle(.borderedProminent)
        Button("动作教学") { model.showTutorial() }
      }.padding(24)
    }.navigationTitle("Wrist Magic")
  }
}
