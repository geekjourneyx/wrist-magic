import CoreMotion
import Foundation
import WristMagicCore

@MainActor final class MotionSource {
  enum MotionError: Error { case unavailable }
  private let manager = CMMotionManager()
  private let queue: OperationQueue = {
    let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1
    queue.name = "WristMagic.motion"; return queue
  }()
  private var generation: UInt64 = 0
  private var callback: ((MotionSample) -> Void)?
  private var calibration: WristCalibration?
  var onError: ((Error) -> Void)?
  #if DEBUG
  var logger: MotionSampleLogger?
  #endif
  func start(onSample: @escaping (MotionSample) -> Void) throws {
    stop()
    guard manager.isDeviceMotionAvailable else { throw MotionError.unavailable }
    callback = onSample; let epoch = generation
    manager.deviceMotionUpdateInterval = 1.0 / 50.0
    manager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: queue) { [weak self] motion, error in
      let sample = motion.map { motion in
        MotionSample(t: motion.timestamp,
          acceleration: SIMD3(motion.userAcceleration.x, motion.userAcceleration.y, motion.userAcceleration.z) * 9.80665,
          rotationRate: SIMD3(motion.rotationRate.x, motion.rotationRate.y, motion.rotationRate.z),
          gravity: SIMD3(motion.gravity.x, motion.gravity.y, motion.gravity.z) * 9.80665,
          attitude: SIMD4(motion.attitude.quaternion.x, motion.attitude.quaternion.y,
            motion.attitude.quaternion.z, motion.attitude.quaternion.w))
      }
      Task { @MainActor in
        guard let self, generation == epoch else { return }
        if let error { stop(); onError?(error); return }
        guard let sample, sample.isValid else { return }
        if calibration == nil { calibration = WristCalibration(neutral: sample.attitude) }
        #if DEBUG
        logger?.append(sample)
        #endif
        callback?(calibration?.normalize(sample) ?? sample)
      }
    }
  }
  func stop() {
    generation += 1; manager.stopDeviceMotionUpdates(); callback = nil; calibration = nil
  }
}
#if DEBUG
/// Explicitly started developer capture; writes only actual sensor samples and anonymous labels.
@MainActor final class MotionSampleLogger {
  private var handle: FileHandle?
  func begin(url: URL, anonymousLabel: String) throws {
    stop()
    let header = "label,t,ax,ay,az,rx,ry,rz,gx,gy,gz,qx,qy,qz,qw\n"
    try Data(header.utf8).write(to: url)
    handle = try FileHandle(forWritingTo: url); try handle?.seekToEnd()
    label = anonymousLabel.replacingOccurrences(of: ",", with: "_").replacingOccurrences(of: "\n", with: "_")
  }
  private var label = ""
  func append(_ s: MotionSample) {
    let values = [s.t,s.acceleration.x,s.acceleration.y,s.acceleration.z,s.rotationRate.x,s.rotationRate.y,s.rotationRate.z,s.gravity.x,s.gravity.y,s.gravity.z,s.attitude.x,s.attitude.y,s.attitude.z,s.attitude.w]
    let row = label + "," + values.map(String.init(describing:)).joined(separator: ",") + "\n"
    do { try handle?.write(contentsOf: Data(row.utf8)) } catch { stop() }
  }
  func stop() { try? handle?.close(); handle = nil }
}
#endif
