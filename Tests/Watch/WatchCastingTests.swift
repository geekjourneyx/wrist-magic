import XCTest
import WristMagicCore
@testable import WristMagicWatch

final class WatchCastingTests: XCTestCase {
  @MainActor func testBackgroundStopsMotionAndInvalidatesPermit() async {
    var stopped = 0
    let model = WatchCastModel(now: { 1 })
    model.onMotionStop = { stopped += 1 }
    model.send(.prepare)
    model.send(.crown(1))
    model.send(.pause)
    XCTAssertEqual(stopped, 1)
    XCTAssertEqual(model.state.phase, .paused)
    model.send(.trigger)
    XCTAssertEqual(model.state.phase, .paused)
    model.send(.resume)
    XCTAssertEqual(model.state.phase, .selecting)
    XCTAssertEqual(model.state.charge, 0)
  }
  @MainActor func testMutedSettingDoesNotBlockState() async {
    let model = WatchCastModel(now: { 1 })
    model.applySettings(SettingsPayload(revision: 1, sound: false, haptics: false, reducedMotion: true))
    model.send(.prepare)
    model.send(.crown(1))
    model.send(.trigger)
    XCTAssertEqual(model.state.phase, .fired)
    XCTAssertFalse(model.settings.sound)
    model.applySettings(SettingsPayload(revision: 0, sound: true, haptics: true, reducedMotion: false))
    XCTAssertFalse(model.settings.sound)
  }
  @MainActor func testReadyDeadlineAndReleaseCooldown() async {
    var time = 0.0
    let model = WatchCastModel(now: { time })
    model.send(.prepare)
    model.send(.crown(1))
    time = 4
    model.send(.trigger)
    XCTAssertEqual(model.state.phase, .retry)
    model.send(.prepare)
    model.send(.crown(1))
    model.send(.trigger)
    XCTAssertEqual(model.state.phase, .fired)
    model.send(.prepare)
    model.send(.crown(1))
    model.send(.trigger)
    XCTAssertEqual(model.state.phase, .ready)
    time = 4.7
    model.send(.trigger)
    XCTAssertEqual(model.state.phase, .fired)
  }
}
