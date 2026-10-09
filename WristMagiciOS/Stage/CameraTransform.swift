import ARKit
import simd

enum CameraTransform {
  static let outputSize = CGSize(width: 720, height: 1280)
  static func imageUV(displayUV: CGPoint, displayTransform: CGAffineTransform) -> CGPoint {
    displayUV.applying(displayTransform.inverted())
  }
  static func inverseDisplay(_ transform: CGAffineTransform) -> simd_float3x3 {
    let t = transform.inverted()
    return simd_float3x3(SIMD3(Float(t.a), Float(t.b), 0), SIMD3(Float(t.c), Float(t.d), 0), SIMD3(Float(t.tx), Float(t.ty), 1))
  }
  static func viewProjection(_ camera: ARCamera) -> simd_float4x4 {
    camera.projectionMatrix(for: .portrait, viewportSize: outputSize, zNear: 0.01, zFar: 100)
      * camera.viewMatrix(for: .portrait)
  }
}
