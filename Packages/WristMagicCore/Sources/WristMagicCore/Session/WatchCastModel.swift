import Foundation
import Observation

public enum FeedbackEvent: Sendable { case start, ready, released, retry, paused }
@MainActor @Observable public final class WatchCastModel {
  public private(set) var state = CastState()
  public private(set) var mode: PlayMode = .practice
  public private(set) var connected = false
  public private(set) var message = "离线练习"
  public private(set) var sessionID = UUID()
  public private(set) var settings = SettingsPayload(revision: 0, sound: true, haptics: true, reducedMotion: false)
  public var onFeedback: ((FeedbackEvent) -> Void)?
  public var onMotionStart: (() -> Void)?
  public var onMotionStop: (() -> Void)?
  public var onSettingsChanged: ((SettingsPayload) -> Void)?
  public var onSoundStop: (() -> Void)?
  private let now: () -> Double
  private var link: (any LiveLink)?
  private var phoneSequence: UInt64 = 0
  private var sequence: UInt64 = 0
  private var generation: UInt64 = 0
  private var permit: SessionPermit?
  private var readyDeadline: Double?
  private var lastRelease: Double = -.infinity
  private var armRequested = false
  private var armRequestID: UUID?
  private var armGeneration: UInt64?
  private var requests: [UUID: Task<Void, Never>] = [:]
  private var consumedEvents: [UUID] = []
  private var consumedTokens: [UUID] = []
  private var trigger = GestureTrigger(profiles: Dictionary(uniqueKeysWithValues: SpellID.allCases.map { ($0, .experimental($0)) }))
  public init(link: (any LiveLink)? = nil, now: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime }) {
    self.link = link; self.now = now
  }
  private func make<T: Encodable>(_ kind: WireKind, _ payload: T) -> WireEnvelope {
    sequence += 1
    return WireEnvelope(eventID: UUID(), sessionID: sessionID, sequence: sequence, kind: kind,
      payload: (try? JSONEncoder().encode(payload)) ?? Data())
  }
  public func setMode(_ mode: PlayMode) {
    disconnect(reason: "请连接 iPhone 舞台")
    self.mode = mode
    if mode != .practice { connect() } else { message = "离线练习" }
  }
  public func connect() {
    guard mode != .practice, link != nil else { return }
    disconnect(reason: "正在连接")
    let epoch = generation
    let hello = make(.hello, HelloPayload(appVersion: "0.1.0", requestedMode: mode))
    submit(hello) { [weak self] response in
      guard let self, self.generation == epoch, response.sessionID == self.sessionID,
        let ack = try? JSONDecoder().decode(AckPayload.self, from: response.payload),
        ack.eventID == hello.eventID, ack.receipt == .accepted else { return }
      self.connected = true; self.message = "已连接"
    } failure: { [weak self] in self?.disconnect(reason: "连接失败，请重试") }
  }
  private func submit(_ envelope: WireEnvelope,
    success: @escaping @MainActor (WireEnvelope) -> Void,
    failure: @escaping @MainActor () -> Void = {}) {
    guard let link else { return }
    let epoch = generation
    self.requests[envelope.eventID] = Task { [weak self] in
      do {
        try Task.checkCancellation()
        let response = try await link.send(envelope)
        guard let self else { return }
        self.requests.removeValue(forKey: envelope.eventID)
        guard !Task.isCancelled, self.generation == epoch else { return }
        success(response)
      } catch {
        guard let self else { return }
        self.requests.removeValue(forKey: envelope.eventID)
        guard !Task.isCancelled, self.generation == epoch else { return }
        failure()
      }
    }
  }
  /// Stop retries synchronously before issuing the newer revocation sequence.
  private func cancelCycle(revoke kind: WireKind? = nil) {
    for task in requests.values { task.cancel() }
    requests.removeAll()
    link?.cancelPending(sessionID: sessionID)
    generation += 1
    armRequestID = nil; armGeneration = nil
    permit = nil; readyDeadline = nil; armRequested = false
    if connected, let kind {
      let revocation = make(kind, ReasonPayload(reason: "Watch casting cycle ended"))
      submit(revocation, success: { _ in })
    }
  }

  public func disconnect(reason: String) {
    cancelCycle(revoke: .end)
    sessionID = UUID(); sequence = 0; phoneSequence = 0; connected = false
    permit = nil; readyDeadline = nil; armRequested = false; trigger.reset()
    let wasPaused = state.phase == .paused
    state = CastReducer.reduce(state, .reset)
    if wasPaused { state = CastReducer.reduce(state, .pause) }
    onMotionStop?(); onSoundStop?(); message = reason
  }
  public func updatePreferences(sound: Bool, haptics: Bool, reducedMotion: Bool) {
    let value = SettingsPayload(revision: settings.revision + 1, sound: sound, haptics: haptics, reducedMotion: reducedMotion)
    applySettings(value)
    onSettingsChanged?(value)
  }
  public func report(_ text: String) { message = text }
  public func applySettings(_ value: SettingsPayload) {
    guard value.revision > settings.revision else { return }
    settings = value
    if !value.sound { onSoundStop?() }
  }
  public func receivePhoneCommand(_ envelope: WireEnvelope) -> Receipt {
    guard connected, envelope.isValid, envelope.sessionID == sessionID,
      envelope.sequence > phoneSequence else { return .stale }
    guard state.phase != .charging && state.phase != .ready else { return .unavailable }
    if envelope.kind == .select,
      let selection = try? JSONDecoder().decode(SelectPayload.self, from: envelope.payload) {
      phoneSequence = envelope.sequence
      send(.select(selection.spell)); return .accepted
    }
    if envelope.kind == .hello,
      let hello = try? JSONDecoder().decode(HelloPayload.self, from: envelope.payload), hello.requestedMode != .practice {
      phoneSequence = envelope.sequence
      setMode(hello.requestedMode); return .accepted
    }
    return .invalid
  }
  @discardableResult public func receive(_ envelope: WireEnvelope) -> Bool {
    guard connected, envelope.isValid, envelope.sessionID == sessionID,
      envelope.kind == .armGrant, state.phase == .charging, state.charge == 1,
      let grant = try? JSONDecoder().decode(ArmGrantPayload.self, from: envelope.payload),
      grant.permit.spell == state.spell,
      grant.requestEventID == armRequestID, armRequestID != nil, armGeneration == generation,
      !consumedEvents.contains(envelope.eventID), !consumedTokens.contains(grant.permit.token),
      let duration = PermitTiming.watchReadyDuration(mode: mode, grantValidFor: grant.validFor) else { return false }
    phoneSequence = max(phoneSequence, envelope.sequence)
    consumedEvents.append(envelope.eventID); consumedTokens.append(grant.permit.token)
    if consumedEvents.count > 256 { consumedEvents.removeFirst() }
    if consumedTokens.count > 256 { consumedTokens.removeFirst() }
    armRequestID = nil; armGeneration = nil
    permit = grant.permit; readyDeadline = now() + duration
    state = CastReducer.reduce(state, .armed); onFeedback?(.ready); message = "就绪，挥动或轻点施法"
    return true
  }
  public func tick() {
    if let deadline = readyDeadline, now() >= deadline { send(.timeout) }
  }
  public func sample(_ sample: MotionSample) {
    tick()
    if trigger.update(sample: sample, state: state, now: now())?.accepted == true { send(.trigger) }
  }
  public func send(_ action: CastAction) {
    if case .trigger = action {
      guard state.phase == .ready, readyDeadline.map({ now() < $0 }) ?? false,
        now() - lastRelease >= 0.7 else { tick(); return }
      if mode != .practice {
        guard connected, let permit, link != nil else { return }
        let request = make(.cast, CastPayload(permit: permit, charge: state.charge))
        self.permit = nil; readyDeadline = nil
        state = CastReducer.reduce(state, .trigger); onMotionStop?()
        let epoch = generation
        submit(request) { [weak self] response in
          guard let self, epoch == self.generation, response.sessionID == self.sessionID,
            let ack = try? JSONDecoder().decode(AckPayload.self, from: response.payload),
            ack.eventID == request.eventID, ack.receipt == .accepted else {
            self?.message = "施法未接受，请重新准备"; return
          }
          self.onFeedback?(.released); self.message = "施法成功"
        } failure: { [weak self] in self?.message = "结果未知，请重新准备" }
      } else {
        state = CastReducer.reduce(state, .trigger); onFeedback?(.released); onMotionStop?()
        submit(make(.practiceResult, SelectPayload(spell: state.spell)), success: { _ in })
      }
      lastRelease = now(); permit = nil; readyDeadline = nil; return
    }
    let before = state.phase
    state = CastReducer.reduce(state, action)
    switch action {
    case .pause:
      cancelCycle(revoke: .pause); connected = false
      onMotionStop?(); onSoundStop?(); onFeedback?(.paused)
    case .resume:
      armRequested = false; trigger.reset(); if mode != .practice { connect() }
    case .prepare where before != state.phase:
      cancelCycle(revoke: .pause); trigger.reset(); onMotionStart?(); onFeedback?(.start)
    case .crown where state.phase == .charging && state.charge < 1:
      if armRequested { cancelCycle(revoke: .pause) }
    case .crown where state.phase == .charging && state.charge == 1 && !armRequested:
      armRequested = true
      if mode == .practice {
        state = CastReducer.reduce(state, .armed); readyDeadline = now() + 4; onFeedback?(.ready)
      } else if connected, link != nil {
        let request = make(.armRequest, ArmRequestPayload(spell: state.spell, charge: 1))
        armRequestID = request.eventID; armGeneration = generation
        submit(request) { [weak self] response in
          guard let self, response.sessionID == self.sessionID else { return }
          if response.kind == .armGrant { self.receive(response) }
          else if let ack = try? JSONDecoder().decode(AckPayload.self, from: response.payload),
            ack.eventID == request.eventID, ack.receipt == .accepted {
            self.message = "已蓄满，等待 iPhone 准备"
          } else { self.disconnect(reason: "舞台尚未准备，请重试") }
        } failure: { [weak self] in self?.disconnect(reason: "连接中断，请重试") }
      } else { disconnect(reason: "请先连接 iPhone 舞台") }
    case .timeout:
      cancelCycle(revoke: .pause); onMotionStop?(); onFeedback?(.retry)
    case .reset, .select:
      cancelCycle(revoke: .end); onMotionStop?(); onSoundStop?()
    default: break
    }
  }
}
