import WatchKit
import WristMagicCore
@MainActor final class HapticPlayer {
  private var limiter = FeedbackRateLimiter()
  var enabled = true
  func play(_ event: FeedbackEvent, at: Double) {
    guard enabled, limiter.accept(at: at) else { return }
    let type: WKHapticType
    switch event {
    case .start: type = .start
    case .ready: type = .directionUp
    case .released: type = .success
    case .retry: type = .retry
    case .paused: type = .stop
    }
    WKInterfaceDevice.current().play(type)
  }
}
