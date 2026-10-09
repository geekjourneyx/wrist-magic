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
