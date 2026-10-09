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
    XCTAssertFalse(exchange.accept(ack(request)))
    XCTAssertEqual(exchange.advance(now: 1), .finished)
  }
  func testCompletionOnceAndOldAckRejected() {
    let request = request()
    var exchange = LiveExchange(request: request, now: 0)
    XCTAssertFalse(exchange.accept(ack(request, session: UUID())))
    XCTAssertFalse(exchange.accept(ack(request, event: UUID())))
    XCTAssertTrue(exchange.accept(ack(request)))
    XCTAssertFalse(exchange.accept(ack(request)))
    XCTAssertEqual(exchange.advance(now: 1), .finished)
    var cancelled = LiveExchange(request: request, now: 0)
    cancelled.cancel()
    XCTAssertFalse(cancelled.accept(ack(request)))
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
}
