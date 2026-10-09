import Foundation
import WristMagicCore
@MainActor final class WatchLink: ForegroundLink {
  func bind(_ model: WatchCastModel) {
    onAvailability = { [weak model] available, reason in
      if !available { model?.disconnect(reason: reason) }
    }
    onSettings = { [weak model] in model?.applySettings($0) }
    onEnvelope = { [weak model] envelope in
      model?.receive(envelope)
      let ack = AckPayload(receipt: .accepted, eventID: envelope.eventID)
      return WireEnvelope(eventID: UUID(), sessionID: envelope.sessionID, sequence: envelope.sequence,
        kind: .ack, payload: (try? JSONEncoder().encode(ack)) ?? Data())
    }
  }
}
