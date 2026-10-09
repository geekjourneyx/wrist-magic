import XCTest
import ARKit
@testable import WristMagiciOS
import WristMagicCore

@MainActor final class ShowOffFlowTests: XCTestCase {
  func testCountdownDoesNotEmitEffectOrPermit() {
    let authority = SessionCoordinator()
    authority.foreground = true; authority.trackingNormal = true
    XCTAssertFalse(authority.isReady)
    XCTAssertNil(authority.grantIfReady(now: 3))
  }
  func testCameraMoveInvalidatesFixedComposition() {
    var gate = CameraMovementGate()
    XCTAssertFalse(gate.update(distance: 0.16, angle: 0, now: 1))
    XCTAssertFalse(gate.update(distance: 0.16, angle: 0, now: 1.2))
    XCTAssertTrue(gate.update(distance: 0.16, angle: 0, now: 1.31))
    gate.reset()
    XCTAssertFalse(gate.update(distance: 0, angle: 11, now: 2))
    XCTAssertTrue(gate.update(distance: 0, angle: 11, now: 2.31))
  }
}

@MainActor private final class FlowRenderer: FrameRendering {
  var complete: (@MainActor (Result<CVPixelBuffer, Error>) -> Void)?
  func submit(image: CVPixelBuffer, displayTransform: CGAffineTransform, viewProjection: simd_float4x4, time: Double, effects: [EffectCue], completion: @escaping @MainActor (Result<CVPixelBuffer, Error>) -> Void) throws -> Bool {
    complete = completion; return true
  }
}
@MainActor private final class FlowWriter: ClipWriting {
  var state: ClipWriter.State = .idle
  var ready = true
  func start(at time: CMTime) throws { state = .writing }
  func append(buffer: CVPixelBuffer, pts: CMTime) throws -> Bool { true }
  func finish() async throws -> URL { throw MediaError.invalidState }
  func cancel() { state = .cancelled }
}
extension ShowOffFlowTests {
  private func message<T: Encodable>(_ kind: WireKind, _ payload: T, session: UUID, sequence: UInt64) throws -> WireEnvelope {
    WireEnvelope(eventID: UUID(), sessionID: session, sequence: sequence, kind: kind, payload: try JSONEncoder().encode(payload))
  }
  func testPermitOnlyAfterFirstRecordedFrameAndFullCountdown() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let authority = SessionCoordinator(); authority.foreground = true; authority.trackingNormal = true
    let session = UUID()
    _ = authority.receive(try message(.hello, HelloPayload(appVersion: "test", requestedMode: .showOff), session: session, sequence: 1), now: 100)
    _ = authority.receive(try message(.armRequest, ArmRequestPayload(spell: .fireball, charge: 1), session: session, sequence: 2), now: 100)
    let renderer = FlowRenderer(); let writer = FlowWriter()
    let pipeline = RenderCapturePipeline(renderer: renderer, makeWriter: { _ in writer })
    var clock = 100.0
    var waits = 0
    var grants = 0
    authority.onPushGrant = { _ in grants += 1 }
    let capture = CaptureCoordinator(authority: authority, pipeline: pipeline, store: try ClipStore(directory: directory), settings: SettingsStore(defaults: UserDefaults(suiteName: UUID().uuidString)!), now: { clock }, sleep: { _ in
      XCTAssertEqual(grants, 0); XCTAssertNil(authority.captureFirstFrame)
      waits += 1; clock += 1
    })
    capture.prepare(side: .left)
    await capture.beginCountdown()
    XCTAssertEqual(waits, 3); XCTAssertEqual(clock, 103)
    XCTAssertEqual(capture.state, .recording); XCTAssertEqual(grants, 0)
    var buffer: CVPixelBuffer?
    XCTAssertEqual(CVPixelBufferCreate(nil, 720, 1280, kCVPixelFormatType_32BGRA, nil, &buffer), kCVReturnSuccess)
    let image = try XCTUnwrap(buffer)
    pipeline.consume(image: image, displayTransform: .identity, viewProjection: matrix_identity_float4x4, timestamp: 20, receiverUptime: 103)
    XCTAssertEqual(grants, 0)
    renderer.complete?(.success(image))
    XCTAssertEqual(grants, 1); XCTAssertEqual(authority.captureFirstFrame, 103)
    XCTAssertTrue(capture.acceptCast()); XCTAssertFalse(capture.acceptCast())
    capture.cancel(); XCTAssertNil(authority.sessionID); XCTAssertEqual(writer.state, .cancelled)
  }
  func testLateCastRejectedAt4Point5() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let authority = SessionCoordinator(); authority.foreground = true; authority.trackingNormal = true
    let session = UUID()
    _ = authority.receive(try message(.hello, HelloPayload(appVersion: "test", requestedMode: .showOff), session: session, sequence: 1), now: 0)
    _ = authority.receive(try message(.armRequest, ArmRequestPayload(spell: .fireball, charge: 1), session: session, sequence: 2), now: 0)
    let pipeline = RenderCapturePipeline(renderer: FlowRenderer(), makeWriter: { _ in FlowWriter() })
    var clock = 0.0
    let capture = CaptureCoordinator(authority: authority, pipeline: pipeline, store: try ClipStore(directory: directory), settings: SettingsStore(defaults: UserDefaults(suiteName: UUID().uuidString)!), now: { clock }, sleep: { _ in })
    capture.prepare(side: .right); await capture.beginCountdown()
    authority.captureDidStart(firstFrame: 0, cutoff: 4.5, now: 0)
    clock = 4.5
    XCTAssertFalse(capture.acceptCast()); XCTAssertFalse(capture.castAccepted)
    capture.cancel()
  }
}
