import XCTest
@testable import WristMagicCore

final class AuthorityTests: XCTestCase {
  private static func envelope<T: Encodable>(_ kind: WireKind, _ value: T, session: UUID, sequence: UInt64) -> WireEnvelope {
    WireEnvelope(eventID: UUID(), sessionID: session, sequence: sequence, kind: kind,
      payload: try! JSONEncoder().encode(value))
  }
  func testShowOffAcknowledgesChargeThenPushesFirstFrameGrant() {
    MainActor.assumeIsolated {
      let authority = SessionCoordinator()
      authority.foreground = true; authority.trackingNormal = true
      let session = UUID()
      let hello = Self.envelope(.hello, HelloPayload(appVersion: "test", requestedMode: .showOff), session: session, sequence: 1)
      _ = authority.receive(hello, now: 0)
      let arm = Self.envelope(.armRequest, ArmRequestPayload(spell: .lightning, charge: 1), session: session, sequence: 2)
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
      XCTAssertEqual(grant.requestEventID, arm.eventID)
      var emitted = 0
      authority.onAcceptedCast = { _, _ in emitted += 1 }
      let cast = Self.envelope(.cast, CastPayload(permit: grant.permit, charge: 1), session: session, sequence: 3)
      _ = authority.receive(cast, now: 3)
      _ = authority.receive(cast, now: 3.1)
      XCTAssertEqual(emitted, 1)
      let secondArm = Self.envelope(.armRequest, ArmRequestPayload(spell: .lightning, charge: 1), session: session, sequence: 4)
      let secondReply = authority.receive(secondArm, now: 3.2)
      XCTAssertEqual(secondReply.kind, .ack)
      XCTAssertEqual(try! JSONDecoder().decode(AckPayload.self, from: secondReply.payload).receipt, .unavailable)
      XCTAssertNil(authority.grantIfReady(now: 3.3))
    }
  }
  func testInactivePhoneRejectsCastAndReconnectRetiresOldSession() {
    MainActor.assumeIsolated {
      let authority = SessionCoordinator()
      authority.foreground = true; authority.trackingNormal = true
      let session = UUID()
      let hello = Self.envelope(.hello, HelloPayload(appVersion: "test", requestedMode: .reality), session: session, sequence: 1)
      _ = authority.receive(hello, now: 0)
      let arm = Self.envelope(.armRequest, ArmRequestPayload(spell: .fireball, charge: 1), session: session, sequence: 2)
      let response = authority.receive(arm, now: 1)
      let duplicate = authority.receive(arm, now: 1.3)
      XCTAssertEqual(response.eventID, duplicate.eventID)
      let grant = try! JSONDecoder().decode(ArmGrantPayload.self, from: response.payload)
      authority.foreground = false
      let cast = Self.envelope(.cast, CastPayload(permit: grant.permit, charge: 1), session: session, sequence: 3)
      let rejected = authority.receive(cast, now: 2)
      let ack = try! JSONDecoder().decode(AckPayload.self, from: rejected.payload)
      XCTAssertEqual(ack.receipt, .unavailable)
      authority.invalidate(reason: "disconnect")
      authority.foreground = true
      let replay = authority.receive(hello, now: 3)
      XCTAssertEqual(try! JSONDecoder().decode(AckPayload.self, from: replay.payload).receipt, .stale)
      XCTAssertNil(authority.sessionID)
      let newSession = UUID()
      _ = authority.receive(Self.envelope(.hello, HelloPayload(appVersion: "test", requestedMode: .reality), session: newSession, sequence: 1), now: 4)
      XCTAssertEqual(authority.sessionID, newSession)
      XCTAssertNil(authority.chargedSpell)
    }
  }
  func testPauseRevokesChargeBeforeFutureFirstFrame() {
    MainActor.assumeIsolated {
      let authority = SessionCoordinator()
      authority.foreground = true
      authority.trackingNormal = true
      let session = UUID()
      _ = authority.receive(Self.envelope(.hello,
        HelloPayload(appVersion: "test", requestedMode: .showOff), session: session, sequence: 1), now: 0)
      _ = authority.receive(Self.envelope(.armRequest,
        ArmRequestPayload(spell: .fireball, charge: 1), session: session, sequence: 2), now: 1)
      XCTAssertEqual(authority.chargedSpell, .fireball)
      let reply = authority.receive(Self.envelope(.pause,
        ReasonPayload(reason: "Watch paused"), session: session, sequence: 3), now: 2)
      XCTAssertEqual(try! JSONDecoder().decode(AckPayload.self, from: reply.payload).receipt, .accepted)
      XCTAssertNil(authority.chargedSpell)
      var pushed = false
      authority.onPushGrant = { _ in pushed = true }
      authority.captureDidStart(firstFrame: 3, cutoff: 7.5, now: 3)
      XCTAssertFalse(pushed)
    }
  }

}
