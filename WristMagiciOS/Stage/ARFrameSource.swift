import ARKit
@preconcurrency import AVFoundation

/// Sole owner of the rear camera. UI must request permission before start().
@MainActor final class ARFrameSource: NSObject, ARSessionDelegate {
  let session = ARSession()
  var onFrame: ((ARFrame) -> Void)?
  var onTracking: ((Bool) -> Void)?
  var onInterruption: ((Error?) -> Void)?
  private(set) var running = false
  static var supported: Bool { ARWorldTrackingConfiguration.isSupported }
  override init() { super.init(); session.delegate = self; session.delegateQueue = .main }
  static func requestPermission() async -> Bool { await AVCaptureDevice.requestAccess(for: .video) }
  func start() throws {
    guard Self.supported else { throw MediaError.unsupported }
    guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { throw MediaError.invalidState }
    let config = ARWorldTrackingConfiguration(); config.worldAlignment = .gravity
    session.run(config, options: [.resetTracking, .removeExistingAnchors]); running = true
    onTracking?(false)
  }
  func stop() { guard running else { return }; running = false; session.pause(); onTracking?(false) }
  nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
    MainActor.assumeIsolated {
      guard self.running else { return }
      if case .normal = frame.camera.trackingState { self.onTracking?(true) } else { self.onTracking?(false) }
      self.onFrame?(frame)
    }
  }
  nonisolated func sessionWasInterrupted(_ session: ARSession) {
    MainActor.assumeIsolated { self.running = false; self.onTracking?(false); self.onInterruption?(nil) }
  }
  nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
    MainActor.assumeIsolated { self.running = false; self.onTracking?(false); self.onInterruption?(error) }
  }
}
