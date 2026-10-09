import ARKit
@preconcurrency import AVFoundation

@MainActor protocol ARSessionDriving: AnyObject {
  var delegate: (any ARSessionDelegate)? { get set }
  var delegateQueue: DispatchQueue? { get set }
  var currentFrame: ARFrame? { get }
  func run(_ configuration: ARConfiguration, options: ARSession.RunOptions)
  func pause()
}
extension ARSession: ARSessionDriving {}

/// Sole owner of the rear camera. UI must request permission before start().
@MainActor final class ARFrameSource: NSObject, ARSessionDelegate {
  let session: any ARSessionDriving
  var onFrame: ((ARFrame) -> Void)?
  var onTracking: ((Bool) -> Void)?
  var onInterruption: ((Error?) -> Void)?
  private(set) var running = false
  static var supported: Bool { ARWorldTrackingConfiguration.isSupported }
  init(session: any ARSessionDriving = ARSession()) { self.session = session; super.init(); session.delegate = self; session.delegateQueue = .main }
  static func requestPermission() async -> Bool { await AVCaptureDevice.requestAccess(for: .video) }
  func start() throws {
    guard Self.supported else { throw MediaError.unsupported }
    guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { throw MediaError.invalidState }
    let config = ARWorldTrackingConfiguration(); config.worldAlignment = .gravity
    session.run(config, options: [.resetTracking, .removeExistingAnchors]); running = true
    onTracking?(false)
  }
  func stop() { running = false; session.pause(); onTracking?(false) }
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
