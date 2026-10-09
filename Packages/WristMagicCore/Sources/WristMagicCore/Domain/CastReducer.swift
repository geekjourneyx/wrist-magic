public enum CastReducer {
  public static func reduce(_ state: CastState, _ action: CastAction) -> CastState {
    var s = state
    switch action {
    case .pause:
      s.phase = .paused
      s.charge = 0
    case .reset:
      s.phase = .selecting
      s.charge = 0
    case .resume where s.phase == .paused:
      s.phase = .selecting
      s.charge = 0
    case .select(let spell) where [.selecting, .charging, .fired, .retry].contains(s.phase):
      s.spell = spell
      s.phase = .selecting
      s.charge = 0
    case .prepare where [.selecting, .fired, .retry].contains(s.phase):
      s.phase = .charging
      s.charge = 0
    case .crown(let v) where s.phase == .charging && v.isFinite: s.charge = min(1, max(0, v))
    case .armed where s.phase == .charging && s.charge == 1: s.phase = .ready
    case .trigger where s.phase == .ready: s.phase = .fired
    case .timeout where s.phase == .ready:
      s.phase = .retry
      s.charge = 0
    default: break
    }
    return s
  }
}
