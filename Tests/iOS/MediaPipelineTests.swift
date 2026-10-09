import XCTest
import AVFoundation
import MetalKit
import WristMagicCore
@testable import WristMagiciOS

final class MediaPipelineTests: XCTestCase {
  @MainActor func testPortraitCropMapsKnownCorners() {
    let uv = CameraTransform.imageUV(displayUV: CGPoint(x: 0.25, y: 0.75), displayTransform: CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 1, ty: 0))
    XCTAssertEqual(uv.x, 0.75, accuracy: 0.0001)
    XCTAssertEqual(uv.y, 0.75, accuracy: 0.0001)
  }
  @MainActor func testLimitedTrackingRejectsNewCastAndFixedAnchor() throws {
    let stage = EffectStage()
    XCTAssertThrowsError(try stage.place(cameraTransform: matrix_identity_float4x4, mode: .reality, side: .left))
    stage.trackingNormal = true
    try stage.place(cameraTransform: matrix_identity_float4x4, mode: .reality, side: .left)
    let original = stage.origin
    XCTAssertEqual(original.z, -1.5, accuracy: 0.0001)
    stage.casting = true
    var moved = matrix_identity_float4x4; moved.columns.3.x = 1
    XCTAssertThrowsError(try stage.place(cameraTransform: moved, mode: .reality, side: .right))
    XCTAssertEqual(stage.origin, original)
  }
  @MainActor func testPTSStrictlyIncreasesAndGeneratedVideoDecodes() async throws {
    let writer = try ClipWriter(url: Self.temp("writer"))
    let pixel = try Self.pixel()
    try writer.start(at: .zero)
    XCTAssertTrue(try writer.append(buffer: pixel, pts: .zero))
    XCTAssertThrowsError(try writer.append(buffer: pixel, pts: .zero))
    for i in 1..<60 {
      let pts = CMTime(value: Int64(i), timescale: 30)
      while !(try writer.append(buffer: pixel, pts: pts)) { await Task.yield() }
    }
    let url = try await writer.finish()
    XCTAssertEqual(try await writer.finish(), url)
    let report = try await ClipValidator.validate(url: url, expectedDuration: 2, requiresAudio: false)
    XCTAssertEqual(report.width, 720); XCTAssertEqual(report.height, 1280)
    XCTAssertFalse(report.hasAudio)
    try? FileManager.default.removeItem(at: url)
  }
  @MainActor func testWriterFailureNeverReturnsSuccessURL() async throws {
    let writer = try ClipWriter(url: Self.temp("cancel"))
    writer.cancel(); writer.cancel()
    do { _ = try await writer.finish(); XCTFail("Cancelled writer succeeded") } catch {}
  }
  @MainActor func testShareLeasePreventsPruneAndRecoveryUsesRealFiles() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try ClipStore(directory: root)
    let source = Self.temp("store"); try Data([1,2,3]).write(to: source)
    let record = try store.commit(tempURL: source, report: ClipReport(width: 720, height: 1280, duration: 2, hasAudio: false), interrupted: true)
    XCTAssertEqual(try ClipStore(directory: root).latestRecoverable()?.id, record.id)
    try store.acquire(record.id)
    try store.prune(now: Date().addingTimeInterval(8 * 86400))
    XCTAssertTrue(FileManager.default.fileExists(atPath: record.url.path))
    store.release(record.id)
    try store.prune(now: Date().addingTimeInterval(8 * 86400))
    XCTAssertFalse(FileManager.default.fileExists(atPath: record.url.path))
  }
  @MainActor func testInvalidClipNeverCommittedAndPartialCleaned() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let partial = root.appendingPathComponent("dead.partial"); try Data([0]).write(to: partial)
    let store = try ClipStore(directory: root)
    XCTAssertFalse(FileManager.default.fileExists(atPath: partial.path))
    let source = Self.temp("invalid"); try Data([0]).write(to: source)
    XCTAssertThrowsError(try store.commit(tempURL: source, report: ClipReport(width: 1, height: 1, duration: 0, hasAudio: false)))
    XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    try? FileManager.default.removeItem(at: source)
  }
  @MainActor private static func pixel() throws -> CVPixelBuffer {
    var result: CVPixelBuffer?
    let status = CVPixelBufferCreate(nil, 720, 1280, kCVPixelFormatType_32BGRA, [kCVPixelBufferMetalCompatibilityKey: true] as CFDictionary, &result)
    guard status == kCVReturnSuccess, let result else { throw MediaError.pixelBuffer }
    CVPixelBufferLockBaseAddress(result, [])
    memset(CVPixelBufferGetBaseAddress(result), 80, CVPixelBufferGetDataSize(result))
    CVPixelBufferUnlockBaseAddress(result, [])
    return result
  }
  private static func temp(_ name: String) -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(UUID()).partial") }
}

extension MediaPipelineTests {
  @MainActor func testCuePlacedAtVideoTimeWithin80MillisecondsAndMute() throws {
    let cue = EffectCue(eventID:UUID(),spell:.lightning,start:0.4,seed:7,origin:.zero,direction:SIMD3(0,0,-1))
    let samples = try ClipAudioMixer.renderedSamples(cues:[cue],duration:2)
    let onset = samples.firstIndex(where:{ abs($0) > 0.005 })!
    XCTAssertEqual(Double(onset)/48000,0.4,accuracy:0.08)
    XCTAssertTrue(samples.prefix(19200).allSatisfy {$0 == 0})
    XCTAssertLessThanOrEqual(samples.map{abs($0)}.max()!,0.95)
  }
  @MainActor func testSharedGPUFrameHasDistinctSpellPixelsAndBoundedBuffers() async throws {
    guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("Metal unavailable on this simulator") }
    let renderer = try StageRenderer()
    let camera = try Self.pixel()
    let projection = simd_float4x4(SIMD4(1,0,0,0),SIMD4(0,1,0,0),SIMD4(0,0,1,0),SIMD4(0,0,0,1))
    func render(_ spell: SpellID) async throws -> Data {
      let cue = EffectCue(eventID:UUID(),spell:spell,start:0,seed:7,origin:SIMD3(0,0,0),direction:SIMD3(0.4,0,0))
      let buffer: CVPixelBuffer = try await withCheckedThrowingContinuation { continuation in
        do {
          let accepted = try renderer.submit(image:camera,displayTransform:.identity,viewProjection:projection,time:0.3,effects:[cue]) { continuation.resume(with:$0) }
          if !accepted { continuation.resume(throwing:MediaError.gpu) }
        } catch { continuation.resume(throwing:error) }
      }
      XCTAssertEqual(renderer.framesInFlight,0)
      CVPixelBufferLockBaseAddress(buffer,.readOnly); defer { CVPixelBufferUnlockBaseAddress(buffer,.readOnly) }
      return Data(bytes:CVPixelBufferGetBaseAddress(buffer)!,count:CVPixelBufferGetDataSize(buffer))
    }
    let fire = try await render(.fireball); let lightning = try await render(.lightning); let push = try await render(.forcePush)
    XCTAssertNotEqual(fire,lightning); XCTAssertNotEqual(fire,push); XCTAssertNotEqual(lightning,push)
    var accepted = 0
    for _ in 0..<12 {
      if try renderer.submit(image:camera,displayTransform:.identity,viewProjection:projection,time:0,effects:[],completion:{_ in}) { accepted += 1 }
    }
    XCTAssertEqual(accepted,3); XCTAssertEqual(renderer.framesInFlight,3)
  }
  @MainActor func testAudioFailureKeepsSourceAndMuteHasNoTrack() async throws {
    let writer = try ClipWriter(url:Self.temp("audio")); let pixel = try Self.pixel()
    try writer.start(at:.zero)
    for i in 0..<60 {
      while !(try writer.append(buffer:pixel,pts:CMTime(value:Int64(i),timescale:30))) { await Task.yield() }
    }
    let video = try await writer.finish(); defer { try? FileManager.default.removeItem(at:video) }
    let cue = EffectCue(eventID:UUID(),spell:.fireball,start:0.4,seed:1,origin:.zero,direction:.zero)
    let muted = try await ClipAudioMixer.mix(video:video,cues:[cue],soundEnabled:false)
    XCTAssertEqual(muted,video)
    _ = try await ClipValidator.validate(url:muted,expectedDuration:2,requiresAudio:false)
    let mixed = try await ClipAudioMixer.mix(video:video,cues:[cue],soundEnabled:true)
    defer { try? FileManager.default.removeItem(at:mixed) }
    _ = try await ClipValidator.validate(url:mixed,expectedDuration:2,requiresAudio:true)
    let broken = EffectCue(eventID:UUID(),spell:.fireball,start:-1,seed:1,origin:.zero,direction:.zero)
    do { _ = try await ClipAudioMixer.mix(video:video,cues:[broken],soundEnabled:true); XCTFail("Expected failure") } catch {}
    XCTAssertTrue(FileManager.default.fileExists(atPath:video.path))
  }
}
