import Foundation

/// Deterministic lifecycle used by the live adapter; wall-clock retries never create another event.
public struct LiveExchange: Sendable {
  public enum Step: Equatable, Sendable { case waiting, retry, timeout, finished }
  public let request: WireEnvelope
  private let start: Double
  private var retried = false
  private var completed = false
  public init(request: WireEnvelope, now: Double) { self.request = request; start = now }
  public mutating func advance(now: Double) -> Step {
    guard !completed else { return .finished }
    guard now.isFinite, now >= start else { completed = true; return .timeout }
    if now - start >= 0.8 { completed = true; return .timeout }
    if !retried, now - start >= 0.3 { retried = true; return .retry }
    return .waiting
  }
  public mutating func accept(_ response: WireEnvelope) -> Bool {
    guard !completed, response.isValid, response.sessionID == request.sessionID else { return false }
    if response.kind == .ack {
      guard let ack = try? JSONDecoder().decode(AckPayload.self, from: response.payload), ack.eventID == request.eventID else { return false }
    } else {
      guard request.kind == .armRequest, response.kind == .armGrant,
        let arm = try? JSONDecoder().decode(ArmRequestPayload.self, from: request.payload),
        let grant = try? JSONDecoder().decode(ArmGrantPayload.self, from: response.payload), grant.permit.spell == arm.spell else { return false }
    }
    completed = true
    return true
  }
  public mutating func cancel() { completed = true }
}
public enum MotionConversion {
  /// Core Motion userAcceleration already excludes gravity; preserve gravity independently in SI.
  public static func sample(t: Double, userAcceleration: SIMD3<Double>, rotationRate: SIMD3<Double>, gravity: SIMD3<Double>, attitude: SIMD4<Double>) -> MotionSample {
    MotionSample(t: t, acceleration: userAcceleration * 9.80665, rotationRate: rotationRate,
      gravity: gravity * 9.80665, attitude: attitude)
  }
}
public struct FeedbackRateLimiter: Sendable {
  private var last = -Double.infinity
  public init() {}
  public mutating func accept(at: Double) -> Bool {
    guard at.isFinite, at - last >= 0.25 else { return false }
    last = at; return true
  }
}

/// Samples queued before stop/restart cannot reach UI or a logger after that boundary.
public struct MotionDeliveryGate: Sendable {
  private var generation: UInt64 = 0
  private var active = false
  public init() {}
  public mutating func start() -> UInt64 { generation += 1; active = true; return generation }
  public mutating func stop() { generation += 1; active = false }
  public func accepts(_ generation: UInt64) -> Bool { active && self.generation == generation }
}
