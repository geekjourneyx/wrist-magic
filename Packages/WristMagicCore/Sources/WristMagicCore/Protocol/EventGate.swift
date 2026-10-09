import Foundation

/// Own on the receiving session actor. All times are receiver monotonic seconds.
public struct EventGate: Sendable {
  private var sessionID: UUID?
  private var permits: [UUID: (SessionPermit, Double)] = [:]
  private var receipts: [UUID: AckPayload] = [:]
  private var order: [UUID] = []
  private var sequence: UInt64?
  private var clock: Double?
  private let makeUUID: @Sendable () -> UUID
  public var available = true
  public init(sessionID: UUID? = nil, makeUUID: @escaping @Sendable () -> UUID = { UUID() }) {
    self.sessionID = sessionID
    self.makeUUID = makeUUID
  }
  public mutating func reset(sessionID: UUID) {
    self.sessionID = sessionID
    permits = [:]
    receipts = [:]
    order = []
    sequence = nil
    clock = nil
  }
  public mutating func revokePermits() { permits = [:] }
  public mutating func grant(sessionID: UUID, spell: SpellID, now: Double, validFor: Double)
    -> SessionPermit
  {
    permits = [:]
    let p = SessionPermit(sessionID: sessionID, token: makeUUID(), spell: spell)
    if self.sessionID == sessionID, available, advance(now), validFor.isFinite, validFor > 0,
      (now + validFor).isFinite
    {
      permits = [p.token: (p, now + validFor)]
    }
    return p
  }
  public func acknowledgement(for eventID: UUID) -> AckPayload? { receipts[eventID] }
  public mutating func accept(_ envelope: WireEnvelope, now: Double) -> Receipt {
    guard envelope.isValid else { return .invalid }
    guard envelope.sessionID == sessionID else { return .stale }
    if receipts[envelope.eventID] != nil { return .duplicate }
    guard advance(now) else { return .stale }
    var result: Receipt = .accepted
    if !available {
      result = .unavailable
    } else if let sequence, envelope.sequence <= sequence {
      result = .stale
    } else if envelope.kind == .cast {
      let p = try! JSONDecoder().decode(CastPayload.self, from: envelope.payload)
      if p.charge != 1 {
        result = .invalid
      } else if let entry = permits[p.permit.token], entry.0 == p.permit, now < entry.1 {
        permits.removeValue(forKey: p.permit.token)
      } else {
        result = .stale
      }
    }
    if result == .accepted {
      sequence = envelope.sequence
      if envelope.kind == .pause || envelope.kind == .end { revokePermits() }
    }
    receipts[envelope.eventID] = AckPayload(receipt: result, eventID: envelope.eventID)
    order.append(envelope.eventID)
    if order.count > 256 { receipts.removeValue(forKey: order.removeFirst()) }
    return result
  }
  private mutating func advance(_ now: Double) -> Bool {
    guard now.isFinite, clock.map({ now >= $0 }) ?? true else { return false }
    clock = now
    return true
  }
}
