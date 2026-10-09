import Foundation

public struct SessionPermit: Codable, Sendable, Equatable {
  public let sessionID: UUID
  public let token: UUID
  public let spell: SpellID
  public init(sessionID: UUID, token: UUID, spell: SpellID) {
    self.sessionID = sessionID
    self.token = token
    self.spell = spell
  }
}
public enum WireKind: String, Codable, Sendable, CaseIterable {
  case hello, select, armRequest, armGrant, cast, ack, pause, end, settings
}
public struct WireEnvelope: Codable, Sendable {
  public let version: Int
  public let eventID: UUID
  public let sessionID: UUID
  public let sequence: UInt64
  public let kind: WireKind
  public let payload: Data
  public init(
    version: Int = 1, eventID: UUID, sessionID: UUID, sequence: UInt64, kind: WireKind,
    payload: Data
  ) {
    self.version = version
    self.eventID = eventID
    self.sessionID = sessionID
    self.sequence = sequence
    self.kind = kind
    self.payload = payload
  }
  public static func decode(_ data: Data) -> WireEnvelope? {
    guard data.count <= 16384, let e = try? JSONDecoder().decode(Self.self, from: data), e.isValid
    else { return nil }
    return e
  }
  public var isValid: Bool {
    guard version == 1, let encoded = try? JSONEncoder().encode(self), encoded.count <= 16384 else {
      return false
    }
    let d = JSONDecoder()
    switch kind {
    case .hello:
      guard let p = try? d.decode(HelloPayload.self, from: payload) else { return false }
      return p.protocolVersion == 1 && !p.appVersion.isEmpty
    case .select: return (try? d.decode(SelectPayload.self, from: payload)) != nil
    case .armRequest:
      guard let p = try? d.decode(ArmRequestPayload.self, from: payload) else { return false }
      return Self.chargeValid(p.charge)
    case .armGrant:
      guard let p = try? d.decode(ArmGrantPayload.self, from: payload) else { return false }
      return p.validFor.isFinite && p.validFor > 0 && p.permit.sessionID == sessionID
    case .cast:
      guard let p = try? d.decode(CastPayload.self, from: payload) else { return false }
      return Self.chargeValid(p.charge) && p.permit.sessionID == sessionID
    case .ack: return (try? d.decode(AckPayload.self, from: payload)) != nil
    case .pause, .end:
      guard let p = try? d.decode(ReasonPayload.self, from: payload) else { return false }
      return !p.reason.isEmpty
    case .settings: return (try? d.decode(SettingsPayload.self, from: payload)) != nil
    }
  }
  private static func chargeValid(_ c: Double) -> Bool { c.isFinite && (0...1).contains(c) }
}
public struct HelloPayload: Codable, Sendable {
  public let appVersion: String
  public let protocolVersion: Int
  public let requestedMode: PlayMode
  public init(appVersion: String, protocolVersion: Int = 1, requestedMode: PlayMode) {
    self.appVersion = appVersion
    self.protocolVersion = protocolVersion
    self.requestedMode = requestedMode
  }
}
public struct SelectPayload: Codable, Sendable {
  public let spell: SpellID
  public init(spell: SpellID) { self.spell = spell }
}
public struct ArmRequestPayload: Codable, Sendable {
  public let spell: SpellID
  public let charge: Double
  public init(spell: SpellID, charge: Double) {
    self.spell = spell
    self.charge = charge
  }
}
public struct ArmGrantPayload: Codable, Sendable {
  public let permit: SessionPermit
  public let validFor: Double
  public init(permit: SessionPermit, validFor: Double) {
    self.permit = permit
    self.validFor = validFor
  }
}
public struct CastPayload: Codable, Sendable {
  public let permit: SessionPermit
  public let charge: Double
  public init(permit: SessionPermit, charge: Double) {
    self.permit = permit
    self.charge = charge
  }
}
public enum Receipt: String, Codable, Sendable {
  case accepted, duplicate, stale, invalid, unavailable
}
public struct AckPayload: Codable, Sendable, Equatable {
  public let receipt: Receipt
  public let eventID: UUID
  public init(receipt: Receipt, eventID: UUID) {
    self.receipt = receipt
    self.eventID = eventID
  }
}
public struct ReasonPayload: Codable, Sendable {
  public let reason: String
  public init(reason: String) { self.reason = reason }
}
public struct SettingsPayload: Codable, Sendable {
  public let revision: UInt64
  public let sound: Bool
  public let haptics: Bool
  public let reducedMotion: Bool
  public init(revision: UInt64, sound: Bool, haptics: Bool, reducedMotion: Bool) {
    self.revision = revision
    self.sound = sound
    self.haptics = haptics
    self.reducedMotion = reducedMotion
  }
}
public protocol LiveLink: Sendable {
  func send(_ envelope: WireEnvelope) async throws -> WireEnvelope
}

/// Converts a duration hint, never the other device's absolute clock.
public enum PermitTiming {
  public static func watchReadyDuration(mode: PlayMode, grantValidFor: Double) -> Double? {
    guard grantValidFor.isFinite, grantValidFor > 0 else { return nil }
    let duration = mode == .showOff ? grantValidFor - 0.3 : min(4, grantValidFor)
    return duration > 0 ? duration : nil
  }
}
