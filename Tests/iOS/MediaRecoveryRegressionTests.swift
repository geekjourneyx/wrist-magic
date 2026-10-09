import XCTest
import ARKit
import WristMagicCore
@testable import WristMagiciOS

@MainActor private final class DelayedRenderer: FrameRendering {
  var completions: [@MainActor (Result<CVPixelBuffer,Error>) -> Void] = []
  func submit(image:CVPixelBuffer,displayTransform:CGAffineTransform,viewProjection:simd_float4x4,time:Double,effects:[EffectCue],completion:@escaping @MainActor (Result<CVPixelBuffer,Error>)->Void) throws -> Bool {
    completions.append(completion); return true
  }
  func complete(_ buffer:CVPixelBuffer) { completions.removeFirst()(.success(buffer)) }
}
@MainActor private final class InitiallyBackpressuredWriter: ClipWriting {
  var state:ClipWriter.State = .idle
  var ready = true
  var starts = 0
  var attempts = 0
  func start(at:CMTime) throws {
    guard state == .idle else { throw MediaError.invalidState }
    starts += 1; state = .writing
  }
  func append(buffer:CVPixelBuffer,pts:CMTime) throws -> Bool { attempts += 1; return attempts > 1 }
  func finish() async throws -> URL { throw MediaError.invalidState }
  func cancel() { state = .cancelled }
}
@MainActor private final class SessionDriver: ARSessionDriving {
  weak var delegate: (any ARSessionDelegate)?
  var delegateQueue: DispatchQueue?
  var currentFrame: ARFrame? { nil }
  var pauses = 0
  func run(_ configuration:ARConfiguration,options:ARSession.RunOptions) {}
  func pause() { pauses += 1 }
}
final class MediaRecoveryRegressionTests: XCTestCase {
  @MainActor func testFirstAppendBackpressureRetriesWithoutRestartAndKeepsFrameClockPair() throws {
    let renderer = DelayedRenderer(); let writer = InitiallyBackpressuredWriter()
    let pipeline = RenderCapturePipeline(renderer:renderer,makeWriter:{_ in writer})
    try pipeline.prepare(url:FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    var events: [(Double,Double)] = []
    var errors = 0
    pipeline.onError = {_ in errors += 1}
    pipeline.onFirstFrame = {events.append(($0,$1))}
    var buffer:CVPixelBuffer?
    XCTAssertEqual(CVPixelBufferCreate(nil,720,1280,kCVPixelFormatType_32BGRA,nil,&buffer),kCVReturnSuccess)
    let image = buffer!
    pipeline.consume(image:image,displayTransform:.identity,viewProjection:matrix_identity_float4x4,timestamp:10,receiverUptime:100)
    XCTAssertNil(pipeline.firstFrameTime); XCTAssertTrue(events.isEmpty)
    renderer.complete(image)
    XCTAssertNil(pipeline.firstFrameTime); XCTAssertTrue(events.isEmpty)
    pipeline.consume(image:image,displayTransform:.identity,viewProjection:matrix_identity_float4x4,timestamp:10.1,receiverUptime:100.1)
    // Completion is deliberately controlled after ingress; it must not sample the current clock.
    renderer.complete(image)
    XCTAssertEqual(writer.starts,1); XCTAssertEqual(writer.attempts,2); XCTAssertEqual(errors,0)
    XCTAssertEqual(pipeline.firstFrameTime,10.1)
    XCTAssertEqual(events.count,1)
    XCTAssertEqual(events.first?.0,10.1); XCTAssertEqual(events.first?.1,100.1)
    pipeline.cancel()
  }
  @MainActor func testInterruptedSessionStillPausesOnExplicitStop() {
    let driver = SessionDriver(); let source = ARFrameSource(session:driver)
    var interruptions = 0
    source.onInterruption = {_ in interruptions += 1}
    source.sessionWasInterrupted(ARSession())
    XCTAssertFalse(source.running)
    source.stop(); XCTAssertEqual(driver.pauses,1)
    source.stop(); XCTAssertEqual(driver.pauses,2)
    XCTAssertEqual(interruptions,1)
  }
  @MainActor func testRelocatedContainerAndLegacyAbsoluteIndexRecoverWithoutDeletingClip() throws {
    let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let old = parent.appendingPathComponent("old/Clips"); let relocated = parent.appendingPathComponent("new/Clips")
    defer {try? FileManager.default.removeItem(at:parent)}
    try FileManager.default.createDirectory(at:old,withIntermediateDirectories:true)
    let id = UUID(); let file = old.appendingPathComponent("\(id).mp4")
    try Data([1,2,3]).write(to:file)
    let legacy = ClipRecord(id:id,url:file,createdAt:Date(),duration:2,interrupted:true,reviewed:false)
    try JSONEncoder().encode([legacy]).write(to:old.appendingPathComponent("index.json"))
    try FileManager.default.createDirectory(at:relocated.deletingLastPathComponent(),withIntermediateDirectories:true)
    try FileManager.default.moveItem(at:old,to:relocated)
    let migrated = try ClipStore(directory:relocated)
    XCTAssertEqual(migrated.latestRecoverable()?.id,id)
    XCTAssertEqual(migrated.latestRecoverable()?.url,relocated.appendingPathComponent("\(id).mp4"))
    XCTAssertTrue(FileManager.default.fileExists(atPath:relocated.appendingPathComponent("\(id).mp4").path))
    let json = String(decoding:try Data(contentsOf:relocated.appendingPathComponent("index.json")),as:UTF8.self)
    XCTAssertFalse(json.contains(old.path)); XCTAssertTrue(json.contains("filename"))
    let final = parent.appendingPathComponent("final/Clips")
    try FileManager.default.createDirectory(at:final.deletingLastPathComponent(),withIntermediateDirectories:true)
    try FileManager.default.moveItem(at:relocated,to:final)
    let reopened = try ClipStore(directory:final)
    XCTAssertEqual(reopened.latestRecoverable()?.url,final.appendingPathComponent("\(id).mp4"))
    XCTAssertEqual(reopened.latestRecoverable()?.id,id)
  }
}
