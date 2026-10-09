import XCTest
@testable import WristMagiciOS
import WristMagicCore

@MainActor final class ShowOffFlowTests: XCTestCase {
  func testCountdownDoesNotEmitEffectOrPermit() {
    let authority = SessionCoordinator()
    authority.foreground = true; authority.trackingNormal = true
    XCTAssertFalse(authority.isReady)
    XCTAssertNil(authority.grantIfReady(now: 3))
  }
  func testCameraMoveInvalidatesFixedComposition() {
    var gate = CameraMovementGate()
    XCTAssertFalse(gate.update(distance: 0.16, angle: 0, now: 1))
    XCTAssertFalse(gate.update(distance: 0.16, angle: 0, now: 1.2))
    XCTAssertTrue(gate.update(distance: 0.16, angle: 0, now: 1.31))
    gate.reset()
    XCTAssertFalse(gate.update(distance: 0, angle: 11, now: 2))
    XCTAssertTrue(gate.update(distance: 0, angle: 11, now: 2.31))
  }
}
