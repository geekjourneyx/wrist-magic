import Foundation
import WristMagicCore

/// Original application-generated PCM. The same waveform drives live phone/Watch and export.
enum SpellPCM {
  static let sampleRate = 48_000
  static let duration = 0.6
  static func samples(_ spell: SpellID) -> [Float] {
    let count = Int(Double(sampleRate) * duration)
    return (0..<count).map { i in
      let t = Double(i) / Double(sampleRate)
      let envelope = min(1,t * 100) * pow(max(0,1-t/duration),2)
      let frequency: Double
      switch spell {
      case .fireball: frequency = 180 + 650 * t
      case .lightning: frequency = 1050 - 900 * t
      case .forcePush: frequency = 95 + 100 * t
      }
      let primary = sin(2 * .pi * (frequency * t))
      let harmonic = sin(2 * .pi * frequency * t * 2.17) * 0.18
      return Float((primary + harmonic) * envelope * 0.35)
    }
  }
  static func wav(_ samples: [Float], stereo: Bool = true) -> Data {
    let channels = stereo ? 2 : 1
    var data = Data()
    func word<T: FixedWidthInteger>(_ value: T) {
      var little = value.littleEndian
      withUnsafeBytes(of:&little) { data.append(contentsOf:$0) }
    }
    data.append(Data("RIFF".utf8)); word(UInt32(36 + samples.count * channels * 2))
    data.append(Data("WAVEfmt ".utf8)); word(UInt32(16)); word(UInt16(1)); word(UInt16(channels))
    word(UInt32(sampleRate)); word(UInt32(sampleRate * channels * 2)); word(UInt16(channels * 2)); word(UInt16(16))
    data.append(Data("data".utf8)); word(UInt32(samples.count * channels * 2))
    for sample in samples {
      let pcm = Int16(max(-1,min(1,sample)) * 32767)
      for _ in 0..<channels { word(pcm) }
    }
    return data
  }
}
