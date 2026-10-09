import Foundation

public struct EffectCue: Sendable {
  public let eventID: UUID
  public let spell: SpellID
  public let start: Double
  public let duration: Double
  public let seed: UInt64
  public let origin: SIMD3<Float>
  public let direction: SIMD3<Float>
  public init(
    eventID: UUID, spell: SpellID, start: Double, duration: Double = 1.5, seed: UInt64,
    origin: SIMD3<Float>, direction: SIMD3<Float>
  ) {
    self.eventID = eventID
    self.spell = spell
    self.start = start
    self.duration = duration
    self.seed = seed
    self.origin = origin
    self.direction = direction
  }
}
/// Four 16-byte lanes; Metal counterpart must use float4 for all lanes (64 bytes).
@frozen public struct EffectParameters: Sendable, Equatable {
  public var originAndProgress: SIMD4<Float>
  public var directionAndOpacity: SIMD4<Float>
  public var colorAndFlash: SIMD4<Float>
  public var shape: SIMD4<Float>
  public init(
    originAndProgress: SIMD4<Float>, directionAndOpacity: SIMD4<Float>, colorAndFlash: SIMD4<Float>,
    shape: SIMD4<Float>
  ) {
    self.originAndProgress = originAndProgress
    self.directionAndOpacity = directionAndOpacity
    self.colorAndFlash = colorAndFlash
    self.shape = shape
  }
  public static let inactive = Self(
    originAndProgress: .zero, directionAndOpacity: .zero, colorAndFlash: .zero, shape: .zero)
  public var isActive: Bool { directionAndOpacity.w > 0 }
}
public enum EffectTimeline {
  public static func evaluate(_ cue: EffectCue, at time: Double, reducedMotion: Bool)
    -> EffectParameters
  {
    let age = time - cue.start
    let duration = min(cue.duration, 1.5)
    guard time.isFinite, cue.start.isFinite, duration.isFinite, duration > 0, age >= 0,
      age < duration,
      [cue.origin.x, cue.origin.y, cue.origin.z, cue.direction.x, cue.direction.y, cue.direction.z]
        .allSatisfy(\.isFinite)
    else { return .inactive }
    let p = Float(age / duration)
    let tail = Float(min(1, max(0, (duration - age) / 0.3)))
    let color: SIMD3<Float>
    let kind: Float
    switch cue.spell {
    case .fireball:
      color = SIMD3(1, 0.32, 0.06)
      kind = 0
    case .lightning:
      color = SIMD3(0.35, 0.65, 1)
      kind = 1
    case .forcePush:
      color = SIMD3(0.8, 0.85, 0.9)
      kind = 2
    }
    let flash: Float =
      reducedMotion || cue.spell != .lightning ? 0 : Float(max(0, 1 - age / 0.12)) * 0.35
    let noise = Float((cue.seed ^ (cue.seed >> 32)) & 0xFFFFFF) / Float(0xFFFFFF)
    return .init(
      originAndProgress: SIMD4(cue.origin.x, cue.origin.y, cue.origin.z, p),
      directionAndOpacity: SIMD4(cue.direction.x, cue.direction.y, cue.direction.z, tail),
      colorAndFlash: SIMD4(color.x, color.y, color.z, flash),
      shape: SIMD4(kind, noise, reducedMotion ? 0.25 : 1, p * 1.2))
  }
}
