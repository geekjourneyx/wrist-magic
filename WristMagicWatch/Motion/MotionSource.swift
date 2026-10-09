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
  private var delivery = MotionDeliveryGate()
  private var neutralStart: Double?
  private var callback: ((MotionSample) -> Void)?
  private var calibration: WristCalibration?
  var onError: ((Error) -> Void)?
  #if DEBUG
  var logger: MotionSampleLogger?
  #endif
  func start(onSample: @escaping (MotionSample) -> Void) throws {
    stop()
    guard manager.isDeviceMotionAvailable else { throw MotionError.unavailable }
    callback = onSample; let epoch = delivery.start()
    manager.deviceMotionUpdateInterval = 1.0 / 50.0
    manager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: queue) { [weak self] motion, error in
      let sample = motion.map { motion in
        MotionConversion.sample(t: motion.timestamp,
          userAcceleration: SIMD3(motion.userAcceleration.x, motion.userAcceleration.y, motion.userAcceleration.z),
          rotationRate: SIMD3(motion.rotationRate.x, motion.rotationRate.y, motion.rotationRate.z),
          gravity: SIMD3(motion.gravity.x, motion.gravity.y, motion.gravity.z),
          attitude: SIMD4(motion.attitude.quaternion.x, motion.attitude.quaternion.y,
            motion.attitude.quaternion.z, motion.attitude.quaternion.w))
      }
      Task { @MainActor in
        guard let self, delivery.accepts(epoch) else { return }
        if let error { stop(); onError?(error); return }
        guard let sample, sample.isValid else { return }
        if calibration == nil {
          let magnitude = sqrt(sample.acceleration.x * sample.acceleration.x + sample.acceleration.y * sample.acceleration.y + sample.acceleration.z * sample.acceleration.z)
          let rotation = sqrt(sample.rotationRate.x * sample.rotationRate.x + sample.rotationRate.y * sample.rotationRate.y + sample.rotationRate.z * sample.rotationRate.z)
          if magnitude < 1 && rotation < 0.5 {
            if neutralStart == nil { neutralStart = sample.t }
            if sample.t - neutralStart! >= 0.4 { calibration = WristCalibration(neutral: sample.attitude) }
          } else { neutralStart = nil }
        }
        #if DEBUG
        logger?.append(sample)
        #endif
        if let calibration { callback?(calibration.normalize(sample)) }
      }
    }
  }
  func stop() {
    delivery.stop(); manager.stopDeviceMotionUpdates(); callback = nil; calibration = nil; neutralStart = nil
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
