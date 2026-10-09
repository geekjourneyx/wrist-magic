import AVFoundation
import WristMagicCore

/// Procedural PCM source is playable without depending on future asset production.
@MainActor final class WatchSoundPlayer {
  private var player: AVAudioPlayer?
  func play(_ spell: SpellID) {
    stop()
    let bytes = SpellPCM.wav(SpellPCM.samples(spell))
    do {
      try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
      try AVAudioSession.sharedInstance().setActive(true)
      player = try AVAudioPlayer(data: bytes); player?.play()
    } catch { player = nil }
  }
  func stop() { player?.stop(); player = nil }
}
