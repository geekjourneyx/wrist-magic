import XCTest
@testable import WristMagicCore
final class SessionTests: XCTestCase {
  func testReachableWithoutHelloIsNotReady() {
    MainActor.assumeIsolated { XCTAssertFalse(SessionCoordinator().isReady) }
  }
  func testLocalPracticeWorksWithoutPhone() {
    MainActor.assumeIsolated {
      let model = WatchCastModel(now: { 1 })
      model.send(.prepare); model.send(.crown(1))
      XCTAssertEqual(model.state.phase, .ready)
      model.send(.trigger)
      XCTAssertEqual(model.state.phase, .fired)
    }
  }
  func testBackgroundInvalidatesCharge() {
    MainActor.assumeIsolated {
      let model = WatchCastModel(now: { 1 })
      model.send(.prepare); model.send(.crown(1)); model.send(.pause)
      XCTAssertEqual(model.state.charge, 0)
      model.send(.resume)
      XCTAssertEqual(model.state.phase, .selecting)
    }
  }
}
