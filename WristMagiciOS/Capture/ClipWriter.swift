@preconcurrency import AVFoundation

/// All writer calls are serialized by the main actor. No application frame queue is retained.
enum MediaError: Error { case invalidState, invalidPTS, writerFailed, pixelBuffer, invalidClip, unsupported, tracking, casting, gpu, storage, audio }
@MainActor final class ClipWriter: ClipWriting {
  enum State { case idle, writing, finishing, finished, failed, cancelled }
  private(set) var state: State = .idle
  let url: URL
  private let writer: AVAssetWriter
  private let input: AVAssetWriterInput
  private let adaptor: AVAssetWriterInputPixelBufferAdaptor
  private var sessionStart: CMTime?
  private var lastPTS: CMTime?
  private var result: Result<URL, Error>?
  private var finishTask: Task<URL, Error>?
  nonisolated static func temporaryURL(in directory: URL = FileManager.default.temporaryDirectory) -> URL {
    directory.appendingPathComponent("\(UUID()).partial.mp4")
  }
  init(url: URL) throws {
    // AVURLAsset format discovery uses the final path extension even for completed MP4 bytes.
    // Keep the incomplete marker in the basename while preserving the actual media extension.
    let outputURL = url.pathExtension.lowercased() == "mp4" ? url : url.appendingPathExtension("mp4")
    self.url = outputURL
    writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
    input = AVAssetWriterInput(mediaType: .video, outputSettings: [
      AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 720, AVVideoHeightKey: 1280,
      AVVideoColorPropertiesKey: [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
        AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2, AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2],
      AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 5_000_000, AVVideoExpectedSourceFrameRateKey: 30, AVVideoMaxKeyFrameIntervalKey: 30]])
    input.expectsMediaDataInRealTime = true
    adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
      kCVPixelBufferWidthKey as String: 720, kCVPixelBufferHeightKey as String: 1280,
      kCVPixelBufferMetalCompatibilityKey as String: true])
    guard writer.canAdd(input) else { throw MediaError.writerFailed }
    writer.add(input)
  }
  var ready: Bool { state == .writing && input.isReadyForMoreMediaData }
  func start(at time: CMTime) throws {
    guard state == .idle, time.isNumeric else { throw MediaError.invalidState }
    guard writer.startWriting() else { state = .failed; throw writer.error ?? MediaError.writerFailed }
    writer.startSession(atSourceTime: time); sessionStart = time; state = .writing
  }
  @discardableResult func append(buffer: CVPixelBuffer, pts: CMTime) throws -> Bool {
    guard state == .writing else { throw MediaError.invalidState }
    guard pts.isNumeric, pts >= (sessionStart ?? .zero), lastPTS == nil || pts > lastPTS! else { throw MediaError.invalidPTS }
    guard writer.status == .writing else { state = .failed; throw writer.error ?? MediaError.writerFailed }
    guard input.isReadyForMoreMediaData else { return false }
    guard adaptor.append(buffer, withPresentationTime: pts) else { state = .failed; throw writer.error ?? MediaError.writerFailed }
    lastPTS = pts; return true
  }
  func finish() async throws -> URL {
    if let result { return try result.get() }
    if let finishTask { return try await finishTask.value }
    guard state == .writing, let lastPTS else { throw MediaError.invalidState }
    state = .finishing
    // One real frame interval ends the last sample; never append a duplicate frame or PTS.
    writer.endSession(atSourceTime: lastPTS + CMTime(value: 1, timescale: 30))
    input.markAsFinished()
    let task = Task { @MainActor [self] () throws -> URL in
      await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        self.writer.finishWriting { continuation.resume() }
      }
      guard self.writer.status == .completed, self.state != .cancelled else {
        let error = self.writer.error ?? MediaError.writerFailed
        self.state = .failed; self.result = .failure(error); throw error
      }
      self.state = .finished; self.result = .success(self.url); return self.url
    }
    finishTask = task
    return try await task.value
  }
  func cancel() {
    guard state != .finished, state != .cancelled else { return }
    state = .cancelled; result = .failure(CancellationError())
    writer.cancelWriting(); try? FileManager.default.removeItem(at: url)
  }
}
