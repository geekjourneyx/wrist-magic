import SwiftUI
import WristMagicCore

@MainActor @Observable final class WatchRuntime {
  let model: WatchCastModel
  let link: WatchLink
  let motion = MotionSource()
  let haptics = HapticPlayer()
  let sound = WatchSoundPlayer()
  init() {
    link = WatchLink()
    model = WatchCastModel(link: link)
    link.bind(model)
    model.onMotionStart = { [weak self] in
      guard let self else { return }
      do { try motion.start { [weak self] sample in self?.model.sample(sample) } }
      catch { model.report("动作传感器不可用，请轻点施法") }
    }
    model.onMotionStop = { [weak self] in self?.motion.stop() }
    model.onSoundStop = { [weak self] in self?.sound.stop() }
    model.onFeedback = { [weak self] event in
      guard let self else { return }
      haptics.enabled = model.settings.haptics
      haptics.play(event, at: ProcessInfo.processInfo.systemUptime)
      if event == .released, model.mode == .practice, model.settings.sound { sound.play(model.state.spell) }
    }
    motion.onError = { [weak self] _ in self?.model.report("动作采样中断，请轻点施法") }
  }
  func foreground(_ active: Bool) {
    link.setForeground(active)
    if !active { model.send(.pause) }
  }
}

@main struct WristMagicWatchApp: App {
  @State private var runtime = WatchRuntime()
  @Environment(\.scenePhase) private var scenePhase
  var body: some Scene {
    WindowGroup {
      WatchRootView(model: runtime.model)
        .onAppear { runtime.foreground(scenePhase == .active) }
        .onChange(of: scenePhase) { _, phase in runtime.foreground(phase == .active) }
    }
  }
}

struct WatchRootView: View {
  @Bindable var model: WatchCastModel
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack {
          Text("腕术").font(.headline)
          Text(model.message).font(.caption).foregroundStyle(.secondary)
          switch model.state.phase {
          case .selecting: SpellPickerView(model: model)
          case .charging: ChargeView(model: model)
          case .ready: ReadyView(model: model)
          case .fired, .retry: ResultView(model: model)
          case .paused:
            Text("已暂停")
            Button("继续") { model.send(.resume) }
          }
        }
      }
      .toolbar {
        ToolbarItem { NavigationLink("设置") { WatchSettingsView(model: model) } }
      }
    }
    .task {
      while !Task.isCancelled {
        try? await Task.sleep(for: .milliseconds(100))
        model.tick()
      }
    }
  }
}
struct SpellPickerView: View {
  @Bindable var model: WatchCastModel
  var body: some View {
    Picker("选择法术", selection: Binding(get: { model.state.spell }, set: { model.send(.select($0)) })) {
      ForEach(SpellID.allCases, id: \.self) { spell in Text(spell.title).tag(spell) }
    }.pickerStyle(.wheel)
    Button("准备施法") { model.send(.prepare) }
      .disabled(model.mode != .practice && !model.connected)
    if model.mode != .practice && !model.connected {
      Button("重新连接") { model.connect() }
    }
  }
}
struct ChargeView: View {
  @Bindable var model: WatchCastModel
  @State private var crown = 0.0
  var body: some View {
    VStack {
      Text(model.state.spell.title).font(.title3)
      ProgressView(value: model.state.charge)
        .accessibilityLabel("蓄力")
        .accessibilityValue("\(Int(model.state.charge * 4) * 25)%")
      Text("转动表冠蓄力")
      Button("蓄满力量") { crown = 1; model.send(.crown(1)) }
        .accessibilityHint("无需转动表冠的替代操作")
      Button("返回") { model.send(.reset) }
    }
    .focusable()
    .digitalCrownRotation($crown, from: 0, through: 1, by: 0.02, sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true)
    .onChange(of: crown) { _, value in model.send(.crown(value)) }
  }
}
struct ReadyView: View {
  @Bindable var model: WatchCastModel
  var body: some View {
    Text("已就绪").font(.title3)
    Text("挥动手腕或轻点施法")
    Text("动作识别为实验规则").font(.caption2).foregroundStyle(.secondary)
    Button("轻点施法") { model.send(.trigger) }
    Button("取消") { model.send(.reset) }
  }
}
struct ResultView: View {
  @Bindable var model: WatchCastModel
  var body: some View {
    if model.state.phase == .fired {
      WatchSpellEffect(spell: model.state.spell, reducedMotion: model.settings.reducedMotion)
    }
    Image(systemName: model.state.phase == .fired ? "sparkles" : "arrow.clockwise")
      .font(.largeTitle).accessibilityHidden(true)
    Text(model.state.phase == .fired ? "已释放" : "就绪时间已结束")
    Button("再来一次") { model.send(.prepare) }
    Button("换个法术") { model.send(.reset) }
  }
}
struct WatchSettingsView: View {
  @Bindable var model: WatchCastModel
  var body: some View {
    Form {
      Picker("模式", selection: Binding(get: { model.mode }, set: { model.setMode($0) })) {
        Text("离线练习").tag(PlayMode.practice)
        Text("Reality").tag(PlayMode.reality)
        Text("Show Off").tag(PlayMode.showOff)
      }
      Toggle("声音", isOn: preference(\.sound))
      Toggle("触感", isOn: preference(\.haptics))
      Toggle("减少动态", isOn: preference(\.reducedMotion))
      Text("连接玩法需要在 iPhone 打开舞台。")
      Button("暂停") { model.send(.pause) }
    }
  }
  private func preference(_ key: KeyPath<SettingsPayload, Bool>) -> Binding<Bool> {
    Binding(get: { model.settings[keyPath: key] }, set: { value in
      let current = model.settings
      model.updatePreferences(
        sound: key == \.sound ? value : current.sound,
        haptics: key == \.haptics ? value : current.haptics,
        reducedMotion: key == \.reducedMotion ? value : current.reducedMotion)
    })
  }
}
extension SpellID {
  var title: String {
    switch self { case .fireball: "火球"; case .lightning: "闪电"; case .forcePush: "原力推" }
  }
}
