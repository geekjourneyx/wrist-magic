import Foundation

public struct CastState: Equatable, Sendable {
  public var spell: SpellID
  public var phase: CastPhase
  public var charge: Double
  public init(spell: SpellID = .fireball, phase: CastPhase = .selecting, charge: Double = 0) {
    self.spell = spell
    self.phase = phase
    self.charge = charge
  }
}
public enum CastAction: Sendable {
  case select(SpellID)
  case prepare
  case crown(Double)
  case armed, trigger, timeout, pause, resume, reset
}
