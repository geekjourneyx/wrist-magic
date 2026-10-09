import Foundation

public enum ClipDisposition: Sendable, Equatable { case discard, interrupted, complete, partial }
public struct ClipTimeline: Sendable {
  public private(set) var firstFrameTime: Double?
  public private(set) var lastFrameTime: Double?
  public init() {}
  public mutating func begin(firstFrameTime: Double) {
    guard firstFrameTime.isFinite, self.firstFrameTime == nil else { return }
    self.firstFrameTime = firstFrameTime
    lastFrameTime = firstFrameTime
  }
  public mutating func acceptFrame(at time: Double) -> Bool {
    guard time.isFinite, let last = lastFrameTime, time > last else { return false }
    lastFrameTime = time
    return true
  }
  public func elapsed(at time: Double) -> Double {
    guard time.isFinite, let start = firstFrameTime else { return 0 }
    return max(0, time - start)
  }
  public func canCast(at time: Double) -> Bool {
    guard let start = firstFrameTime, time.isFinite, time >= start else { return false }
    return elapsed(at: time) < 4.5
  }
  public func shouldFinish(at time: Double) -> Bool {
    firstFrameTime != nil && time.isFinite && elapsed(at: time) >= 6
  }
  public func disposition(at time: Double, interrupted: Bool) -> ClipDisposition {
    let d = elapsed(at: time)
    if d < 2 { return .discard }
    if interrupted { return .interrupted }
    return d >= 6 ? .complete : .partial
  }
}
