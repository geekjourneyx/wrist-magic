import XCTest
import Metal
import WristMagicCore
@testable import WristMagiciOS

@MainActor private final class FlowPhoneLink: PhoneSessionLink {
  var available = true
  var onReceived: ((WireEnvelope) -> Void)?
  var onLinkChanged: ((Bool, String) -> Void)?
  var onSettings: ((SettingsPayload) -> Void)?
  var requests: [WireEnvelope] = []
  var receipt: Receipt = .accepted
  func setForeground(_ value: Bool) {}
  func publishSettings(_ value: SettingsPayload) throws {}
  func send(_ envelope: WireEnvelope) async throws -> WireEnvelope {
    requests.append(envelope)
    return WireEnvelope(eventID: UUID(), sessionID: envelope.sessionID, sequence: envelope.sequence, kind: .ack, payload: try JSONEncoder().encode(AckPayload(receipt: receipt, eventID: envelope.eventID)))
  }
  func cancelPending(sessionID: UUID) {}
}
@MainActor final class RecoveryFlowTests: XCTestCase {
  private func makeModel() throws -> (AppModel, FlowPhoneLink, URL) {
    guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("Simulator has no Metal device") }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let link = FlowPhoneLink()
    let model = try AppModel(settings: SettingsStore(defaults: UserDefaults(suiteName: UUID().uuidString)!), link: link, store: ClipStore(directory: directory), cameraPermission: { false })
    model.sceneActive(true)
    return (model, link, directory)
  }
  func testForegroundReturnDoesNotAutoResume() throws {
    let (model, _, directory) = try makeModel()
    defer { try? FileManager.default.removeItem(at: directory) }
    model.recover(.background); model.sceneActive(false); model.sceneActive(true)
    XCTAssertEqual(model.route, .recovery); XCTAssertNil(model.authority.sessionID)
    XCTAssertFalse(model.frames.running)
  }
  func testCameraDeniedStillAllowsWatchPractice() async throws {
    let (model, _, directory) = try makeModel()
    defer { try? FileManager.default.removeItem(at: directory) }
    let session = UUID()
    _ = model.authority.receive(WireEnvelope(eventID: UUID(), sessionID: session, sequence: 1, kind: .hello, payload: try JSONEncoder().encode(HelloPayload(appVersion: "test", requestedMode: .reality))), now: 0)
    await model.startStage()
    XCTAssertEqual(model.failure, .cameraDenied); XCTAssertEqual(model.route, .recovery)
    model.showTutorial(); XCTAssertEqual(model.route, .tutorial)
    XCTAssertFalse(model.frames.running)
  }
  func testSpellRequestWhileChargingIsDeferred() async throws {
    let (model, link, directory) = try makeModel()
    defer { try? FileManager.default.removeItem(at: directory) }
    let session = UUID()
    _ = model.authority.receive(WireEnvelope(eventID: UUID(), sessionID: session, sequence: 1, kind: .hello, payload: try JSONEncoder().encode(HelloPayload(appVersion: "test", requestedMode: .showOff))), now: 0)
    _ = model.authority.receive(WireEnvelope(eventID: UUID(), sessionID: session, sequence: 2, kind: .armRequest, payload: try JSONEncoder().encode(ArmRequestPayload(spell: .fireball, charge: 1))), now: 0)
    model.select(.lightning)
    XCTAssertTrue(link.requests.isEmpty); XCTAssertEqual(model.selectedSpell, .fireball)
    XCTAssertTrue(model.message.contains("蓄力"))
  }
  func testEveryFailureAndPhaseRequiresExplicitRecovery() {
    for failure in AppFailure.allCases {
      for phase in CaptureState.allCases {
        let result = RecoveryPolicy.transition(error: failure, phase: phase)
        XCTAssertFalse(result.canAcceptCast); XCTAssertFalse(result.automaticallyResume)
        XCTAssertTrue(result.revokePermit); XCTAssertTrue(result.releaseResources)
        XCTAssertFalse(result.exits.isEmpty)
        if failure == .audioFailed { XCTAssertTrue(result.exits.contains(.shareSilent)) }
      }
    }
  }
}
