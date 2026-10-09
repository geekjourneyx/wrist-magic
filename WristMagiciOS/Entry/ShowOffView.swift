import SwiftUI
import MetalKit
import WristMagicCore

struct StagePreview: UIViewRepresentable {
  let renderer: StageRenderer
  func makeUIView(context: Context) -> MTKView {
    let view = MTKView(); renderer.attach(preview: view); return view
  }
  func updateUIView(_ view: MTKView, context: Context) {}
}
struct ShowOffView: View {
  @Bindable var model: AppModel
  var body: some View {
    ZStack {
      StagePreview(renderer: model.renderer).ignoresSafeArea()
      VStack(spacing: 16) {
        HStack { Button("退出") { model.home() }.disabled(model.capture.state == .processing); Spacer(); Text(model.selectedMode == .showOff ? "Show Off" : "Reality").font(.headline) }
        Spacer()
        if model.route == .showOff && model.capture.state == .preparing {
          Image(systemName: "figure.stand").font(.system(size: 130)).foregroundStyle(.white.opacity(0.55)).accessibilityHidden(true)
          Text("放稳手机，站到轮廓附近。发射区固定，不追踪手。")
          Picker("发射侧", selection: Binding(get: { model.capture.side }, set: { model.changeSide($0) })) {
            Text("左侧").tag(LaunchSide.left); Text("右侧").tag(LaunchSide.right)
          }.pickerStyle(.segmented)
        }
        Spacer()
        if model.capture.state == .countdown { Text("\(model.capture.countdown)").font(.system(size: 88, weight: .bold)).accessibilityLabel("倒计时 \(model.capture.countdown)") }
        if model.capture.state == .recording {
          Text(String(format: "录制 %.1f / 6 秒", model.capture.elapsed)).monospacedDigit()
          Text(model.capture.castAccepted ? "已接受一次施法" : "等待手表施法")
          Button("提前结束") { Task { await model.capture.stop() } }.buttonStyle(.borderedProminent)
        } else if model.capture.state == .processing {
          ProgressView("正在处理短片，请稍候")
        } else if model.route == .showOff && model.capture.state == .preparing {
          Text(model.watchCharged ? "手表已蓄满" : "请在手表点准备并蓄满")
          Button("开始三秒倒计时") { Task { await model.capture.beginCountdown() } }
            .buttonStyle(.borderedProminent).disabled(!model.watchCharged || !model.trackingReady)
        }
        Text(model.trackingReady ? model.message : "正在定位舞台，请保持光线充足").font(.footnote)
      }.padding().background(.black.opacity(0.2))
    }.toolbar(.hidden, for: .navigationBar)
  }
}
