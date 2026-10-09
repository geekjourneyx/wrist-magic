import SwiftUI
import AVKit

struct ClipReviewView: View {
  @Bindable var model: AppModel
  let record: ClipRecord
  @State private var player: AVPlayer
  @State private var sharing = false
  @State private var shareLease = false
  @State private var error: String?
  init(model: AppModel, record: ClipRecord) {
    self.model = model; self.record = record; _player = State(initialValue: AVPlayer(url: record.url))
  }
  var body: some View {
    VStack(spacing: 20) {
      VideoPlayer(player: player).aspectRatio(9 / 16, contentMode: .fit)
      Text(record.interrupted ? "中断前的片段" : "你的短片").font(.title2)
      if let error { Text(error).foregroundStyle(.orange) }
      HStack {
        Button(model.photos.saved.contains(record.url) ? "已保存" : "保存到照片") {
          Task {
            do { try await model.photos.save(url: record.url); error = nil }
            catch { error = "无法保存。请允许添加照片，或使用系统分享。" }
          }
        }.disabled(model.photos.saving || model.photos.saved.contains(record.url))
        Button("系统分享", systemImage: "square.and.arrow.up") {
          do { try model.store.acquire(record.id); shareLease = true; sharing = true }
          catch { error = "短片暂时无法读取，请重试。" }
        }
      }.buttonStyle(.bordered)
      Button("完成") { player.pause(); model.home() }.buttonStyle(.borderedProminent)
    }.padding().navigationTitle("回放")
      .sheet(isPresented: $sharing, onDismiss: releaseShare) {
        SharePresenter(url: record.url) { sharing = false; releaseShare() }
      }
      .onDisappear { player.pause() }
  }
  private func releaseShare() {
    guard shareLease else { return }; model.store.release(record.id); shareLease = false
  }
}
