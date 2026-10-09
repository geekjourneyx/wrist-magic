import XCTest
import WristMagicCore
@testable import WristMagiciOS

private actor AuthorityLink: LiveLink {
  let authority: SessionCoordinator
  init(_ authority: SessionCoordinator) { self.authority = authority }
  func send(_ envelope: WireEnvelope) async throws -> WireEnvelope {
    await authority.receive(envelope, now: ProcessInfo.processInfo.systemUptime)
  }
}
final class LiveLinkTests: XCTestCase {
  @MainActor func testRealWatchModelAndPhoneAuthorityAcceptOnce() async {
    let authority = SessionCoordinator()
    authority.foreground = true
    authority.trackingNormal = true
    var emitted = 0
    authority.onAcceptedCast = { _, _ in emitted += 1 }
    let model = WatchCastModel(link: AuthorityLink(authority))
    model.setMode(.reality)
    for _ in 0..<100 where !model.connected { try? await Task.sleep(for: .milliseconds(10)) }
    XCTAssertTrue(model.connected)
    model.send(.prepare)
    model.send(.crown(1))
    for _ in 0..<100 where model.state.phase != .ready { try? await Task.sleep(for: .milliseconds(10)) }
    XCTAssertEqual(model.state.phase, .ready)
    model.send(.trigger)
    model.send(.trigger)
    for _ in 0..<100 where emitted == 0 { try? await Task.sleep(for: .milliseconds(10)) }
    XCTAssertEqual(emitted, 1)
    XCTAssertEqual(model.state.phase, .fired)
    model.disconnect(reason: "test disconnect")
    XCTAssertEqual(model.state.charge, 0)
    XCTAssertEqual(model.state.phase, .selecting)
  }
  @MainActor func testPhoneLinkRemainsUnavailableWithoutForeground() async {
    let authority = SessionCoordinator()
    let link = PhoneLink(coordinator: authority)
    XCTAssertFalse(link.available)
    XCTAssertFalse(authority.isReady)
  }
}

@MainActor private final class DelayedAuthorityLink: LiveLink {
  let authority = SessionCoordinator()
  var sent: [WireEnvelope] = []
  var replies: [UUID: WireEnvelope] = [:]
  var pending: [UUID: CheckedContinuation<WireEnvelope, Error>] = [:]
  var cancelled: [UUID] = []
  init() {
    authority.foreground = true
    authority.trackingNormal = true
  }
  func send(_ envelope: WireEnvelope) async throws -> WireEnvelope {
    try Task.checkCancellation()
    sent.append(envelope)
    let reply = authority.receive(envelope, now: ProcessInfo.processInfo.systemUptime)
    if envelope.kind != .armRequest { return reply }
    replies[envelope.eventID] = reply
    return try await withCheckedThrowingContinuation { pending[envelope.eventID] = $0 }
  }
  func cancelPending(sessionID: UUID) {
    for envelope in sent where envelope.sessionID == sessionID {
      if let continuation = pending.removeValue(forKey: envelope.eventID) {
        cancelled.append(envelope.eventID)
        continuation.resume(throwing: CancellationError())
      }
    }
  }
  func complete(_ eventID: UUID) {
    guard let continuation = pending.removeValue(forKey: eventID), let reply = replies[eventID] else { return }
    continuation.resume(returning: reply)
  }
}

extension LiveLinkTests {
  @MainActor func testCancelledArmCannotRearmNextAttemptAndRevokesAuthority() async {
    let link = DelayedAuthorityLink()
    let model = WatchCastModel(link: link)
    model.setMode(.reality)
    for _ in 0..<100 where !model.connected { try? await Task.sleep(for: .milliseconds(10)) }
    model.send(.prepare)
    model.send(.crown(1))
    for _ in 0..<100 where link.pending.isEmpty { try? await Task.sleep(for: .milliseconds(10)) }
    let attemptA = link.sent.last(where: { $0.kind == .armRequest })!
    let staleGrant = link.replies[attemptA.eventID]!
    model.send(.reset)
    XCTAssertTrue(link.cancelled.contains(attemptA.eventID))
    for _ in 0..<100 where !link.sent.contains(where: { $0.kind == .end }) { try? await Task.sleep(for: .milliseconds(10)) }
    let grantA = try! JSONDecoder().decode(ArmGrantPayload.self, from: staleGrant.payload)
    let oldCast = WireEnvelope(eventID: UUID(), sessionID: attemptA.sessionID, sequence: attemptA.sequence, kind: .cast,
      payload: try! JSONEncoder().encode(CastPayload(permit: grantA.permit, charge: 1)))
    let rejected = link.authority.receive(oldCast, now: ProcessInfo.processInfo.systemUptime)
    XCTAssertEqual(try! JSONDecoder().decode(AckPayload.self, from: rejected.payload).receipt, .stale)
    model.send(.prepare)
    model.send(.crown(1))
    for _ in 0..<100 where link.pending.isEmpty { try? await Task.sleep(for: .milliseconds(10)) }
    let attemptB = link.sent.last(where: { $0.kind == .armRequest })!
    XCTAssertNotEqual(attemptA.eventID, attemptB.eventID)
    XCTAssertFalse(model.receive(staleGrant))
    XCTAssertEqual(model.state.phase, .charging)
    link.complete(attemptB.eventID)
    for _ in 0..<100 where model.state.phase != .ready { try? await Task.sleep(for: .milliseconds(10)) }
    XCTAssertEqual(model.state.phase, .ready)
    let consumed = link.replies[attemptB.eventID]!
    XCTAssertFalse(model.receive(consumed))
    model.send(.reset)
    model.send(.prepare)
    model.send(.crown(1))
    for _ in 0..<100 where link.pending.isEmpty { try? await Task.sleep(for: .milliseconds(10)) }
    let attemptC = link.sent.last(where: { $0.kind == .armRequest })!
    let grantB = try! JSONDecoder().decode(ArmGrantPayload.self, from: consumed.payload)
    let reusedToken = WireEnvelope(eventID: UUID(), sessionID: model.sessionID, sequence: consumed.sequence,
      kind: .armGrant, payload: try! JSONEncoder().encode(ArmGrantPayload(permit: grantB.permit,
        validFor: 5, requestEventID: attemptC.eventID)))
    XCTAssertFalse(model.receive(reusedToken))
    model.send(.pause)
    XCTAssertTrue(link.cancelled.contains(attemptC.eventID))
    for _ in 0..<100 where !link.sent.contains(where: { $0.kind == .pause && $0.sequence > attemptC.sequence }) { try? await Task.sleep(for: .milliseconds(10)) }
    XCTAssertEqual(model.state.phase, .paused)
    XCTAssertFalse(model.receive(staleGrant))
  }
}
