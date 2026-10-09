import AVFoundation
import WristMagicCore

/// Procedural PCM source is playable without depending on future asset production.
@MainActor final class WatchSoundPlayer {
  private var player: AVAudioPlayer?
  func play(_ spell: SpellID) {
    stop()
    let rate = 22050
    let frames = rate / 2
    var bytes = Data()
    func word<T: FixedWidthInteger>(_ value: T) {
      var little = value.littleEndian
      withUnsafeBytes(of: &little) { bytes.append(contentsOf: $0) }
    }
    bytes.append(Data("RIFF".utf8)); word(UInt32(36 + frames * 2))
    bytes.append(Data("WAVEfmt ".utf8)); word(UInt32(16)); word(UInt16(1)); word(UInt16(1))
    word(UInt32(rate)); word(UInt32(rate * 2)); word(UInt16(2)); word(UInt16(16))
    bytes.append(Data("data".utf8)); word(UInt32(frames * 2))
    for i in 0..<frames {
      let t = Double(i) / Double(rate)
      let frequency: Double
      switch spell {
      case .fireball: frequency = 180 + 500 * t
      case .lightning: frequency = 900 - 1000 * t
      case .forcePush: frequency = 100 + 120 * t
      }
      let envelope = min(1, t * 40) * max(0, 1 - t * 2)
      word(Int16(sin(2 * .pi * frequency * t) * envelope * 10000))
    }
    do {
      try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
      try AVAudioSession.sharedInstance().setActive(true)
      player = try AVAudioPlayer(data: bytes); player?.play()
    } catch { player = nil }
  }
  func stop() { player?.stop(); player = nil }
}
