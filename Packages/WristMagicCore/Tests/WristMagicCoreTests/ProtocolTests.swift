import XCTest

@testable import WristMagicCore

final class ProtocolTests: XCTestCase {
  let session = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
  func envelope<T: Encodable>(
    _ payload: T, kind: WireKind = .cast, sequence: UInt64 = 1, id: UUID = UUID()
  ) -> WireEnvelope {
    WireEnvelope(
      eventID: id, sessionID: session, sequence: sequence, kind: kind,
      payload: try! JSONEncoder().encode(payload))
  }
  func testSingleUseExpiryReplayAndOriginalAcknowledgement() {
    var gate = EventGate(sessionID: session)
    let permit = gate.grant(sessionID: session, spell: .fireball, now: 10, validFor: 5)
    let event = envelope(CastPayload(permit: permit, charge: 1))
    XCTAssertEqual(gate.accept(event, now: 11), .accepted)
    XCTAssertEqual(gate.accept(event, now: 12), .duplicate)
    XCTAssertEqual(
      gate.acknowledgement(for: event.eventID),
      AckPayload(receipt: .accepted, eventID: event.eventID))
    XCTAssertEqual(
      gate.accept(envelope(CastPayload(permit: permit, charge: 1), sequence: 2), now: 12), .stale)
    let p = gate.grant(sessionID: session, spell: .lightning, now: 12, validFor: 5)
    XCTAssertEqual(
      gate.accept(envelope(CastPayload(permit: p, charge: 1), sequence: 3), now: 17), .stale)
    gate.reset(sessionID: UUID())
    XCTAssertEqual(gate.accept(event, now: 18), .stale)
  }
  func testWrongTokenSpellRollbackAndReceiverClock() {
    var gate = EventGate(sessionID: session)
    let p = gate.grant(sessionID: session, spell: .fireball, now: 10, validFor: 5)
    let wrong = SessionPermit(sessionID: session, token: p.token, spell: .lightning)
    XCTAssertEqual(gate.accept(envelope(CastPayload(permit: wrong, charge: 1)), now: 11), .stale)
    XCTAssertEqual(
      gate.accept(envelope(SelectPayload(spell: .fireball), kind: .select, sequence: 4), now: 12),
      .accepted)
    XCTAssertEqual(
      gate.accept(envelope(CastPayload(permit: p, charge: 1), sequence: 3), now: 13), .stale)
    XCTAssertEqual(
      gate.accept(envelope(CastPayload(permit: p, charge: 1), sequence: 5), now: 11), .stale)
    XCTAssertEqual(
      gate.accept(envelope(CastPayload(permit: p, charge: 1), sequence: 5), now: 14), .accepted)
  }
  func testEveryPayloadRoundTripAndMalformedInput() {
    let p = SessionPermit(sessionID: session, token: UUID(), spell: .fireball)
    let all: [WireEnvelope] = [
      envelope(HelloPayload(appVersion: "1", requestedMode: .reality), kind: .hello),
      envelope(SelectPayload(spell: .lightning), kind: .select),
      envelope(ArmRequestPayload(spell: .fireball, charge: 1), kind: .armRequest),
      envelope(ArmGrantPayload(permit: p, validFor: 4), kind: .armGrant),
      envelope(CastPayload(permit: p, charge: 1)),
      envelope(AckPayload(receipt: .accepted, eventID: UUID()), kind: .ack),
      envelope(ReasonPayload(reason: "background"), kind: .pause),
      envelope(ReasonPayload(reason: "exit"), kind: .end),
      envelope(
        SettingsPayload(revision: 1, sound: true, haptics: true, reducedMotion: false),
        kind: .settings),
    ]
    for e in all { XCTAssertNotNil(WireEnvelope.decode(try! JSONEncoder().encode(e))) }
    XCTAssertNil(WireEnvelope.decode(Data("invalid".utf8)))
    XCTAssertNil(WireEnvelope.decode(Data(repeating: 32, count: 16385)))
    XCTAssertFalse(envelope(CastPayload(permit: p, charge: 1.01)).isValid)
    let malformed = WireEnvelope(
      eventID: UUID(), sessionID: session, sequence: 1, kind: .cast,
      payload: Data("{\"charge\":\"NaN\"}".utf8))
    var gate = EventGate(sessionID: session)
    XCTAssertEqual(gate.accept(malformed, now: 1), .invalid)
    XCTAssertNil(gate.acknowledgement(for: malformed.eventID))
    let valid = try! JSONEncoder().encode(all[0])
    let text = String(decoding: valid, as: UTF8.self)
    XCTAssertNil(
      WireEnvelope.decode(
        Data(text.replacingOccurrences(of: "\"version\":1", with: "\"version\":2").utf8)))
    XCTAssertNil(
      WireEnvelope.decode(Data(text.replacingOccurrences(of: "\"hello\"", with: "\"future\"").utf8))
    )
  }
  func testCompleteCastPayloadRejectsNonfiniteEncoding() {
    let permit = SessionPermit(sessionID: session, token: UUID(), spell: .fireball)
    for charge in [Double.nan, Double.infinity, -Double.infinity] {
      XCTAssertThrowsError(try JSONEncoder().encode(CastPayload(permit: permit, charge: charge)))
    }
  }
  func testCacheBoundAndReset() {
    var gate = EventGate(sessionID: session)
    let first = envelope(SelectPayload(spell: .fireball), kind: .select)
    XCTAssertEqual(gate.accept(first, now: 0), .accepted)
    for i in 2...257 {
      XCTAssertEqual(
        gate.accept(
          envelope(SelectPayload(spell: .fireball), kind: .select, sequence: UInt64(i)),
          now: Double(i)), .accepted)
    }
    XCTAssertNil(gate.acknowledgement(for: first.eventID))
    XCTAssertEqual(gate.accept(first, now: 258), .stale)
    gate.reset(sessionID: session)
    XCTAssertEqual(gate.accept(first, now: 0), .accepted)
  }
}
