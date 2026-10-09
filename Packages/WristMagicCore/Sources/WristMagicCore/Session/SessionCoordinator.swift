import Foundation

/// Phone authority. Availability is supplied by the camera/capture owner, never connectivity alone.
@MainActor public final class SessionCoordinator {
  public private(set) var sessionID: UUID?
  public private(set) var mode: PlayMode = .reality
  public private(set) var chargedSpell: SpellID?
  public var foreground = false { didSet { refreshAvailability() } }
  public var trackingNormal = false { didSet { refreshAvailability() } }
  public var captureFirstFrame: Double? { didSet { refreshAvailability() } }
  public var captureCutoff: Double? { didSet { refreshAvailability() } }
  public var onAcceptedCast: ((SpellID, Double) -> Void)?
  public var onCharged: ((SpellID) -> Void)?
  public var onPushGrant: ((WireEnvelope) -> Void)?
  private var gate = EventGate()
  private var sequence: UInt64 = 0
  public init() {}
  public var isReady: Bool {
    sessionID != nil && foreground && trackingNormal &&
      (mode != .showOff || (captureFirstFrame != nil && captureCutoff != nil))
  }
  public func invalidate(reason: String) {
    sessionID = nil; chargedSpell = nil; gate.revokePermits()
  }
  private func refreshAvailability() {
    gate.available = isReady
    if !isReady { gate.revokePermits() }
  }
  private func envelope<T: Encodable>(_ kind: WireKind, _ payload: T, session: UUID) -> WireEnvelope {
    sequence += 1
    return WireEnvelope(eventID: UUID(), sessionID: session, sequence: sequence,
      kind: kind, payload: (try? JSONEncoder().encode(payload)) ?? Data())
  }
  public func receive(_ request: WireEnvelope, now: Double) -> WireEnvelope {
    if request.isValid, request.kind == .hello,
       let hello = try? JSONDecoder().decode(HelloPayload.self, from: request.payload) {
      if sessionID != request.sessionID {
        sessionID = request.sessionID; gate.reset(sessionID: request.sessionID)
        chargedSpell = nil; sequence = 0
      }
      mode = hello.requestedMode
      refreshAvailability()
      return envelope(.ack, AckPayload(receipt: foreground ? .accepted : .unavailable,
        eventID: request.eventID), session: request.sessionID)
    }
    // Charging may be acknowledged before recording starts. It is not a cast capability.
    gate.available = foreground && sessionID == request.sessionID &&
      (request.kind == .armRequest || isReady)
    let receipt = gate.accept(request, now: now)
    if receipt == .accepted {
      if request.kind == .armRequest,
         let arm = try? JSONDecoder().decode(ArmRequestPayload.self, from: request.payload), arm.charge == 1 {
        chargedSpell = arm.spell; onCharged?(arm.spell)
        if let grant = grantIfReady(now: now) { return grant }
      } else if request.kind == .cast,
                let cast = try? JSONDecoder().decode(CastPayload.self, from: request.payload) {
        chargedSpell = nil; onAcceptedCast?(cast.permit.spell, now)
      } else if request.kind == .pause || request.kind == .end {
        chargedSpell = nil
      }
    }
    let ack = gate.acknowledgement(for: request.eventID) ?? AckPayload(receipt: receipt, eventID: request.eventID)
    return envelope(.ack, ack, session: request.sessionID)
  }
  /// Called after the first valid captured frame; no arm-request reply waits on countdown UI.
  public func grantIfReady(now: Double) -> WireEnvelope? {
    guard isReady, let sessionID, let spell = chargedSpell else { return nil }
    let validFor = mode == .showOff ? (captureCutoff! - now) : 5
    guard validFor > 0.3 else { return nil }
    gate.available = true
    let permit = gate.grant(sessionID: sessionID, spell: spell, now: now, validFor: validFor)
    chargedSpell = nil
    return envelope(.armGrant, ArmGrantPayload(permit: permit, validFor: validFor), session: sessionID)
  }
  public func captureDidStart(firstFrame: Double, cutoff: Double, now: Double) {
    captureFirstFrame = firstFrame; captureCutoff = cutoff
    if let grant = grantIfReady(now: now) { onPushGrant?(grant) }
  }
}
