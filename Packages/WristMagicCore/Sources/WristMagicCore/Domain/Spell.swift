import Foundation

public enum SpellID: String, Codable, Sendable, CaseIterable { case fireball, lightning, forcePush }
public enum PlayMode: String, Codable, Sendable { case practice, reality, showOff }
public enum CastPhase: String, Codable, Sendable {
  case selecting, charging, ready, fired, retry, paused
}
