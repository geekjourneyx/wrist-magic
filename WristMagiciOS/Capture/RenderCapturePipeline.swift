import ARKit
import WristMagicCore

/// S05 binds these events to authority/UI. This object owns only rendering and video time.
@MainActor final class RenderCapturePipeline {
  let renderer: StageRenderer
  private(set) var writer: ClipWriter?
  private(set) var firstFrameTime: Double?
  private(set) var lastFrameTime: Double?
  private(set) var cues: [EffectCue] = []
  private(set) var recording = false
  private var pendingGPU = 0
  private var generation = 0
  private var lastSubmitted: Double?
  private var finishWaiters: [CheckedContinuation<Void,Never>] = []
  private var closing = false
  var onFirstFrame: ((_ arTimestamp: Double, _ receiverUptime: Double) -> Void)?
  var onDurationReached: (() -> Void)?
  var onError: ((Error) -> Void)?
  init(renderer: StageRenderer) { self.renderer = renderer }
  func prepare(url: URL) throws {
    guard !recording, !closing, pendingGPU == 0 else { throw MediaError.invalidState }
    generation += 1; writer = try ClipWriter(url:url)
    firstFrameTime = nil; lastFrameTime = nil; lastSubmitted = nil; cues = []; recording = true
  }
  func add(_ cue: EffectCue) { cues.append(cue); if cues.count > 16 { cues.removeFirst(cues.count-16) } }
  /// Render preview even while idle. Camera/effects alone enter the shared offscreen surface.
  func consume(_ frame: ARFrame) {
    consume(image:frame.capturedImage,displayTransform:frame.displayTransform(for:.portrait,viewportSize:CameraTransform.outputSize),viewProjection:CameraTransform.viewProjection(frame.camera),timestamp:frame.timestamp)
  }
  func consume(image: CVPixelBuffer, displayTransform: CGAffineTransform, viewProjection: simd_float4x4, timestamp: Double) {
    guard timestamp.isFinite, !closing else { return }
    if let lastSubmitted, timestamp - lastSubmitted < 1.0/30.0 - 0.001 { return }
    if recording, let firstFrameTime, timestamp >= firstFrameTime + 6 {
      recording = false; onDurationReached?(); return
    }
    if recording, let writer, writer.state != .idle, !writer.ready { return }
    let currentGeneration = generation
    let writing = recording
    do {
      let accepted = try renderer.submit(image:image,displayTransform:displayTransform,viewProjection:viewProjection,time:timestamp,effects:cues) { [self] result in
        self.pendingGPU -= 1
        defer {
          if self.pendingGPU == 0 { let waiters = self.finishWaiters; self.finishWaiters = []; waiters.forEach {$0.resume()} }
        }
        guard currentGeneration == self.generation else { return }
        switch result {
        case .failure(let error): self.recording = false; self.onError?(error)
        case .success(let buffer):
          guard writing, let writer = self.writer else { return }
          do {
            if self.firstFrameTime == nil {
              try writer.start(at:.zero)
              guard try writer.append(buffer:buffer,pts:.zero) else { return }
              self.firstFrameTime = timestamp; self.lastFrameTime = timestamp
              self.onFirstFrame?(timestamp,ProcessInfo.processInfo.systemUptime)
            } else if let first = self.firstFrameTime, timestamp < first + 6,
              self.lastFrameTime.map({timestamp > $0}) ?? true {
              if try writer.append(buffer:buffer,pts:CMTime(seconds:timestamp-first,preferredTimescale:60000)) { self.lastFrameTime = timestamp }
            }
          } catch { self.recording = false; self.onError?(error) }
        }
      }
      if accepted { pendingGPU += 1; lastSubmitted = timestamp }
    } catch { recording = false; onError?(error) }
  }
  var relativeAudioCues: [EffectCue] {
    guard let firstFrameTime else { return [] }
    return cues.filter {$0.start >= firstFrameTime}.map {
      EffectCue(eventID:$0.eventID,spell:$0.spell,start:$0.start-firstFrameTime,duration:$0.duration,seed:$0.seed,origin:$0.origin,direction:$0.direction)
    }
  }
  func finish(interrupted: Bool = false) async throws -> URL? {
    guard let writer, !closing else { throw MediaError.invalidState }
    closing = true; recording = false
    defer { closing = false }
    if pendingGPU > 0 { await withCheckedContinuation { finishWaiters.append($0) } }
    guard let first = firstFrameTime, let last = lastFrameTime, last-first+1.0/30 >= 2 else {
      writer.cancel(); self.writer = nil; return nil
    }
    let url = try await writer.finish()
    let actualDuration = last-first+1.0/30
    _ = try await ClipValidator.validate(url:url,expectedDuration:interrupted ? actualDuration : min(6,actualDuration),requiresAudio:false)
    return url
  }
  func cancel() {
    generation += 1; recording = false; writer?.cancel(); writer = nil
    firstFrameTime = nil; lastFrameTime = nil; cues = []
  }
}
