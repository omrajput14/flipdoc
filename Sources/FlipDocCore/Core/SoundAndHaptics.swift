import AppKit
import Foundation

/// Provides subtle petal-highlight tick sounds and Force Touch alignment haptics.
@MainActor
public final class SoundAndHaptics {
    public static let shared = SoundAndHaptics()

    private var tickSounds: [NSSound] = []
    private var nextTickIndex: Int = 0
    private var completionSound: NSSound?

    private init() {
        let wavData = Self.makeCrispTickWAV(frequency: 1320, durationMs: 14, volume: 0.22)
        for _ in 0..<4 {
            if let s = NSSound(data: wavData) {
                tickSounds.append(s)
            }
        }
        let doneData = Self.makeCompletionChimeWAV()
        completionSound = NSSound(data: doneData)
    }

    public func playPetalTick() {
        guard AppPreferences.shared.soundsAndHapticsEnabled else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        guard !tickSounds.isEmpty else { return }
        let sound = tickSounds[nextTickIndex % tickSounds.count]
        nextTickIndex = (nextTickIndex + 1) % tickSounds.count
        sound.stop()
        sound.play()
    }

    public func playCompletion() {
        guard AppPreferences.shared.soundsAndHapticsEnabled else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        completionSound?.stop()
        completionSound?.play()
    }

    /// Generates an in-memory 44.1 kHz 16-bit PCM WAV buffer for a warm, ultra-short mechanical glass tick.
    private static func makeCrispTickWAV(frequency: Double, durationMs: Double, volume: Double) -> Data {
        let sampleRate = 44100
        let totalSamples = max(1, Int(Double(sampleRate) * (durationMs / 1000.0)))
        var samples = [Int16](repeating: 0, count: totalSamples)

        for i in 0..<totalSamples {
            let t = Double(i) / Double(sampleRate)
            let progress = Double(i) / Double(totalSamples)
            // Fast attack + exponential decay envelope
            let envelope = exp(-progress * 8.5) * min(1.0, Double(i) / 18.0)
            let pitchDrop = frequency * (1.0 - 0.28 * progress)
            let wave = sin(2.0 * .pi * pitchDrop * t)
            let sampleValue = max(-1.0, min(1.0, wave * envelope * volume))
            samples[i] = Int16(sampleValue * Double(Int16.max))
        }
        return encodeWAV(samples: samples, sampleRate: sampleRate)
    }

    /// Generates a pleasant subtle two-note upward completion chime.
    private static func makeCompletionChimeWAV() -> Data {
        let sampleRate = 44100
        let totalSamples = Int(Double(sampleRate) * 0.16)
        var samples = [Int16](repeating: 0, count: totalSamples)
        let splitSample = totalSamples / 2

        for i in 0..<totalSamples {
            let t = Double(i) / Double(sampleRate)
            let isSecond = i >= splitSample
            let localIdx = isSecond ? (i - splitSample) : i
            let localLen = isSecond ? (totalSamples - splitSample) : splitSample
            let progress = Double(localIdx) / Double(max(1, localLen))
            let freq = isSecond ? 1046.5 : 783.99 // G5 -> C6
            let env = exp(-progress * 5.0) * min(1.0, Double(localIdx) / 40.0)
            let val = sin(2.0 * .pi * freq * t) * env * 0.18
            samples[i] = Int16(max(-1.0, min(1.0, val)) * Double(Int16.max))
        }
        return encodeWAV(samples: samples, sampleRate: sampleRate)
    }

    private static func encodeWAV(samples: [Int16], sampleRate: Int) -> Data {
        let dataSize = UInt32(samples.count * 2)
        let fileSize = 36 + dataSize
        var data = Data()
        data.append(contentsOf: "RIFF".utf8)
        data.append(contentsOf: littleEndianBytes(fileSize))
        data.append(contentsOf: "WAVE".utf8)
        data.append(contentsOf: "fmt ".utf8)
        data.append(contentsOf: littleEndianBytes(UInt32(16)))
        data.append(contentsOf: littleEndianBytes(UInt16(1))) // PCM
        data.append(contentsOf: littleEndianBytes(UInt16(1))) // Mono
        data.append(contentsOf: littleEndianBytes(UInt32(sampleRate)))
        data.append(contentsOf: littleEndianBytes(UInt32(sampleRate * 2)))
        data.append(contentsOf: littleEndianBytes(UInt16(2)))
        data.append(contentsOf: littleEndianBytes(UInt16(16)))
        data.append(contentsOf: "data".utf8)
        data.append(contentsOf: littleEndianBytes(dataSize))
        for s in samples {
            data.append(contentsOf: littleEndianBytes(UInt16(bitPattern: s)))
        }
        return data
    }

    private static func littleEndianBytes<T: FixedWidthInteger>(_ value: T) -> [UInt8] {
        withUnsafeBytes(of: value.littleEndian) { Array($0) }
    }
}
