import Foundation
import WristMagicCore

@MainActor final class PhoneLink: ForegroundLink {
  let coordinator: SessionCoordinator
  var onReceived: ((WireEnvelope) -> Void)?
  var onLinkChanged: ((Bool, String) -> Void)?
  init(coordinator: SessionCoordinator) {
    self.coordinator = coordinator
    super.init()
    onEnvelope = { [weak self] envelope in
      guard let self else { return nil }
      let response: WireEnvelope
      if envelope.kind == .practiceResult {
        response = WireEnvelope(eventID: UUID(), sessionID: envelope.sessionID, sequence: envelope.sequence, kind: .ack, payload: (try? JSONEncoder().encode(AckPayload(receipt: .accepted, eventID: envelope.eventID))) ?? Data())
      } else { response = self.coordinator.receive(envelope, now: ProcessInfo.processInfo.systemUptime) }
      self.onReceived?(envelope)
      return response
    }
    onAvailability = { [weak self] available, reason in
      if !available { self?.coordinator.invalidate(reason: reason) }
      self?.onLinkChanged?(available, reason)
    }
    coordinator.onPushGrant = { [weak self] envelope in
      Task { try? await self?.send(envelope) }
    }
  }
}
