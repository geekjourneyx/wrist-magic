import Photos
import Observation

@MainActor @Observable final class PhotoSaver {
  private(set) var saving = false
  private let defaults: UserDefaults
  private var savedNames: Set<String>
  private let permission: () async -> Bool
  private let write: (URL) async throws -> Void
  init(defaults: UserDefaults = .standard,
       permission: @escaping () async -> Bool = { await PermissionCoordinator.requestPhotoAdd() },
       write: @escaping (URL) async throws -> Void = { url in
         try await PHPhotoLibrary.shared().performChanges { @Sendable in
           PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
         }
       }) {
    self.defaults = defaults; self.permission = permission; self.write = write
    savedNames = Set(defaults.stringArray(forKey: "savedClipNames") ?? [])
  }
  func isSaved(_ url: URL) -> Bool { savedNames.contains(url.lastPathComponent) }
  func save(url: URL) async throws {
    guard !saving, !isSaved(url) else { return }
    saving = true; defer { saving = false }
    guard await permission() else { throw PhotoSaveError.denied }
    try await write(url)
    savedNames.insert(url.lastPathComponent)
    defaults.set(Array(savedNames), forKey: "savedClipNames")
  }
}
enum PhotoSaveError: Error { case denied }
