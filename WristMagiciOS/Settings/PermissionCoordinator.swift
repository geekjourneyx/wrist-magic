@preconcurrency import AVFoundation
import Photos

enum PermissionStatus { case authorized, notDetermined, denied, restricted }
@MainActor enum PermissionCoordinator {
  static func cameraStatus() -> PermissionStatus {
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized: .authorized
    case .notDetermined: .notDetermined
    case .denied: .denied
    default: .restricted
    }
  }
  static func requestCamera() async -> Bool {
    if cameraStatus() == .authorized { return true }
    return await AVCaptureDevice.requestAccess(for: .video)
  }
  static func requestPhotoAdd() async -> Bool {
    let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
    return status == .authorized || status == .limited
  }
}
