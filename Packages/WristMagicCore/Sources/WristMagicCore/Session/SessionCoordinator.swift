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
  private var chargedRequestID: UUID?
  private var gate = EventGate()
  private var sequence: UInt64 = 0
  private var responses: [UUID: WireEnvelope] = [:]
  private var responseOrder: [UUID] = []
  private var retiredSessions: [UUID] = []
  public init() {}
  public var isReady: Bool {
    sessionID != nil && foreground && trackingNormal &&
      (mode != .showOff || (captureFirstFrame != nil && captureCutoff != nil))
  }
  public func invalidate(reason: String) {
    if let sessionID { retire(sessionID) }
    sessionID = nil; chargedSpell = nil; chargedRequestID = nil; gate.revokePermits()
  }
  private func retire(_ id: UUID) {
    retiredSessions.append(id)
    if retiredSessions.count > 256 { retiredSessions.removeFirst() }
  }
  private func remember(_ response: WireEnvelope, for event: UUID) {
    responses[event] = response; responseOrder.append(event)
    if responseOrder.count > 256 { responses.removeValue(forKey: responseOrder.removeFirst()) }
  }
  private func refreshAvailability() {
    gate.available = isReady
    if !isReady { gate.revokePermits() }
    if !foreground || !trackingNormal { chargedSpell = nil; chargedRequestID = nil }
  }
  private func envelope<T: Encodable>(_ kind: WireKind, _ payload: T, session: UUID) -> WireEnvelope {
    sequence += 1
    return WireEnvelope(eventID: UUID(), sessionID: session, sequence: sequence,
      kind: kind, payload: (try? JSONEncoder().encode(payload)) ?? Data())
  }
  public func receive(_ request: WireEnvelope, now: Double) -> WireEnvelope {
    if retiredSessions.contains(request.sessionID) {
      return envelope(.ack, AckPayload(receipt: .stale, eventID: request.eventID), session: request.sessionID)
    }
    if let cached = responses[request.eventID], cached.sessionID == sessionID { return cached }
    if request.isValid, request.kind == .hello,
       let hello = try? JSONDecoder().decode(HelloPayload.self, from: request.payload) {
      if sessionID != request.sessionID {
        if let sessionID { retire(sessionID) }
        responses = [:]; responseOrder = []
        sessionID = request.sessionID; gate.reset(sessionID: request.sessionID)
        chargedSpell = nil; chargedRequestID = nil; sequence = 0
      }
      mode = hello.requestedMode
      refreshAvailability()
      return envelope(.ack, AckPayload(receipt: foreground ? .accepted : .unavailable,
        eventID: request.eventID), session: request.sessionID)
    }
    if request.kind == .armRequest,
       let arm = try? JSONDecoder().decode(ArmRequestPayload.self, from: request.payload), arm.charge != 1 {
      return envelope(.ack, AckPayload(receipt: .invalid, eventID: request.eventID), session: request.sessionID)
    }
    // Charging may be acknowledged before recording starts. It is not a cast capability.
    gate.available = foreground && sessionID == request.sessionID &&
      ([.armRequest, .pause, .end].contains(request.kind) || isReady)
    let receipt = gate.accept(request, now: now)
    if receipt == .accepted {
      if request.kind == .armRequest,
         let arm = try? JSONDecoder().decode(ArmRequestPayload.self, from: request.payload), arm.charge == 1 {
        gate.revokePermits()
        chargedSpell = arm.spell; chargedRequestID = request.eventID; onCharged?(arm.spell)
        if let grant = grantIfReady(now: now) { remember(grant, for: request.eventID); return grant }
      } else if request.kind == .cast,
                let cast = try? JSONDecoder().decode(CastPayload.self, from: request.payload) {
        chargedSpell = nil; chargedRequestID = nil; onAcceptedCast?(cast.permit.spell, now)
      } else if request.kind == .pause || request.kind == .end {
        chargedSpell = nil; chargedRequestID = nil
      }
    }
    let ack = gate.acknowledgement(for: request.eventID) ?? AckPayload(receipt: receipt, eventID: request.eventID)
    let response = envelope(.ack, ack, session: request.sessionID)
    remember(response, for: request.eventID)
    return response
  }
  /// Called after the first valid captured frame; no arm-request reply waits on countdown UI.
  public func grantIfReady(now: Double) -> WireEnvelope? {
    guard isReady, let sessionID, let spell = chargedSpell, let requestID = chargedRequestID else { return nil }
    let validFor = mode == .showOff ? (captureCutoff! - now) : 5
    guard validFor > 0.3 else { return nil }
    gate.available = true
    let permit = gate.grant(sessionID: sessionID, spell: spell, now: now, validFor: validFor)
    chargedSpell = nil; chargedRequestID = nil
    return envelope(.armGrant, ArmGrantPayload(permit: permit, validFor: validFor, requestEventID: requestID), session: sessionID)
  }
  public func captureDidStart(firstFrame: Double, cutoff: Double, now: Double) {
    captureFirstFrame = firstFrame; captureCutoff = cutoff
    if let grant = grantIfReady(now: now) { onPushGrant?(grant) }
  }
}
