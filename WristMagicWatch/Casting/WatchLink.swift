import Foundation
import WristMagicCore
@MainActor final class WatchLink: ForegroundLink {
  func bind(_ model: WatchCastModel) {
    onAvailability = { [weak model] available, reason in
      if !available { model?.disconnect(reason: reason) }
    }
    model.onSettingsChanged = { [weak self] value in try? self?.publishSettings(value) }
    onSettings = { [weak model] in model?.applySettings($0) }
    onEnvelope = { [weak model] envelope in
      let accepted = model?.receive(envelope) == true
      let ack = AckPayload(receipt: accepted ? .accepted : .stale, eventID: envelope.eventID)
      return WireEnvelope(eventID: UUID(), sessionID: envelope.sessionID, sequence: envelope.sequence,
        kind: .ack, payload: (try? JSONEncoder().encode(ack)) ?? Data())
    }
  }
}
