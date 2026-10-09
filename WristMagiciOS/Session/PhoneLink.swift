import Foundation
import WristMagicCore

@MainActor final class PhoneLink: ForegroundLink {
  let coordinator: SessionCoordinator
  init(coordinator: SessionCoordinator) {
    self.coordinator = coordinator
    super.init()
    onEnvelope = { [weak coordinator] envelope in
      coordinator?.receive(envelope, now: ProcessInfo.processInfo.systemUptime)
    }
    onAvailability = { [weak coordinator] available, reason in
      if !available { coordinator?.invalidate(reason: reason) }
    }
    coordinator.onPushGrant = { [weak self] envelope in
      Task { try? await self?.send(envelope) }
    }
  }
}
