import Foundation
import Observation
import WristMagicCore

@MainActor @Observable final class SettingsStore {
  private(set) var snapshot: SettingsPayload
  private(set) var tutorialCompleted: Bool
  private let defaults: UserDefaults
  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    snapshot = defaults.data(forKey: "preferences").flatMap { try? JSONDecoder().decode(SettingsPayload.self, from: $0) } ?? SettingsPayload(revision: 0, sound: true, haptics: true, reducedMotion: false)
    tutorialCompleted = defaults.bool(forKey: "tutorialCompleted")
  }
  func update(sound: Bool, haptic: Bool, reduceMotion: Bool) {
    apply(SettingsPayload(revision: snapshot.revision + 1, sound: sound, haptics: haptic, reducedMotion: reduceMotion))
  }
  func apply(_ value: SettingsPayload) {
    guard value.revision > snapshot.revision else { return }
    snapshot = value
    defaults.set(try? JSONEncoder().encode(value), forKey: "preferences")
  }
  func completeTutorial() { tutorialCompleted = true; defaults.set(true, forKey: "tutorialCompleted") }
}
