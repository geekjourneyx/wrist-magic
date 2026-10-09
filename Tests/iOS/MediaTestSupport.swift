import Foundation
import CoreVideo
import CoreMedia
@testable import WristMagiciOS

enum MediaFixtureError: Error { case backpressureTimeout, completionTimeout }
/// Exact-once timeout gate belongs only to tests; SDK/GPU failure becomes a failed test.
@MainActor private final class FixtureCompletion<Value: Sendable> {
  private var continuation: CheckedContinuation<Value,Error>?
  private var timeout: Task<Void,Never>?
  init(_ continuation: CheckedContinuation<Value,Error>) { self.continuation = continuation }
  func arm() {
    timeout = Task { @MainActor [self] in
      do { try await Task.sleep(for:.seconds(10)) } catch { return }
      self.complete(.failure(MediaFixtureError.completionTimeout))
    }
  }
  func complete(_ result: Result<Value,Error>) {
    guard let continuation else { return }
    self.continuation = nil; timeout?.cancel(); timeout = nil
    continuation.resume(with:result)
  }
}
@MainActor enum MediaTestSupport {
  static func callback<Value:Sendable>(_ begin: (@escaping @MainActor (Result<Value,Error>)->Void) throws -> Void) async throws -> Value {
    try await withCheckedThrowingContinuation { continuation in
      let gate = FixtureCompletion(continuation); gate.arm()
      do { try begin { gate.complete($0) } } catch { gate.complete(.failure(error)) }
    }
  }
  static func deadline<Value:Sendable>(_ operation: @escaping @MainActor () async throws -> Value) async throws -> Value {
    try await callback { complete in
      Task { @MainActor in
        do { complete(.success(try await operation())) } catch { complete(.failure(error)) }
      }
    }
  }
  static func append(_ writer:ClipWriter,buffer:CVPixelBuffer,pts:CMTime) async throws {
    let deadline = ContinuousClock.now.advanced(by:.seconds(10))
    while !(try writer.append(buffer:buffer,pts:pts)) {
      guard ContinuousClock.now < deadline else {throw MediaFixtureError.backpressureTimeout}
      try await Task.sleep(for:.milliseconds(5))
    }
  }
  static func waitUntilReady(_ writer:ClipWriter) async throws {
    let deadline = ContinuousClock.now.advanced(by:.seconds(10))
    while !writer.ready {
      guard writer.state == .writing else {throw MediaError.writerFailed}
      guard ContinuousClock.now < deadline else {throw MediaFixtureError.backpressureTimeout}
      try await Task.sleep(for:.milliseconds(5))
    }
  }
}
