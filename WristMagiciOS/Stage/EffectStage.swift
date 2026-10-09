import ARKit
import WristMagicCore

enum LaunchSide: String, CaseIterable { case left, right }
@MainActor final class EffectStage {
  var trackingNormal = false
  var casting = false
  private(set) var origin = SIMD3<Float>(0, 0, -1.5)
  private(set) var direction = SIMD3<Float>(0, 0, -1)
  private(set) var placed = false
  func place(cameraTransform: simd_float4x4, mode: PlayMode, side: LaunchSide) throws {
    guard trackingNormal else { throw MediaError.tracking }
    guard !casting else { throw MediaError.casting }
    let localX: Float = mode == .showOff ? (side == .left ? -0.28 : 0.28) : 0
    let p = cameraTransform * SIMD4<Float>(localX, mode == .showOff ? 0.1 : 0, -1.5, 1)
    origin = SIMD3(p.x, p.y, p.z)
    let forward = cameraTransform * SIMD4<Float>(0, 0, -1, 0)
    direction = simd_normalize(SIMD3(forward.x, forward.y, forward.z)); placed = true
  }
  /// Exact normalized Show Off ray placement uses the same portrait projection as rendering.
  func place(camera: ARCamera, mode: PlayMode, side: LaunchSide) throws {
    try place(cameraTransform: camera.transform, mode: mode, side: side)
    if mode == .showOff {
      let inverse = CameraTransform.viewProjection(camera).inverse
      let x: Float = side == .left ? 0.35 : 0.65
      var point = inverse * SIMD4<Float>(x * 2 - 1, 1 - 0.45 * 2, 1, 1)
      point /= point.w
      let c = camera.transform.columns.3
      let cameraPosition = SIMD3(c.x, c.y, c.z)
      origin = cameraPosition + simd_normalize(SIMD3(point.x, point.y, point.z) - cameraPosition) * 1.5
    }
  }
  func reset() { placed = false; casting = false; trackingNormal = false }
  func makeCue(cast: CastPayload, start: Double, seed: UInt64) throws -> EffectCue {
    guard placed, trackingNormal else { throw MediaError.tracking }
    return EffectCue(eventID: UUID(), spell: cast.permit.spell, start: start, seed: seed, origin: origin, direction: direction)
  }
  func makeCue(spell: SpellID, start: Double, seed: UInt64, eventID: UUID = UUID()) throws -> EffectCue {
    guard placed, trackingNormal else { throw MediaError.tracking }
    return EffectCue(eventID: eventID, spell: spell, start: start, seed: seed, origin: origin, direction: direction)
  }
}
