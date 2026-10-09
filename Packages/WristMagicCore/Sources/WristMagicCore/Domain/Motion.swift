import Foundation

public struct MotionSample: Codable, Sendable {
  public let t: Double
  public let acceleration: SIMD3<Double>
  public let rotationRate: SIMD3<Double>
  public let gravity: SIMD3<Double>
  public let attitude: SIMD4<Double>
  public init(
    t: Double, acceleration: SIMD3<Double>, rotationRate: SIMD3<Double>, gravity: SIMD3<Double>,
    attitude: SIMD4<Double>
  ) {
    self.t = t
    self.acceleration = acceleration
    self.rotationRate = rotationRate
    self.gravity = gravity
    self.attitude = attitude
  }
  public var isValid: Bool {
    t.isFinite
      && (acceleration.array + rotationRate.array + gravity.array + attitude.array).allSatisfy(
        \.isFinite)
      && abs(attitude.array.reduce(0) { $0 + $1 * $1 } - 1) < 0.001
  }
}
extension SIMD3 where Scalar == Double { fileprivate var array: [Double] { [x, y, z] } }
extension SIMD4 where Scalar == Double { fileprivate var array: [Double] { [x, y, z, w] } }
private func cross(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> SIMD3<Double> {
  SIMD3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
}
private func rotate(_ q: SIMD4<Double>, _ v: SIMD3<Double>) -> SIMD3<Double> {
  let u = SIMD3(q.x, q.y, q.z)
  return v + 2 * cross(u, cross(u, v) + q.w * v)
}
/// Neutral attitude defines the forward frame; wrist and Crown orientation are represented by that calibration, never a hardcoded sign flip.
public struct WristCalibration: Sendable {
  public let neutral: SIMD4<Double>
  public init?(neutral: SIMD4<Double>) {
    let n = neutral.array.reduce(0) { $0 + $1 * $1 }
    guard n.isFinite, n > 0 else { return nil }
    self.neutral = neutral / sqrt(n)
  }
  public func normalize(_ sample: MotionSample) -> MotionSample {
    let q = sample.attitude
    let inv = SIMD4(-neutral.x, -neutral.y, -neutral.z, neutral.w)
    func transform(_ v: SIMD3<Double>) -> SIMD3<Double> { rotate(inv, rotate(q, v)) }
    let a = SIMD3(inv.x, inv.y, inv.z)
    let b = SIMD3(q.x, q.y, q.z)
    let xyz = inv.w * b + q.w * a + cross(a, b)
    let relative = SIMD4(xyz.x, xyz.y, xyz.z, inv.w * q.w - (a * b).array.reduce(0, +))
    return MotionSample(
      t: sample.t, acceleration: transform(sample.acceleration),
      rotationRate: transform(sample.rotationRate), gravity: transform(sample.gravity),
      attitude: relative)
  }
}
public struct GestureDecision: Equatable, Sendable {
  public let accepted: Bool
  public let reason: String
  public init(accepted: Bool, reason: String) {
    self.accepted = accepted
    self.reason = reason
  }
}
public struct GestureProfile: Codable, Sendable {
  public let spell: SpellID
  public let values: [String: Double]
  public init(spell: SpellID, values: [String: Double]) {
    self.spell = spell
    self.values = values
  }
  /// Synthetic engineering fixture only. Not trained or cleared for recognition accuracy.
  public static func experimental(_ spell: SpellID) -> Self {
    .init(
      spell: spell,
      values: [
        "experimentalUntrained": 1, "peak": 6, "neutral": 1, "rotationLimit": 4, "return": 2,
        "minDuration": 0.04, "maxDuration": 0.6,
      ])
  }
}
public protocol GestureGate: Sendable {
  func evaluate(samples: [MotionSample], profile: GestureProfile) -> GestureDecision
}
public struct RuleGestureGate: GestureGate {
  public init() {}
  public func evaluate(samples: [MotionSample], profile: GestureProfile) -> GestureDecision {
    func reject(_ reason: String) -> GestureDecision { .init(accepted: false, reason: reason) }
    guard samples.count >= 3, samples.allSatisfy(\.isValid),
      profile.values.values.allSatisfy(\.isFinite), let peak = profile.values["peak"], peak > 0,
      let limit = profile.values["rotationLimit"], limit >= 0, let fall = profile.values["return"],
      fall >= 0,
      let minDuration = profile.values["minDuration"], minDuration >= 0,
      let maxDuration = profile.values["maxDuration"], maxDuration >= minDuration
    else { return reject("invalid") }
    guard zip(samples, samples.dropFirst()).allSatisfy({ $1.t > $0.t && $1.t - $0.t <= 0.2 }) else {
      return reject("gap")
    }
    let duration = samples.last!.t - samples.first!.t
    guard duration >= minDuration, duration <= maxDuration else { return reject("duration") }
    let axis = profile.spell == .lightning ? 1 : 2
    let sign = profile.spell == .lightning ? -1.0 : 1.0
    guard
      samples.allSatisfy({ sqrt(($0.rotationRate * $0.rotationRate).array.reduce(0, +)) <= limit })
    else { return reject("rotation") }
    guard samples.map({ $0.acceleration[axis] * sign }).max()! >= peak,
      abs(samples.last!.acceleration[axis]) <= fall
    else { return reject("impulse") }
    return .init(accepted: true, reason: "experimental impulse")
  }
}
public struct GestureTrigger: Sendable {
  private var samples: [MotionSample] = []
  private var neutralStart: Double?
  private var lastTime: Double?
  private var lastSampleTime: Double?
  private var lastFire: Double?
  private var latched = false
  public let profiles: [SpellID: GestureProfile]
  public let gate: any GestureGate
  public init(profiles: [SpellID: GestureProfile], gate: any GestureGate = RuleGestureGate()) {
    self.profiles = profiles
    self.gate = gate
  }
  public mutating func reset() {
    resetAcquisition()
    latched = false
  }
  private mutating func resetAcquisition() {
    samples = []
    neutralStart = nil
    lastTime = nil
    lastSampleTime = nil
  }
  public mutating func update(sample: MotionSample, state: CastState, now: Double)
    -> GestureDecision?
  {
    guard state.phase == .ready, state.charge == 1, let profile = profiles[state.spell] else {
      reset()
      return nil
    }
    guard now.isFinite, sample.isValid else {
      resetAcquisition()
      return nil
    }
    if let last = lastTime, now <= last || now - last > 0.2 { resetAcquisition() }
    if let last = lastSampleTime, sample.t <= last || sample.t - last > 0.2 {
      resetAcquisition()
    }
    lastTime = now
    lastSampleTime = sample.t
    guard !latched, lastFire.map({ now - $0 >= 0.7 }) ?? true else { return nil }
    if samples.isEmpty {
      let magnitude = sqrt((sample.acceleration * sample.acceleration).array.reduce(0, +))
      if magnitude <= (profile.values["neutral"] ?? 0) {
        if neutralStart == nil { neutralStart = sample.t }
        if sample.t - neutralStart! >= 0.4 { samples = [sample] }
      } else {
        neutralStart = nil
      }
      return nil
    }
    samples.append(sample)
    samples.removeAll { sample.t - $0.t > 0.6 }
    let decision = gate.evaluate(samples: samples, profile: profile)
    if decision.accepted {
      latched = true
      lastFire = now
      return decision
    }
    return nil
  }
}
