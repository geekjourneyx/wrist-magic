import Foundation
@preconcurrency import AVFoundation

@main struct ValidateClip {
  static func main() async throws {
    guard CommandLine.arguments.count >= 2 else { fatalError("Usage: verify-clip.sh <path> [duration]") }
    let url = URL(fileURLWithPath:CommandLine.arguments[1])
    let expected = CommandLine.arguments.count > 2 ? Double(CommandLine.arguments[2]) ?? 6 : 6
    let asset = AVURLAsset(url:url)
    guard let video = try await asset.loadTracks(withMediaType:.video).first else { fatalError("No video") }
    let size = try await video.load(.naturalSize)
    let transform = try await video.load(.preferredTransform)
    let rect = CGRect(origin:.zero,size:size).applying(transform)
    let duration = try await asset.load(.duration).seconds
    guard Int(abs(rect.width)) == 720, Int(abs(rect.height)) == 1280, abs(duration-expected) <= 0.15 else { fatalError("Invalid dimensions/duration: \(rect.size), \(duration)") }
    let reader = try AVAssetReader(asset:asset)
    let output = AVAssetReaderTrackOutput(track:video,outputSettings:[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA])
    reader.add(output); guard reader.startReading() else { throw reader.error! }
    var count = 0; var previous = CMTime.invalid
    while let sample = output.copyNextSampleBuffer() {
      let pts = CMSampleBufferGetPresentationTimeStamp(sample)
      guard CMSampleBufferGetImageBuffer(sample) != nil, !previous.isNumeric || pts > previous else { fatalError("Non-decoded or non-monotonic sample") }
      previous = pts; count += 1
    }
    guard reader.status == .completed, count >= 2, previous.seconds >= duration-0.15 else { fatalError("Decode failed or truncated tail") }
    let audio = try await asset.loadTracks(withMediaType:.audio)
    print("PASS 720x1280 \(duration)s, \(count) decoded monotonic frames, audio=\(!audio.isEmpty)")
    print("Visual direction/effect/UI exclusion and device performance still require physical review.")
  }
}
