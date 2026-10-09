import XCTest

@testable import WristMagicCore

final class MotionEffectRecoveryTests: XCTestCase {
  func sample(
    _ t: Double, _ a: SIMD3<Double> = .zero, _ r: SIMD3<Double> = .zero,
    _ q: SIMD4<Double> = SIMD4(0, 0, 0, 1)
  ) -> MotionSample {
    .init(t: t, acceleration: a, rotationRate: r, gravity: SIMD3(0, -1, 0), attitude: q)
  }
  func testCalibrationKnownRotationsPreserveForward() {
    let q = SIMD4<Double>(0, 1, 0, 0)
    let left = WristCalibration(neutral: SIMD4(0, 0, 0, 1))!.normalize(sample(0, SIMD3(0, 0, 7)))
    let right = WristCalibration(neutral: q)!.normalize(sample(0, SIMD3(0, 0, 7), .zero, q))
    XCTAssertEqual(left.acceleration, right.acceleration)
    let worldForward = WristCalibration(neutral: SIMD4(0, 0, 0, 1))!.normalize(
      sample(0, SIMD3(0, 0, -7), .zero, q))
    XCTAssertEqual(worldForward.acceleration.z, 7, accuracy: 0.0001)
    XCTAssertNil(WristCalibration(neutral: .zero))
  }
  func testSelectedSpellAndCrownNegatives() {
    let gate = RuleGestureGate()
    let down = [sample(0), sample(0.1, SIMD3(0, -8, 0)), sample(0.2)]
    XCTAssertTrue(gate.evaluate(samples: down, profile: .experimental(.lightning)).accepted)
    XCTAssertFalse(gate.evaluate(samples: down, profile: .experimental(.fireball)).accepted)
    XCTAssertFalse(
      gate.evaluate(
        samples: [sample(0), sample(0.1, .zero, SIMD3(0, 0, 3)), sample(0.2)],
        profile: .experimental(.forcePush)
      ).accepted)
    XCTAssertFalse(
      gate.evaluate(
        samples: [sample(0), sample(0.3, SIMD3(0, 0, 9)), sample(0.4)],
        profile: .experimental(.fireball)
      ).accepted)
  }
  func testUnarmedOneImpulseCooldownAndGap() {
    var trigger = GestureTrigger(profiles: [.fireball: .experimental(.fireball)])
    let ready = CastState(spell: .fireball, phase: .ready, charge: 1)
    let unarmed = CastState(spell: .fireball, phase: .charging, charge: 1)
    for i in 0...20 {
      XCTAssertNil(
        trigger.update(
          sample: sample(Double(i) / 50, SIMD3(0, 0, 9)), state: unarmed, now: Double(i) / 50))
    }
    for i in 0...21 {
      let t = 1 + Double(i) / 50
      XCTAssertNil(trigger.update(sample: sample(t), state: ready, now: t))
    }
    XCTAssertNil(trigger.update(sample: sample(1.44, SIMD3(0, 0, 8)), state: ready, now: 1.44))
    XCTAssertEqual(trigger.update(sample: sample(1.46), state: ready, now: 1.46)?.accepted, true)
    XCTAssertNil(trigger.update(sample: sample(1.48, SIMD3(0, 0, 8)), state: ready, now: 1.48))
    _ = trigger.update(sample: sample(1.5), state: unarmed, now: 1.5)
    for i in 0...21 {
      let t = 1.52 + Double(i) / 50
      XCTAssertNil(trigger.update(sample: sample(t), state: ready, now: t))
    }
    XCTAssertNil(trigger.update(sample: sample(1.96, SIMD3(0, 0, 8)), state: ready, now: 1.96))
    for i in 0...22 {
      let t = 2.2 + Double(i) / 50
      XCTAssertNil(trigger.update(sample: sample(t), state: ready, now: t))
    }
    XCTAssertNil(trigger.update(sample: sample(2.66, SIMD3(0, 0, 8)), state: ready, now: 2.66))
    XCTAssertEqual(trigger.update(sample: sample(2.68), state: ready, now: 2.68)?.accepted, true)
  }
  func testSensorDiscontinuityRequiresFreshNeutralWithRegularCallerClock() {
    for discontinuousSensorTime in [0.1, 2.0] {
      var trigger = GestureTrigger(profiles: [.fireball: .experimental(.fireball)])
      let ready = CastState(spell: .fireball, phase: .ready, charge: 1)
      for i in 0...19 {
        let t = Double(i) / 50
        XCTAssertNil(trigger.update(sample: sample(t), state: ready, now: t))
      }
      XCTAssertNil(trigger.update(sample: sample(discontinuousSensorTime), state: ready, now: 0.4))
      XCTAssertNil(
        trigger.update(
          sample: sample(discontinuousSensorTime + 0.02, SIMD3(0, 0, 8)), state: ready, now: 0.42))
      XCTAssertNil(
        trigger.update(sample: sample(discontinuousSensorTime + 0.04), state: ready, now: 0.44))
      for i in 0...22 {
        let offset = Double(i) / 50
        XCTAssertNil(
          trigger.update(
            sample: sample(discontinuousSensorTime + 0.06 + offset), state: ready,
            now: 0.46 + offset))
      }
      XCTAssertNil(
        trigger.update(
          sample: sample(discontinuousSensorTime + 0.52, SIMD3(0, 0, 8)), state: ready, now: 0.92))
      XCTAssertEqual(
        trigger.update(sample: sample(discontinuousSensorTime + 0.54), state: ready, now: 0.94)?
          .accepted, true)
    }
  }
  func testAcquisitionErrorsCannotUnlatchContinuousReadyCycle() {
    for invalidSample in [false, true] {
      var trigger = GestureTrigger(profiles: [.fireball: .experimental(.fireball)])
      let ready = CastState(spell: .fireball, phase: .ready, charge: 1)
      for i in 0...22 {
        let t = Double(i) / 50
        XCTAssertNil(trigger.update(sample: sample(t), state: ready, now: t))
      }
      XCTAssertNil(trigger.update(sample: sample(0.46, SIMD3(0, 0, 8)), state: ready, now: 0.46))
      XCTAssertEqual(trigger.update(sample: sample(0.48), state: ready, now: 0.48)?.accepted, true)
      if invalidSample {
        XCTAssertNil(trigger.update(sample: sample(0.5, SIMD3(.nan, 0, 0)), state: ready, now: 0.5))
      }
      // Invalid input is followed by regular samples; the other case introduces a gap.
      let start = invalidSample ? 0.52 : 2.0
      let count = invalidSample ? 100 : 22
      for i in 0...count {
        let t = start + Double(i) / 50
        XCTAssertNil(trigger.update(sample: sample(t), state: ready, now: t))
      }
      let impulseTime = start + Double(count + 1) / 50
      XCTAssertNil(
        trigger.update(sample: sample(impulseTime, SIMD3(0, 0, 8)), state: ready, now: impulseTime))
      XCTAssertNil(
        trigger.update(sample: sample(impulseTime + 0.02), state: ready, now: impulseTime + 0.02))
    }
  }
  func testEffectTimingDeterminismAndLayout() {
    let cue = EffectCue(
      eventID: UUID(), spell: .lightning, start: 10, seed: 42, origin: .zero,
      direction: SIMD3(0, 0, -1))
    XCTAssertFalse(EffectTimeline.evaluate(cue, at: 9, reducedMotion: false).isActive)
    XCTAssertEqual(
      EffectTimeline.evaluate(cue, at: 10.3, reducedMotion: false),
      EffectTimeline.evaluate(cue, at: 10.3, reducedMotion: false))
    XCTAssertFalse(EffectTimeline.evaluate(cue, at: 11.5, reducedMotion: false).isActive)
    XCTAssertEqual(EffectTimeline.evaluate(cue, at: 10.01, reducedMotion: true).colorAndFlash.w, 0)
    XCTAssertGreaterThan(
      EffectTimeline.evaluate(cue, at: 10.01, reducedMotion: false).colorAndFlash.w, 0)
    XCTAssertEqual(MemoryLayout<EffectParameters>.stride, 64)
    XCTAssertEqual(MemoryLayout<EffectParameters>.alignment, 16)
  }
  func testRecoveryMatrixAndSilentExit() {
    for phase in CaptureState.allCases {
      for failure in [
        AppFailure.background, .linkLost, .trackingLost, .cameraInterrupted, .thermal,
      ] {
        let action = RecoveryPolicy.transition(error: failure, phase: phase)
        XCTAssertFalse(action.canAcceptCast)
        XCTAssertFalse(action.automaticallyResume)
        XCTAssertTrue(action.pause)
        XCTAssertTrue(action.revokePermit)
        XCTAssertTrue(action.releaseResources)
        XCTAssertEqual(action.interruptClip, phase == .recording)
        XCTAssertTrue(action.exits.contains(.returnToPractice))
      }
    }
    XCTAssertTrue(
      RecoveryPolicy.transition(error: .audioFailed, phase: .processing).exits.contains(
        .shareSilent))
    XCTAssertNotEqual(
      RecoveryPolicy.transition(error: .motionUnavailable, phase: .idle).message,
      RecoveryPolicy.transition(error: .trackingLost, phase: .idle).message)
  }
}
