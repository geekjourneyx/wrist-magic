import Photos
import Observation

@MainActor @Observable final class PhotoSaver {
  private(set) var saving = false
  private(set) var saved: Set<URL> = []
  func save(url: URL) async throws {
    guard !saving, !saved.contains(url) else { return }
    saving = true; defer { saving = false }
    guard await PermissionCoordinator.requestPhotoAdd() else { throw PhotoSaveError.denied }
    try await PHPhotoLibrary.shared().performChanges {
      PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
    }
    saved.insert(url)
  }
}
enum PhotoSaveError: Error { case denied }
