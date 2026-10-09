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
  public var onSoundStop: (() -> Void)?
  private let now: () -> Double
  private var link: (any LiveLink)?
  private var sequence: UInt64 = 0
  private var generation: UInt64 = 0
  private var permit: SessionPermit?
  private var readyDeadline: Double?
  private var lastRelease: Double = -.infinity
  private var armRequested = false
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
    guard mode != .practice, let link else { return }
    disconnect(reason: "正在连接")
    let epoch = generation
    let hello = make(.hello, HelloPayload(appVersion: "0.1.0", requestedMode: mode))
    Task {
      do {
        let response = try await link.send(hello)
        guard generation == epoch, response.sessionID == sessionID,
          let ack = try? JSONDecoder().decode(AckPayload.self, from: response.payload),
          ack.eventID == hello.eventID, ack.receipt == .accepted else { return }
        connected = true; message = "已连接"
      } catch { if generation == epoch { disconnect(reason: "连接失败，请重试") } }
    }
  }
  public func disconnect(reason: String) {
    generation += 1; sessionID = UUID(); sequence = 0; connected = false
    permit = nil; readyDeadline = nil; armRequested = false; trigger.reset()
    state = CastReducer.reduce(state, .reset)
    onMotionStop?(); onSoundStop?(); message = reason
  }
  public func applySettings(_ value: SettingsPayload) {
    guard value.revision > settings.revision else { return }
    settings = value
    if !value.sound { onSoundStop?() }
  }
  public func receive(_ envelope: WireEnvelope) {
    guard connected, envelope.isValid, envelope.sessionID == sessionID,
      envelope.kind == .armGrant, state.phase == .charging, state.charge == 1,
      let grant = try? JSONDecoder().decode(ArmGrantPayload.self, from: envelope.payload),
      grant.permit.spell == state.spell,
      let duration = PermitTiming.watchReadyDuration(mode: mode, grantValidFor: grant.validFor) else { return }
    permit = grant.permit; readyDeadline = now() + duration
    state = CastReducer.reduce(state, .armed); onFeedback?(.ready); message = "就绪，挥动或轻点施法"
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
        guard connected, let permit, let link else { return }
        let request = make(.cast, CastPayload(permit: permit, charge: state.charge))
        self.permit = nil; readyDeadline = nil
        state = CastReducer.reduce(state, .trigger); onMotionStop?()
        let epoch = generation
        Task {
          do {
            let response = try await link.send(request)
            guard epoch == generation,
              let ack = try? JSONDecoder().decode(AckPayload.self, from: response.payload),
              ack.eventID == request.eventID, ack.receipt == .accepted else {
              if epoch == generation { message = "施法未接受，请重新准备" }; return
            }
            onFeedback?(.released); message = "施法成功"
          } catch { if epoch == generation { message = "结果未知，请重新准备" } }
        }
      } else {
        state = CastReducer.reduce(state, .trigger); onFeedback?(.released); onMotionStop?()
      }
      lastRelease = now(); permit = nil; readyDeadline = nil; return
    }
    let before = state.phase
    state = CastReducer.reduce(state, action)
    switch action {
    case .pause:
      generation += 1; connected = false; permit = nil; readyDeadline = nil
      onMotionStop?(); onSoundStop?(); onFeedback?(.paused)
    case .resume:
      armRequested = false; trigger.reset(); if mode != .practice { connect() }
    case .prepare where before != state.phase:
      armRequested = false; permit = nil; trigger.reset(); onMotionStart?(); onFeedback?(.start)
    case .crown where state.phase == .charging && state.charge == 1 && !armRequested:
      armRequested = true
      if mode == .practice {
        state = CastReducer.reduce(state, .armed); readyDeadline = now() + 4; onFeedback?(.ready)
      } else if connected, let link {
        let request = make(.armRequest, ArmRequestPayload(spell: state.spell, charge: 1))
        let epoch = generation
        Task {
          do {
            let response = try await link.send(request)
            guard epoch == generation else { return }
            if response.kind == .armGrant { receive(response) }
            else if let ack = try? JSONDecoder().decode(AckPayload.self, from: response.payload), ack.receipt == .accepted {
              message = "已蓄满，等待 iPhone 准备"
            } else { disconnect(reason: "舞台尚未准备，请重试") }
          } catch { if epoch == generation { disconnect(reason: "连接中断，请重试") } }
        }
      } else { disconnect(reason: "请先连接 iPhone 舞台") }
    case .timeout:
      permit = nil; readyDeadline = nil; onMotionStop?(); onFeedback?(.retry)
    case .reset, .select:
      permit = nil; readyDeadline = nil; armRequested = false; onMotionStop?(); onSoundStop?()
    default: break
    }
  }
}
