import XCTest
@testable import WristMagiciOS
import WristMagicCore

@MainActor final class EntryFlowTests: XCTestCase {
  func testOlderSettingsRevisionIgnored() {
    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    let store = SettingsStore(defaults: defaults)
    store.update(sound: false, haptic: false, reduceMotion: true)
    store.apply(SettingsPayload(revision: 0, sound: true, haptics: true, reducedMotion: false))
    XCTAssertFalse(store.snapshot.sound)
    XCTAssertEqual(SettingsStore(defaults: defaults).snapshot.revision, 1)
  }
  func testFirstLaunchAllowsTutorialWithoutWatch() {
    let store = SettingsStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
    XCTAssertFalse(store.tutorialCompleted)
    store.completeTutorial()
    XCTAssertTrue(store.tutorialCompleted)
  }
}
