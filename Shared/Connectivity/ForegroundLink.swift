import Foundation
import WatchConnectivity
import WristMagicCore

public enum LinkError: Error { case unavailable, notInstalled, timeout, invalidReply, invalidEnvelope }
/// Live messages only. Application context is reserved for revisioned static settings.
@MainActor public class ForegroundLink: NSObject, LiveLink, WCSessionDelegate {
  public var foreground = false
  public var onEnvelope: ((WireEnvelope) -> WireEnvelope?)?
  public var onSettings: ((SettingsPayload) -> Void)?
  public var onAvailability: ((Bool, String) -> Void)?
  private let session: WCSession
  private var pending: [UUID: CheckedContinuation<WireEnvelope, Error>] = [:]
  private var timers: [UUID: Task<Void, Never>] = [:]
  private var settingsRevision: UInt64 = 0
  public init(session: WCSession = .default) {
    self.session = session
    super.init()
    if WCSession.isSupported() { session.delegate = self; session.activate() }
  }
  public var available: Bool {
    guard WCSession.isSupported(), foreground, session.activationState == .activated, session.isReachable else { return false }
    #if os(iOS)
    return session.isPaired && session.isWatchAppInstalled
    #else
    return session.isCompanionAppInstalled
    #endif
  }
  public func setForeground(_ value: Bool) {
    foreground = value
    if !value { cancelPending() }
    reportAvailability()
  }
  public func send(_ envelope: WireEnvelope) async throws -> WireEnvelope {
    guard envelope.isValid else { throw LinkError.invalidEnvelope }
    guard available else { throw LinkError.unavailable }
    let data = try JSONEncoder().encode(envelope)
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        guard pending[envelope.eventID] == nil else { continuation.resume(throwing: LinkError.invalidEnvelope); return }
        pending[envelope.eventID] = continuation
        transmit(data, request: envelope)
        timers[envelope.eventID] = Task { [weak self] in
          do {
            try await Task.sleep(for: .milliseconds(300))
            guard let self, pending[envelope.eventID] != nil else { return }
            if available { transmit(data, request: envelope) }
            try await Task.sleep(for: .milliseconds(500))
            finish(envelope.eventID, result: .failure(LinkError.timeout))
          } catch { }
        }
      }
    } onCancel: {
      Task { @MainActor [weak self] in self?.finish(envelope.eventID, result: .failure(CancellationError())) }
    }
  }
  private func transmit(_ data: Data, request: WireEnvelope) {
    session.sendMessageData(data, replyHandler: { [weak self] response in
      Task { @MainActor in
        guard let self, let reply = WireEnvelope.decode(response), reply.sessionID == request.sessionID else { return }
        if reply.kind == .ack {
          guard let ack = try? JSONDecoder().decode(AckPayload.self, from: reply.payload), ack.eventID == request.eventID else { return }
        } else {
          guard request.kind == .armRequest, reply.kind == .armGrant else { return }
        }
        finish(request.eventID, result: .success(reply))
      }
    }, errorHandler: { [weak self] _ in
      // A transient per-attempt error does not create a new event or reset its deadline.
      Task { @MainActor in if self?.available == false { self?.cancelPending() } }
    })
  }
  private func finish(_ id: UUID, result: Result<WireEnvelope, Error>) {
    guard let continuation = pending.removeValue(forKey: id) else { return }
    timers.removeValue(forKey: id)?.cancel()
    continuation.resume(with: result)
  }
  private func cancelPending() {
    for id in Array(pending.keys) { finish(id, result: .failure(LinkError.unavailable)) }
  }
  private func reportAvailability() {
    if !available { cancelPending() }
    #if os(iOS)
    let installed = session.isWatchAppInstalled
    #else
    let installed = session.isCompanionAppInstalled
    #endif
    onAvailability?(available, installed ? "连接中断，请重新连接" : "请安装配套应用")
  }
  public func publishSettings(_ settings: SettingsPayload) throws {
    guard session.activationState == .activated, settings.revision > settingsRevision else { return }
    try session.updateApplicationContext(["settings": try JSONEncoder().encode(settings)])
    settingsRevision = settings.revision
  }
  nonisolated public func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
    Task { @MainActor [weak self] in self?.reportAvailability() }
  }
  nonisolated public func sessionReachabilityDidChange(_ session: WCSession) {
    Task { @MainActor [weak self] in self?.reportAvailability() }
  }
  nonisolated public func session(_ session: WCSession, didReceiveMessageData data: Data, replyHandler: @escaping (Data) -> Void) {
    // WCSession's legacy reply closure is not Sendable; confine it to this immutable box.
    let reply = ReplyBox(replyHandler)
    Task { @MainActor [weak self] in
      guard let self, foreground, let envelope = WireEnvelope.decode(data),
        let response = onEnvelope?(envelope), let encoded = try? JSONEncoder().encode(response) else {
        reply.call(Data()); return
      }
      reply.call(encoded)
    }
  }
  nonisolated public func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
    guard let data = applicationContext["settings"] as? Data else { return }
    Task { @MainActor [weak self] in
      guard let self, let value = try? JSONDecoder().decode(SettingsPayload.self, from: data), value.revision > settingsRevision else { return }
      settingsRevision = value.revision; onSettings?(value)
    }
  }
  #if os(iOS)
  nonisolated public func sessionDidBecomeInactive(_ session: WCSession) {
    Task { @MainActor [weak self] in self?.cancelPending(); self?.onAvailability?(false, "手表切换，请重新连接") }
  }
  nonisolated public func sessionDidDeactivate(_ session: WCSession) { session.activate() }
  nonisolated public func sessionWatchStateDidChange(_ session: WCSession) {
    Task { @MainActor [weak self] in self?.reportAvailability() }
  }
  #endif
}
private final class ReplyBox: @unchecked Sendable {
  private let closure: (Data) -> Void
  init(_ closure: @escaping (Data) -> Void) { self.closure = closure }
  func call(_ data: Data) { closure(data) }
}
