import XCTest
@testable import WristMagicCore

final class AuthorityTests: XCTestCase {
  private func envelope<T: Encodable>(_ kind: WireKind, _ value: T, session: UUID, sequence: UInt64) -> WireEnvelope {
    WireEnvelope(eventID: UUID(), sessionID: session, sequence: sequence, kind: kind,
      payload: try! JSONEncoder().encode(value))
  }
  func testShowOffAcknowledgesChargeThenPushesFirstFrameGrant() {
    MainActor.assumeIsolated {
      let authority = SessionCoordinator()
      authority.foreground = true; authority.trackingNormal = true
      let session = UUID()
      let hello = envelope(.hello, HelloPayload(appVersion: "test", requestedMode: .showOff), session: session, sequence: 1)
      _ = authority.receive(hello, now: 0)
      let arm = envelope(.armRequest, ArmRequestPayload(spell: .lightning, charge: 1), session: session, sequence: 2)
      let chargeAck = authority.receive(arm, now: 1)
      XCTAssertEqual(chargeAck.kind, .ack)
      XCTAssertEqual(authority.chargedSpell, .lightning)
      XCTAssertFalse(authority.isReady)
      var pushed: WireEnvelope?
      authority.onPushGrant = { pushed = $0 }
      authority.captureDidStart(firstFrame: 2, cutoff: 6.5, now: 2)
      XCTAssertEqual(pushed?.kind, .armGrant)
      let grant = try! JSONDecoder().decode(ArmGrantPayload.self, from: pushed!.payload)
      XCTAssertEqual(grant.validFor, 4.5)
      var emitted = 0
      authority.onAcceptedCast = { _, _ in emitted += 1 }
      let cast = envelope(.cast, CastPayload(permit: grant.permit, charge: 1), session: session, sequence: 3)
      _ = authority.receive(cast, now: 3)
      _ = authority.receive(cast, now: 3.1)
      XCTAssertEqual(emitted, 1)
    }
  }
  func testInactivePhoneRejectsCastAndReconnectRetiresOldSession() {
    MainActor.assumeIsolated {
      let authority = SessionCoordinator()
      authority.foreground = true; authority.trackingNormal = true
      let session = UUID()
      let hello = envelope(.hello, HelloPayload(appVersion: "test", requestedMode: .reality), session: session, sequence: 1)
      _ = authority.receive(hello, now: 0)
      let arm = envelope(.armRequest, ArmRequestPayload(spell: .fireball, charge: 1), session: session, sequence: 2)
      let response = authority.receive(arm, now: 1)
      let duplicate = authority.receive(arm, now: 1.3)
      XCTAssertEqual(response.eventID, duplicate.eventID)
      let grant = try! JSONDecoder().decode(ArmGrantPayload.self, from: response.payload)
      authority.foreground = false
      let cast = envelope(.cast, CastPayload(permit: grant.permit, charge: 1), session: session, sequence: 3)
      let rejected = authority.receive(cast, now: 2)
      let ack = try! JSONDecoder().decode(AckPayload.self, from: rejected.payload)
      XCTAssertEqual(ack.receipt, .unavailable)
      authority.invalidate(reason: "disconnect")
      authority.foreground = true
      let replay = authority.receive(hello, now: 3)
      XCTAssertEqual(try! JSONDecoder().decode(AckPayload.self, from: replay.payload).receipt, .stale)
      XCTAssertNil(authority.sessionID)
      let newSession = UUID()
      _ = authority.receive(envelope(.hello, HelloPayload(appVersion: "test", requestedMode: .reality), session: newSession, sequence: 1), now: 4)
      XCTAssertEqual(authority.sessionID, newSession)
      XCTAssertNil(authority.chargedSpell)
    }
  }
}
