import XCTest

@testable import WristMagicCore

final class DomainTests: XCTestCase {
  func testReducerArmingAndPause() {
    let s = CastState(spell: .fireball, phase: .selecting, charge: 0)
    XCTAssertEqual(CastReducer.reduce(s, .trigger), s)
    let full = CastReducer.reduce(CastReducer.reduce(s, .prepare), .crown(1.4))
    XCTAssertEqual(full.phase, .charging)
    XCTAssertEqual(CastReducer.reduce(full, .trigger), full)
    let ready = CastReducer.reduce(full, .armed)
    XCTAssertEqual(CastReducer.reduce(ready, .select(.lightning)), ready)
    let fired = CastReducer.reduce(ready, .trigger)
    XCTAssertEqual(CastReducer.reduce(fired, .trigger), fired)
    XCTAssertEqual(CastReducer.reduce(full, .crown(.nan)), full)
    XCTAssertEqual(CastReducer.reduce(CastReducer.reduce(ready, .pause), .resume), s)
  }
  func testClipBoundariesAndMonotonicFrames() {
    var t = ClipTimeline()
    t.begin(firstFrameTime: 10)
    XCTAssertTrue(t.canCast(at: 14.499))
    XCTAssertFalse(t.canCast(at: 14.5))
    XCTAssertFalse(t.shouldFinish(at: 15.999))
    XCTAssertTrue(t.shouldFinish(at: 16))
    XCTAssertTrue(t.acceptFrame(at: 11))
    XCTAssertFalse(t.acceptFrame(at: 10.5))
    XCTAssertEqual(t.disposition(at: 11.999, interrupted: true), .discard)
    XCTAssertEqual(t.disposition(at: 12, interrupted: true), .interrupted)
  }
  func testRetryInvalidChargeAndPermitLocalDurations() {
    let ready = CastState(spell: .lightning, phase: .ready, charge: 1)
    let retry = CastReducer.reduce(ready, .timeout)
    XCTAssertEqual(retry.phase, .retry)
    XCTAssertEqual(retry.charge, 0)
    let charging = CastReducer.reduce(retry, .prepare)
    XCTAssertEqual(CastReducer.reduce(charging, .crown(-0.1)).charge, 0)
    XCTAssertEqual(CastReducer.reduce(charging, .crown(.infinity)), charging)
    XCTAssertEqual(CastReducer.reduce(charging, .armed), charging)
    XCTAssertEqual(PermitTiming.watchReadyDuration(mode: .reality, grantValidFor: 5), 4)
    XCTAssertEqual(PermitTiming.watchReadyDuration(mode: .showOff, grantValidFor: 1), 0.7)
    XCTAssertNil(PermitTiming.watchReadyDuration(mode: .showOff, grantValidFor: 0.3))
  }
}
