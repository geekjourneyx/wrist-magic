@preconcurrency import AVFoundation
import WristMagicCore

@MainActor final class PhoneSoundPlayer {
  private var players: [AVAudioPlayer] = []
  func play(_ cue: EffectCue, enabled: Bool) {
    guard enabled else { return }
    players.removeAll { !$0.isPlaying }
    do {
      try AVAudioSession.sharedInstance().setCategory(.playback,mode:.default)
      try AVAudioSession.sharedInstance().setActive(true)
      let player = try AVAudioPlayer(data:SpellPCM.wav(SpellPCM.samples(cue.spell)))
      player.prepareToPlay(); player.play(); players.append(player)
    } catch { stop() }
  }
  func stop() { players.forEach {$0.stop()}; players.removeAll() }
}

/// Cues passed here are already relative to the first video frame, never Watch time.
@MainActor enum ClipAudioMixer {
  static func mix(video: URL, cues: [EffectCue], soundEnabled: Bool) async throws -> URL {
    guard soundEnabled, !cues.isEmpty else { return video }
    let source = AVURLAsset(url:video)
    let duration = try await source.load(.duration)
    let samples = try renderedSamples(cues:cues,duration:duration.seconds)
    let audioURL = video.deletingLastPathComponent().appendingPathComponent("\(UUID()).wav")
    let output = ClipWriter.temporaryURL(in:video.deletingLastPathComponent())
    defer { try? FileManager.default.removeItem(at:audioURL) }
    do {
      try SpellPCM.wav(samples).write(to:audioURL,options:.atomic)
      let audio = AVURLAsset(url:audioURL)
      let composition = AVMutableComposition()
      guard let sourceVideo = try await source.loadTracks(withMediaType:.video).first,
        let sourceAudio = try await audio.loadTracks(withMediaType:.audio).first,
        let videoTrack = composition.addMutableTrack(withMediaType:.video,preferredTrackID:kCMPersistentTrackID_Invalid),
        let audioTrack = composition.addMutableTrack(withMediaType:.audio,preferredTrackID:kCMPersistentTrackID_Invalid) else { throw MediaError.audio }
      try videoTrack.insertTimeRange(CMTimeRange(start:.zero,duration:duration),of:sourceVideo,at:.zero)
      videoTrack.preferredTransform = try await sourceVideo.load(.preferredTransform)
      try audioTrack.insertTimeRange(CMTimeRange(start:.zero,duration:duration),of:sourceAudio,at:.zero)
      guard let exporter = AVAssetExportSession(asset:composition,presetName:AVAssetExportPresetHighestQuality) else { throw MediaError.audio }
      exporter.outputURL = output; exporter.outputFileType = .mp4; exporter.timeRange = CMTimeRange(start:.zero,duration:duration)
      await withCheckedContinuation { (continuation: CheckedContinuation<Void,Never>) in exporter.exportAsynchronously { continuation.resume() } }
      guard exporter.status == .completed else { throw exporter.error ?? MediaError.audio }
      _ = try await ClipValidator.validate(url:output,expectedDuration:duration.seconds,requiresAudio:true)
      return output
    } catch { try? FileManager.default.removeItem(at:output); throw error } // Source video always remains available.
  }
  static func renderedSamples(cues: [EffectCue], duration: Double) throws -> [Float] {
    guard duration.isFinite, duration > 0, duration <= 6.15 else { throw MediaError.audio }
    var result = [Float](repeating:0,count:Int((duration * Double(SpellPCM.sampleRate)).rounded()))
    for cue in cues {
      guard cue.start.isFinite, cue.start >= 0 else { throw MediaError.audio }
      let offset = Int((cue.start * Double(SpellPCM.sampleRate)).rounded())
      guard offset < result.count else { continue }
      let sound = SpellPCM.samples(cue.spell)
      for i in 0..<min(sound.count,result.count-offset) { result[offset+i] = max(-0.95,min(0.95,result[offset+i] + sound[i])) }
    }
    return result
  }
}
