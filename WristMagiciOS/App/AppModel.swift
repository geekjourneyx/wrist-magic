import ARKit
import UIKit
import Observation
import WristMagicCore

enum AppRoute: Equatable { case connection, tutorial, home, reality, showOff, settings, review(UUID), recovery }

@MainActor @Observable final class AppModel {
  private(set) var route: AppRoute
  private(set) var selectedSpell: SpellID = .fireball
  var selectedMode: PlayMode = .reality
  private(set) var selectingSpell = false
  private(set) var connected = false
  private(set) var message = "请在 Apple Watch 上打开腕术"
  private(set) var tutorialSuccess = false
  private(set) var failure: AppFailure = .unknown
  private(set) var clip: ClipRecord?
  private(set) var trackingReady = false
  private(set) var watchCharged = false
  let settings: SettingsStore
  let authority: SessionCoordinator
  let link: any PhoneSessionLink
  let frames: ARFrameSource
  let renderer: StageRenderer
  let stage: EffectStage
  let pipeline: RenderCapturePipeline
  let store: ClipStore
  let sound: PhoneSoundPlayer
  let capture: CaptureCoordinator
  let photos = PhotoSaver()
  private let now: () -> Double
  private let cameraPermission: () async -> Bool
  private var frameUptime: Double = 0
  private var currentFrame: ARFrame?
  private var deferredSpell: SpellID?
  private var commandGeneration = 0
  private var tutorialEvents: [UUID] = []
  private var tutorialSession: UUID?
  private var foreground = false
  private var trackingLostAt: Double?
  private var reviewLeaseID: UUID?
  private var observation: NSObjectProtocol?
  init(settings: SettingsStore = SettingsStore(), authority: SessionCoordinator = SessionCoordinator(),
       link: (any PhoneSessionLink)? = nil, frames: ARFrameSource = ARFrameSource(),
       store: ClipStore? = nil, now: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime },
       cameraPermission: @escaping () async -> Bool = { await PermissionCoordinator.requestCamera() }) throws {
    self.settings = settings
    self.authority = authority; self.link = link ?? PhoneLink(coordinator: authority)
    self.frames = frames; self.now = now; self.cameraPermission = cameraPermission
    renderer = try StageRenderer(); stage = EffectStage()
    pipeline = RenderCapturePipeline(renderer: renderer); self.store = try store ?? ClipStore(); sound = PhoneSoundPlayer()
    capture = CaptureCoordinator(authority: authority, pipeline: pipeline, store: self.store, settings: settings, now: now)
    route = settings.tutorialCompleted ? .home : .connection
    bind()
    if let pending = self.store.latestRecoverable() { try self.store.acquire(pending.id); reviewLeaseID = pending.id; clip = pending; route = .recovery; message = "上次的短片已保留，是否查看？" }
    do { try self.store.prune() } catch { NSLog("Clip prune failed: %@", String(describing: error)) }
  }
  private func bind() {
    link.onSettings = { [weak self] value in self?.settings.apply(value) }
    link.onLinkChanged = { [weak self] available, reason in
      guard let self else { return }
      self.connected = available
      if available { try? self.link.publishSettings(self.settings.snapshot) }
      else { self.commandGeneration += 1; self.message = reason; self.watchCharged = false; if self.isStage { self.recover(.linkLost) } }
    }
    link.onReceived = { [weak self] envelope in self?.received(envelope) }
    authority.onCharged = { [weak self] spell in self?.watchCharged = true; self?.selectedSpell = spell }
    authority.onAcceptedCast = { [weak self] spell, uptime in
      guard let self, self.isStage, let frame = self.currentFrame, self.stage.placed else { return }
      if self.route == .showOff && !self.capture.acceptCast() { return }
      do {
        let start = frame.timestamp + uptime - self.frameUptime
        let cue = try self.stage.makeCue(spell: spell, start: start, seed: UInt64.random(in: 0...UInt64.max))
        self.pipeline.add(cue); self.sound.play(cue, enabled: self.settings.snapshot.sound)
        self.watchCharged = false; self.message = "这次成功了"
      } catch { self.recover(.trackingLost) }
    }
    frames.onTracking = { [weak self] normal in
      guard let self, self.isStage else { return }
      self.trackingReady = normal; self.stage.trackingNormal = normal; self.authority.trackingNormal = normal && self.stage.placed
      if normal { self.trackingLostAt = nil }
      else if self.capture.state == .recording { self.recover(.trackingLost) }
      else if self.trackingLostAt == nil { self.trackingLostAt = self.now() }
    }
    frames.onFrame = { [weak self] frame in
      guard let self, self.isStage else { return }
      self.currentFrame = frame; self.frameUptime = self.now()
      if self.trackingReady && !self.stage.placed {
        do { try self.stage.place(camera: frame.camera, mode: self.selectedMode, side: self.capture.side); self.authority.trackingNormal = true }
        catch { self.recover(.trackingLost); return }
      }
      if let lost = self.trackingLostAt, self.now() - lost >= 1 { self.recover(.trackingLost); return }
      self.capture.frame(frame)
      self.stage.casting = self.pipeline.cues.contains { frame.timestamp >= $0.start && frame.timestamp < $0.start + $0.duration }
      self.pipeline.consume(frame)
    }
    frames.onInterruption = { [weak self] _ in self?.recover(.cameraInterrupted) }
    capture.onClip = { [weak self] record in self?.review(record) }
    capture.onFailure = { [weak self] reason in self?.recover(reason) }
    observation = NotificationCenter.default.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main) { @Sendable [weak self] _ in
      Task { @MainActor in
        if ProcessInfo.processInfo.thermalState == .serious || ProcessInfo.processInfo.thermalState == .critical { self?.recover(.thermal) }
      }
    }
  }
  var isStage: Bool { route == .reality || route == .showOff }
  func sceneActive(_ active: Bool) {
    foreground = active; authority.foreground = active; link.setForeground(active)
    if !active {
      commandGeneration += 1
      if isStage { recover(.background) }
      else { authority.invalidate(reason: "inactive") }
      UIApplication.shared.isIdleTimerDisabled = false
    }
  }
  private func received(_ envelope: WireEnvelope) {
    if envelope.kind == .practiceResult, route == .tutorial, envelope.isValid, foreground,
      tutorialSession == nil || tutorialSession == envelope.sessionID,
      !tutorialEvents.contains(envelope.eventID) {
      tutorialSession = envelope.sessionID; tutorialEvents.append(envelope.eventID)
      if tutorialEvents.count > 256 { tutorialEvents.removeFirst() }
      tutorialSuccess = true; settings.completeTutorial()
    }
    if envelope.kind == .hello { connected = link.available; watchCharged = false; flushSelection() }
    if envelope.kind == .pause || envelope.kind == .end || envelope.kind == .cast { watchCharged = false; flushSelection() }
  }
  func showTutorial() { leaveStage(); tutorialSuccess = false; tutorialSession = nil; route = .tutorial }
  func home() { leaveStage(); releaseReview(); route = .home }
  func showSettings() { leaveStage(); route = .settings }
  func updateSettings(sound: Bool, haptic: Bool, reduceMotion: Bool) {
    settings.update(sound: sound, haptic: haptic, reduceMotion: reduceMotion)
    renderer.reducedMotion = reduceMotion
    try? link.publishSettings(settings.snapshot)
  }
  func select(_ spell: SpellID) {
    guard spell != selectedSpell else { return }
    if watchCharged || selectingSpell { deferredSpell = spell; message = "蓄力结束后切换法术"; return }
    guard let command = authority.command(.select, payload: SelectPayload(spell: spell)), link.available else { message = "请先在手表上连接 iPhone"; return }
    selectingSpell = true; let epoch = commandGeneration
    Task {
      defer { selectingSpell = false }
      do {
        let response = try await link.send(command)
        guard epoch == commandGeneration, response.sessionID == authority.sessionID,
          let ack = try? JSONDecoder().decode(AckPayload.self, from: response.payload), ack.eventID == command.eventID else { return }
        if ack.receipt == .accepted { selectedSpell = spell; message = "已切换法术" }
        else if ack.receipt == .unavailable { deferredSpell = spell; message = "蓄力结束后切换法术" }
        else { message = "切换失败，请重试" }
      } catch { message = "切换失败，保留原法术" }
    }
  }
  private func flushSelection() {
    if let pending = deferredSpell, !selectingSpell { deferredSpell = nil; select(pending) }
  }
  func startStage() async {
    guard foreground, link.available, authority.sessionID != nil else { route = .connection; message = "在手表上选择 Reality 或 Show Off，然后连接"; return }
    guard ProcessInfo.processInfo.thermalState != .serious && ProcessInfo.processInfo.thermalState != .critical else { recover(.thermal); return }
    if authority.mode != selectedMode {
      guard let request = authority.command(.hello, payload: HelloPayload(appVersion: "0.1.0", requestedMode: selectedMode)) else { return }
      do { _ = try await link.send(request); message = "模式已发送，请等手表重新连接后再次进入" }
      catch { message = "模式切换失败，请在手表上选择相同模式" }
      return
    }
    guard await cameraPermission() else { recover(.cameraDenied); return }
    do {
      stage.reset(); currentFrame = nil; trackingLostAt = nil
      capture.prepare(side: .left); renderer.reducedMotion = settings.snapshot.reducedMotion
      route = selectedMode == .showOff ? .showOff : .reality
      try frames.start(); UIApplication.shared.isIdleTimerDisabled = true
      message = "请缓慢移动手机以定位舞台"
    } catch { recover(.cameraInterrupted) }
  }
  func changeSide(_ side: LaunchSide) {
    guard capture.state == .preparing, !stage.casting, let frame = currentFrame else { return }
    capture.prepare(side: side)
    do { try stage.place(camera: frame.camera, mode: .showOff, side: side) } catch { recover(.trackingLost) }
  }
  private func leaveStage() {
    if isStage { capture.cancel() }
    frames.stop(); sound.stop(); stage.reset(); currentFrame = nil
    authority.trackingNormal = false; authority.captureFirstFrame = nil; authority.captureCutoff = nil
    UIApplication.shared.isIdleTimerDisabled = false
  }
  func recover(_ reason: AppFailure) {
    failure = reason; commandGeneration += 1; watchCharged = false
    let action = RecoveryPolicy.transition(error: reason, phase: capture.state)
    message = action.message
    authority.invalidate(reason: reason.rawValue)
    if capture.state == .recording || capture.state == .countdown || capture.state == .preparing { capture.interrupt(reason) }
    frames.stop(); sound.stop(); stage.reset(); UIApplication.shared.isIdleTimerDisabled = false
    route = .recovery
  }
  func retry() async {
    if failure == .audioFailed { await capture.process(silent: false) }
    else { home(); await startStage() }
  }
  func silentExport() async { await capture.process(silent: true) }
  func review(_ record: ClipRecord) {
    leaveStage(); releaseReview()
    do { try store.acquire(record.id); reviewLeaseID = record.id; clip = record; route = .review(record.id) }
    catch { recover(.diskFull) }
  }
  func reviewRecovered() { if let clip { review(clip) } }
  private func releaseReview() {
    if case .review(let id) = route { try? store.markReviewed(id) }
    if let id = reviewLeaseID { store.release(id); reviewLeaseID = nil }
    clip = nil
  }
}
