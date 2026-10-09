import AVFoundation

struct ClipReport: Codable, Sendable {
  let width: Int
  let height: Int
  let duration: Double
  let hasAudio: Bool
  var valid: Bool { width == 720 && height == 1280 && duration.isFinite && duration >= 2 && duration <= 6.15 }
}
enum ClipValidator {
  static func validate(url: URL, expectedDuration: Double? = nil, requiresAudio: Bool) async throws -> ClipReport {
    let asset = AVURLAsset(url: url)
    let tracks = try await asset.loadTracks(withMediaType: .video)
    guard let video = tracks.first else { throw MediaError.invalidClip }
    let size = try await video.load(.naturalSize)
    let transform = try await video.load(.preferredTransform)
    let transformed = CGRect(origin: .zero, size: size).applying(transform)
    let duration = try await asset.load(.duration).seconds
    let audio = try await asset.loadTracks(withMediaType: .audio)
    let report = ClipReport(width: Int(abs(transformed.width)), height: Int(abs(transformed.height)), duration: duration, hasAudio: !audio.isEmpty)
    guard report.valid, report.hasAudio == requiresAudio,
      expectedDuration.map({ abs(duration - $0) <= 0.15 }) ?? true else { throw MediaError.invalidClip }
    // Decode every sample; metadata alone cannot prove that a partial file is playable.
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(track: video, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
    output.alwaysCopiesSampleData = false
    guard reader.canAdd(output) else { throw MediaError.invalidClip }; reader.add(output)
    guard reader.startReading() else { throw reader.error ?? MediaError.invalidClip }
    var samples = 0; var last = CMTime.invalid
    while let sample = output.copyNextSampleBuffer() {
      let pts = CMSampleBufferGetPresentationTimeStamp(sample)
      guard CMSampleBufferGetImageBuffer(sample) != nil, pts.isNumeric, !last.isNumeric || pts > last else {
        reader.cancelReading(); throw MediaError.invalidClip
      }
      last = pts; samples += 1
    }
    guard reader.status == .completed, samples >= 2, last.seconds >= duration - 0.15 else { throw reader.error ?? MediaError.invalidClip }
    return report
  }
}
