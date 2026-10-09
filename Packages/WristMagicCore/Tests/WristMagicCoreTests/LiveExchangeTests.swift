import XCTest
@testable import WristMagicCore

final class LiveExchangeTests: XCTestCase {
  private func request() -> WireEnvelope {
    WireEnvelope(eventID: UUID(), sessionID: UUID(), sequence: 1, kind: .hello,
      payload: try! JSONEncoder().encode(HelloPayload(appVersion: "test", requestedMode: .reality)))
  }
  private func ack(_ request: WireEnvelope, session: UUID? = nil, event: UUID? = nil) -> WireEnvelope {
    WireEnvelope(eventID: UUID(), sessionID: session ?? request.sessionID, sequence: 1, kind: .ack,
      payload: try! JSONEncoder().encode(AckPayload(receipt: .accepted, eventID: event ?? request.eventID)))
  }
  func testAckLossRetriesSameEventIDOnce() {
    let request = request()
    var exchange = LiveExchange(request: request, now: 0)
    XCTAssertEqual(exchange.advance(now: 0.299), .waiting)
    XCTAssertEqual(exchange.advance(now: 0.3), .retry)
    XCTAssertEqual(exchange.request.eventID, request.eventID)
    XCTAssertEqual(exchange.advance(now: 0.6), .waiting)
    XCTAssertEqual(exchange.advance(now: 0.8), .timeout)
    XCTAssertFalse(exchange.accept(ack(request), now: 0.1))
    XCTAssertEqual(exchange.advance(now: 1), .finished)
  }
  func testCompletionOnceAndOldAckRejected() {
    let request = request()
    var exchange = LiveExchange(request: request, now: 0)
    XCTAssertFalse(exchange.accept(ack(request, session: UUID()), now: 0.1))
    XCTAssertFalse(exchange.accept(ack(request, event: UUID()), now: 0.1))
    XCTAssertTrue(exchange.accept(ack(request), now: 0.1))
    XCTAssertFalse(exchange.accept(ack(request), now: 0.1))
    XCTAssertEqual(exchange.advance(now: 1), .finished)
    var cancelled = LiveExchange(request: request, now: 0)
    cancelled.cancel()
    XCTAssertFalse(cancelled.accept(ack(request), now: 0.1))
  }
  func testGravityExcludedAndUnitsConverted() {
    let sample = MotionConversion.sample(t: 1, userAcceleration: SIMD3(1, 0, 0),
      rotationRate: SIMD3(2, 0, 0), gravity: SIMD3(0, -1, 0), attitude: SIMD4(0, 0, 0, 1))
    XCTAssertEqual(sample.acceleration.x, 9.80665, accuracy: 0.000001)
    XCTAssertEqual(sample.acceleration.y, 0)
    XCTAssertEqual(sample.gravity.y, -9.80665, accuracy: 0.000001)
    XCTAssertEqual(sample.rotationRate.x, 2)
  }
  func testHapticRateLimit250ms() {
    var limiter = FeedbackRateLimiter()
    XCTAssertTrue(limiter.accept(at: 0))
    XCTAssertFalse(limiter.accept(at: 0.249))
    XCTAssertTrue(limiter.accept(at: 0.25))
    XCTAssertFalse(limiter.accept(at: .nan))
    XCTAssertFalse(limiter.accept(at: 0.1))
  }
  func testStopIsIdempotentAndRejectsQueuedSamples() {
    var delivery = MotionDeliveryGate()
    let original = delivery.start()
    XCTAssertTrue(delivery.accepts(original))
    delivery.stop()
    delivery.stop()
    XCTAssertFalse(delivery.accepts(original))
    let restarted = delivery.start()
    XCTAssertFalse(delivery.accepts(original))
    XCTAssertTrue(delivery.accepts(restarted))
  }

  func testReplyCannotBeatUnscheduledDeadlineTimer() {
    let request = request()
    var exact = LiveExchange(request: request, now: 0)
    XCTAssertFalse(exact.accept(ack(request), now: 0.8))
    var late = LiveExchange(request: request, now: 0)
    XCTAssertFalse(late.accept(ack(request), now: 0.801))
    var before = LiveExchange(request: request, now: 0)
    XCTAssertTrue(before.accept(ack(request), now: 0.799))
  }

  func testArmReplyMustMatchExactRequestEvent() {
    let session = UUID()
    let request = WireEnvelope(eventID: UUID(), sessionID: session, sequence: 1, kind: .armRequest,
      payload: try! JSONEncoder().encode(ArmRequestPayload(spell: .fireball, charge: 1)))
    let permit = SessionPermit(sessionID: session, token: UUID(), spell: .fireball)
    var exchange = LiveExchange(request: request, now: 0)
    let stale = WireEnvelope(eventID: UUID(), sessionID: session, sequence: 1, kind: .armGrant,
      payload: try! JSONEncoder().encode(ArmGrantPayload(permit: permit, validFor: 5, requestEventID: UUID())))
    XCTAssertFalse(exchange.accept(stale, now: 0.1))
    let current = WireEnvelope(eventID: UUID(), sessionID: session, sequence: 2, kind: .armGrant,
      payload: try! JSONEncoder().encode(ArmGrantPayload(permit: permit, validFor: 5, requestEventID: request.eventID)))
    XCTAssertTrue(exchange.accept(current, now: 0.2))
    var cancelled = LiveExchange(request: request, now: 0)
    cancelled.cancel()
    XCTAssertEqual(cancelled.advance(now: 0.3), .finished)
    XCTAssertFalse(cancelled.accept(current, now: 0.4))
  }

}
