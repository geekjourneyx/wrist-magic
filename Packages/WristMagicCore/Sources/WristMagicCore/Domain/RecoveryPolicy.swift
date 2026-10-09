public enum CaptureState: String, Sendable, CaseIterable {
  case idle, preparing, countdown, recording, processing, review, paused, failed
}
public enum AppFailure: String, Sendable, CaseIterable {
  case linkLost, trackingLost, cameraDenied, diskFull, writerFailed, audioFailed, thermal,
    background, motionUnavailable, cameraInterrupted, unknown
}
public enum RecoveryExit: String, Sendable { case retry, shareSilent, returnToPractice }
public struct RecoveryAction: Sendable, Equatable {
  public var canAcceptCast: Bool { false }
  public var automaticallyResume: Bool { false }
  public let pause: Bool
  public let revokePermit: Bool
  public let releaseResources: Bool
  public let interruptClip: Bool
  public let exits: [RecoveryExit]
  public let message: String
  public init(
    pause: Bool, revokePermit: Bool, releaseResources: Bool, interruptClip: Bool,
    exits: [RecoveryExit], message: String
  ) {
    self.pause = pause
    self.revokePermit = revokePermit
    self.releaseResources = releaseResources
    self.interruptClip = interruptClip
    self.exits = exits
    self.message = message
  }
}
public enum RecoveryPolicy {
  public static func transition(error: AppFailure, phase: CaptureState) -> RecoveryAction {
    let message: String
    switch error {
    case .linkLost: message = "连接已断开，请重新连接。"
    case .trackingLost: message = "跟踪中断，请重新定位。"
    case .cameraDenied: message = "请在设置中允许相机，或返回练习。"
    case .diskFull: message = "空间不足，请清理后重试。"
    case .writerFailed: message = "录像处理失败，请重拍。"
    case .audioFailed: message = "声音处理失败，可重试或分享静音版。"
    case .thermal: message = "设备温度较高，请稍后继续。"
    case .background: message = "会话已暂停，请手动继续。"
    case .motionUnavailable: message = "动作传感器不可用，可轻点施法。"
    case .cameraInterrupted: message = "相机中断，请重试。"
    case .unknown: message = "遇到问题，请重试或返回练习。"
    }
    return .init(
      pause: true, revokePermit: true, releaseResources: true, interruptClip: phase == .recording,
      exits: error == .audioFailed
        ? [.retry, .shareSilent, .returnToPractice] : [.retry, .returnToPractice], message: message)
  }
}
