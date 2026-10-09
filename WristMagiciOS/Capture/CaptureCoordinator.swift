import ARKit
import Observation
import WristMagicCore

struct CameraMovementGate {
  private var exceededAt: Double?
  mutating func reset() { exceededAt = nil }
  mutating func update(distance: Float, angle: Float, now: Double) -> Bool {
    guard distance > 0.15 || angle > 10 else { exceededAt = nil; return false }
    if exceededAt == nil { exceededAt = now }
    return now - exceededAt! >= 0.3
  }
}

@MainActor @Observable final class CaptureCoordinator {
  private(set) var state: CaptureState = .idle
  private(set) var countdown = 3
  private(set) var elapsed: Double = 0
  private(set) var castAccepted = false
  private(set) var side: LaunchSide = .left
  var onClip: ((ClipRecord) -> Void)?
  var onFailure: ((AppFailure) -> Void)?
  private let authority: SessionCoordinator
  private let pipeline: RenderCapturePipeline
  private let store: ClipStore
  private let settings: SettingsStore
  private let now: () -> Double
  private let sleep: (Duration) async throws -> Void
  private var countdownTask: Task<Void, Never>?
  private var generation = 0
  private var baseline: simd_float4x4?
  private var movement = CameraMovementGate()
  private var silentSource: URL?
  private var audioCues: [EffectCue] = []
  private var interrupted = false
  init(authority: SessionCoordinator, pipeline: RenderCapturePipeline, store: ClipStore, settings: SettingsStore,
       now: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime },
       sleep: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
    self.authority = authority; self.pipeline = pipeline; self.store = store; self.settings = settings; self.now = now; self.sleep = sleep
    pipeline.onFirstFrame = { [weak self] _, uptime in
      guard let self, self.state == .recording else { return }
      self.authority.captureDidStart(firstFrame: uptime, cutoff: uptime + 4.5, now: self.now())
    }
    pipeline.onDurationReached = { [weak self] in Task { await self?.stop() } }
    pipeline.onError = { [weak self] _ in self?.interrupt(.writerFailed) }
  }
  func prepare(side: LaunchSide) {
    guard state != .processing && state != .recording else { return }
    generation += 1; countdownTask?.cancel(); self.side = side; state = .preparing
    elapsed = 0; castAccepted = false; baseline = nil; movement.reset()
    authority.captureFirstFrame = nil; authority.captureCutoff = nil
  }
  func beginCountdown() async {
    guard state == .preparing, authority.mode == .showOff, authority.chargedSpell != nil,
      authority.trackingNormal, authority.foreground else { return }
    state = .countdown; countdown = 3
    let epoch = generation
    countdownTask = Task { [weak self] in
      guard let self else { return }
      do {
        for value in (1...3).reversed() {
          self.countdown = value; try await self.sleep(.seconds(1)); try Task.checkCancellation()
          guard epoch == self.generation, self.authority.trackingNormal, self.authority.foreground else { return }
        }
        try self.pipeline.prepare(url: ClipWriter.temporaryURL(in: self.store.directory))
        self.state = .recording
      } catch is CancellationError { } catch { self.state = .failed; self.onFailure?(.writerFailed) }
    }
    await countdownTask?.value
  }
  func receiveCast(_ envelope: WireEnvelope) { _ = authority.receive(envelope, now: now()) }
  func acceptCast() -> Bool {
    guard state == .recording, !castAccepted,
      let first = authority.captureFirstFrame, now() < first + 4.5 else { return false }
    castAccepted = true; return true
  }
  func frame(_ frame: ARFrame) {
    guard state == .countdown || state == .recording else { return }
    if baseline == nil { baseline = frame.camera.transform }
    if let baseline {
      let current = frame.camera.transform
      let distance = simd_distance(SIMD3(current.columns.3.x,current.columns.3.y,current.columns.3.z), SIMD3(baseline.columns.3.x,baseline.columns.3.y,baseline.columns.3.z))
      let dot = min(1, max(-1, abs(simd_dot(simd_quatf(baseline).vector,simd_quatf(current).vector))))
      let angle = 2 * acos(dot) * 180 / Float.pi
      if movement.update(distance: distance, angle: angle, now: now()) { interrupt(.cameraInterrupted); return }
    }
    if let first = authority.captureFirstFrame { elapsed = max(0, now() - first) }
  }
  func stop() async { await finish(interrupted: false) }
  func interrupt(_ reason: AppFailure) {
    authority.invalidate(reason: reason.rawValue)
    generation += 1; countdownTask?.cancel()
    if state == .recording { Task { await self.finish(interrupted: true, failure: reason) } }
    else if state != .processing && state != .review { pipeline.cancel(); state = .failed; onFailure?(reason) }
  }
  func cancel() {
    guard state != .processing else { return }
    generation += 1; countdownTask?.cancel(); pipeline.cancel(); state = .idle
    authority.invalidate(reason: "capture cancelled"); authority.captureFirstFrame = nil; authority.captureCutoff = nil
  }
  private func finish(interrupted: Bool, failure: AppFailure? = nil) async {
    guard state == .recording else { return }
    state = .processing; self.interrupted = interrupted
    authority.invalidate(reason: "capture ended")
    do {
      audioCues = pipeline.relativeAudioCues
      guard let video = try await pipeline.finish(interrupted: interrupted) else {
        state = .failed; onFailure?(failure ?? .writerFailed); return
      }
      silentSource = video
      await process(silent: false)
    } catch { state = .failed; onFailure?(.writerFailed) }
  }
  func process(silent: Bool) async {
    guard let video = silentSource, state == .processing || state == .failed else { return }
    state = .processing
    do {
      let output: URL
      do { output = try await ClipAudioMixer.mix(video: video, cues: audioCues, soundEnabled: !silent && settings.snapshot.sound) }
      catch { state = .failed; onFailure?(.audioFailed); return }
      let report = try await ClipValidator.validate(url: output, requiresAudio: !silent && settings.snapshot.sound && !audioCues.isEmpty)
      let record = try store.commit(tempURL: output, report: report, interrupted: interrupted)
      if output != video { try? FileManager.default.removeItem(at: video) }
      silentSource = nil; state = .review; onClip?(record)
      do { try store.prune() } catch { NSLog("Clip prune failed: %@", String(describing: error)) }
    } catch { state = .failed; onFailure?(.diskFull) }
  }
}
