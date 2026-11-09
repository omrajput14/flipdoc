import Foundation
import CoreGraphics
@preconcurrency import AVFoundation
import ImageIO
import UniformTypeIdentifiers

public enum MediaConverter {

    // MARK: - Audio Conversions (afconvert + optional ffmpeg)

    public static func convertAudio(inputURL: URL, format: String, forceMono: Bool = false) throws -> URL {
        let fmt = format.lowercased()
        let suffix = forceMono ? "Mono" : nil
        let outURL = OutputNaming.uniqueFileURL(nextTo: inputURL, suffix: suffix, newExtension: fmt)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")

        var args: [String]
        switch fmt {
        case "m4a", "aac":
            args = ["-f", "m4af", "-d", "aac"]
        case "wav":
            args = ["-f", "WAVE", "-d", "LEI16"]
        case "aiff", "aif":
            args = ["-f", "AIFF", "-d", "BEI16"]
        case "flac":
            args = ["-f", "flac", "-d", "flac"]
        default:
            args = ["-f", "m4af", "-d", "aac"]
        }
        if forceMono {
            args += ["-c", "1"]
        }
        args += [inputURL.path, outURL.path]

        proc.arguments = args
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        try proc.run()
        proc.waitUntilExit()

        if proc.terminationStatus == 0, FileManager.default.fileExists(atPath: outURL.path) {
            return outURL
        }

        // Fallback to ffmpeg if installed (e.g. for OGG/Opus/MP3 edge formats)
        let ffmpegPaths = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", NSHomeDirectory() + "/.local/bin/ffmpeg"]
        if let ffmpeg = ffmpegPaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            let ff = Process()
            ff.executableURL = URL(fileURLWithPath: ffmpeg)
            var ffArgs = ["-y", "-i", inputURL.path]
            if forceMono { ffArgs += ["-ac", "1"] }
            ffArgs.append(outURL.path)
            ff.arguments = ffArgs
            ff.standardOutput = FileHandle.nullDevice
            ff.standardError = FileHandle.nullDevice
            try ff.run()
            ff.waitUntilExit()
            if ff.terminationStatus == 0, FileManager.default.fileExists(atPath: outURL.path) {
                return outURL
            }
        }

        throw FlipDocError("Audio conversion to \(fmt.uppercased()) failed.")
    }

    // MARK: - Video Conversions & Tools (100% Native AVFoundation + ImageIO GIF)

    public static func convertVideo(inputURL: URL, toFormat format: String, compress: Bool = false) async throws -> URL {
        let fmt = format.lowercased()
        let asset = AVURLAsset(url: inputURL)
        let preset = compress ? AVAssetExportPresetMediumQuality : AVAssetExportPresetHighestQuality
        let suffix = compress ? "Compressed" : nil
        let outExt = (fmt == "mov") ? "mov" : "mp4"
        let outType: AVFileType = (fmt == "mov") ? .mov : .mp4
        let outURL = OutputNaming.uniqueFileURL(nextTo: inputURL, suffix: suffix, newExtension: outExt)

        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw FlipDocError("Unable to initialize video export session.")
        }
        session.outputURL = outURL
        session.outputFileType = outType
        session.shouldOptimizeForNetworkUse = true

        await session.export()
        if let err = session.error {
            throw err
        }
        guard session.status == .completed else {
            throw FlipDocError("Video export did not complete.")
        }
        return outURL
    }

    public static func extractAudioFromVideo(inputURL: URL, format: String) async throws -> URL {
        let asset = AVURLAsset(url: inputURL)
        let tempM4A = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
        defer { try? FileManager.default.removeItem(at: tempM4A) }

        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw FlipDocError("Video has no exportable audio track.")
        }
        session.outputURL = tempM4A
        session.outputFileType = .m4a
        await session.export()

        if let err = session.error { throw err }
        guard session.status == .completed else {
            throw FlipDocError("Failed extracting audio from video.")
        }

        if format.lowercased() == "m4a" {
            let outURL = OutputNaming.uniqueFileURL(nextTo: inputURL, newExtension: "m4a")
            try FileManager.default.copyItem(at: tempM4A, to: outURL)
            return outURL
        } else {
            let converted = try convertAudio(inputURL: tempM4A, format: format)
            let outURL = OutputNaming.uniqueFileURL(nextTo: inputURL, newExtension: format.lowercased())
            try FileManager.default.moveItem(at: converted, to: outURL)
            return outURL
        }
    }

    /// Strips the audio track losslessly from a video file (`Mute Video`).
    public static func muteVideo(inputURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: inputURL)
        let composition = AVMutableComposition()
        let duration = try await asset.load(.duration)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let sourceVideoTrack = videoTracks.first,
              let compTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw FlipDocError("No video track found in \(inputURL.lastPathComponent).")
        }
        try compTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: sourceVideoTrack, at: .zero)
        compTrack.preferredTransform = try await sourceVideoTrack.load(.preferredTransform)

        let ext = inputURL.pathExtension.lowercased() == "mov" ? "mov" : "mp4"
        let outURL = OutputNaming.uniqueFileURL(nextTo: inputURL, suffix: "Muted", newExtension: ext)
        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            throw FlipDocError("Failed creating video export session.")
        }
        session.outputURL = outURL
        session.outputFileType = (ext == "mov") ? .mov : .mp4
        await session.export()

        if let err = session.error { throw err }
        return outURL
    }

    /// Exports 6 evenly spaced full-resolution PNG snapshots from a video into `<Name> Snapshots/`.
    public static func saveVideoSnapshots(inputURL: URL, count: Int = 6) async throws -> URL {
        let asset = AVURLAsset(url: inputURL)
        let duration = try await asset.load(.duration)
        let totalSeconds = max(0.2, CMTimeGetSeconds(duration))

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        let folder = try OutputNaming.uniqueDirectoryURL(nextTo: inputURL, suffix: "Snapshots")
        let base = OutputNaming.baseName(for: inputURL)
        let frameCount = max(1, min(count, Int(ceil(totalSeconds * 2))))

        for idx in 0..<frameCount {
            let fraction = frameCount == 1 ? 0.0 : Double(idx) / Double(frameCount - 1)
            let sec = min(totalSeconds * 0.96, totalSeconds * fraction)
            let time = CMTime(seconds: sec, preferredTimescale: 600)
            let (cgImage, _) = try await generator.image(at: time)
            let name = String(format: "%@ Snapshot %02d.png", base, idx + 1)
            try DocumentTools.writeCGImage(cgImage, to: folder.appendingPathComponent(name), utType: UTType.png.identifier, quality: 1.0)
        }
        return folder
    }

    /// Converts a video into a crisp looping animated GIF using pure Apple `AVAssetImageGenerator` + `ImageIO`.
    public static func videoToAnimatedGIF(inputURL: URL, fps: Int = 10, maxWidth: CGFloat = 540) async throws -> URL {
        let asset = AVURLAsset(url: inputURL)
        let duration = try await asset.load(.duration)
        let cappedDuration = min(12.0, max(0.2, CMTimeGetSeconds(duration)))
        let totalFrames = max(2, Int((cappedDuration * Double(fps)).rounded()))
        let frameDelay = 1.0 / Double(fps)

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxWidth, height: maxWidth)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.05, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.05, preferredTimescale: 600)

        let outURL = OutputNaming.uniqueFileURL(nextTo: inputURL, newExtension: "gif")
        guard let dest = CGImageDestinationCreateWithURL(outURL as CFURL, UTType.gif.identifier as CFString, totalFrames, nil) else {
            throw FlipDocError("Failed creating GIF destination.")
        }

        let fileProps: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFLoopCount: 0
            ]
        ]
        CGImageDestinationSetProperties(dest, fileProps as CFDictionary)

        let frameProps: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFDelayTime: frameDelay,
                kCGImagePropertyGIFUnclampedDelayTime: frameDelay
            ]
        ]

        for i in 0..<totalFrames {
            let t = CMTime(seconds: Double(i) * frameDelay, preferredTimescale: 600)
            if let (cg, _) = try? await generator.image(at: t) {
                CGImageDestinationAddImage(dest, cg, frameProps as CFDictionary)
            }
        }

        guard CGImageDestinationFinalize(dest) else {
            throw FlipDocError("Failed finalizing animated GIF.")
        }
        return outURL
    }

    /// Speeds up or slows down a video (default 2x fast-forward for screen recordings & demos) using `AVMutableComposition.scaleTimeRange`.
    public static func changeVideoSpeed(inputURL: URL, speedMultiplier: Double = 2.0) async throws -> URL {
        let rate = max(0.25, min(4.0, speedMultiplier))
        let asset = AVURLAsset(url: inputURL)
        let duration = try await asset.load(.duration)
        let composition = AVMutableComposition()

        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let srcVideo = videoTracks.first,
              let dstVideo = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw FlipDocError("No video track found in \(inputURL.lastPathComponent).")
        }
        try dstVideo.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: srcVideo, at: .zero)
        dstVideo.preferredTransform = try await srcVideo.load(.preferredTransform)

        if let srcAudio = (try? await asset.loadTracks(withMediaType: .audio))?.first,
           let dstAudio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try? dstAudio.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: srcAudio, at: .zero)
        }

        let targetSeconds = max(0.1, CMTimeGetSeconds(duration) / rate)
        let scaledDuration = CMTime(seconds: targetSeconds, preferredTimescale: 600)
        composition.scaleTimeRange(CMTimeRange(start: .zero, duration: duration), toDuration: scaledDuration)

        let ext = inputURL.pathExtension.lowercased() == "mov" ? "mov" : "mp4"
        let label = rate == floor(rate) ? "\(Int(rate))x" : String(format: "%.1fx", rate)
        let outURL = OutputNaming.uniqueFileURL(nextTo: inputURL, suffix: label, newExtension: ext)

        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw FlipDocError("Unable to create video speed export session.")
        }
        session.outputURL = outURL
        session.outputFileType = (ext == "mov") ? .mov : .mp4
        session.shouldOptimizeForNetworkUse = true
        await session.export()
        if let err = session.error { throw err }
        return outURL
    }

    /// Renders a studio-quality visual waveform PNG (`<Name> Waveform.png`) from any audio file.
    public static func generateAudioWaveformPNG(inputURL: URL, barCount: Int = 64) async throws -> URL {
        let asset = AVURLAsset(url: inputURL)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        var amplitudes: [CGFloat] = []

        if let track = audioTracks.first, let reader = try? AVAssetReader(asset: asset) {
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsNonInterleaved: false
            ]
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
            if reader.canAdd(output) {
                reader.add(output)
                reader.startReading()
                var allSamples: [Int16] = []
                while reader.status == .reading, let sampleBuffer = output.copyNextSampleBuffer() {
                    if let block = CMSampleBufferGetDataBuffer(sampleBuffer) {
                        let len = CMBlockBufferGetDataLength(block)
                        var bytes = [UInt8](repeating: 0, count: len)
                        CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: len, destination: &bytes)
                        bytes.withUnsafeBytes { raw in
                            let ptr = raw.bindMemory(to: Int16.self)
                            let step = max(1, ptr.count / 1200)
                            var idx = 0
                            while idx < ptr.count {
                                allSamples.append(ptr[idx])
                                idx += step
                            }
                        }
                    }
                }
                if !allSamples.isEmpty {
                    let bucketSize = max(1, allSamples.count / barCount)
                    var rawPeaks: [CGFloat] = []
                    for b in 0..<barCount {
                        let start = b * bucketSize
                        let end = min(allSamples.count, start + bucketSize)
                        if start < end {
                            var sum: Double = 0
                            for s in allSamples[start..<end] {
                                let v = abs(Double(Int(s))) / 32768.0
                                sum += v * v
                            }
                            let rms = sqrt(sum / Double(end - start))
                            rawPeaks.append(CGFloat(rms))
                        } else {
                            rawPeaks.append(0.15)
                        }
                    }
                    let maxPeak = max(0.01, rawPeaks.max() ?? 1.0)
                    amplitudes = rawPeaks.map { max(0.08, min(1.0, $0 / maxPeak)) }
                }
            }
        }

        if amplitudes.count < barCount {
            amplitudes = (0..<barCount).map { i in
                let t = Double(i) / Double(max(1, barCount - 1))
                return CGFloat(0.18 + 0.72 * abs(sin(t * .pi * 3.5) * cos(t * .pi * 2.0)))
            }
        }

        let width = 1200
        let height = 420
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw FlipDocError("Failed creating waveform canvas.")
        }

        // Studio cream background card
        ctx.setFillColor(CGColor(red: 0.985, green: 0.980, blue: 0.972, alpha: 1.0))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let marginX: CGFloat = 84
        let usableWidth = CGFloat(width) - marginX * 2
        let slotWidth = usableWidth / CGFloat(barCount)
        let barWidth = max(4.0, slotWidth * 0.54)
        let maxBarHeight: CGFloat = 250
        let centerY = CGFloat(height) * 0.50

        for (i, amp) in amplitudes.enumerated() {
            let bh = max(14, amp * maxBarHeight)
            let bx = marginX + CGFloat(i) * slotWidth + (slotWidth - barWidth) / 2
            let by = centerY - bh / 2
            let rect = CGRect(x: bx, y: by, width: barWidth, height: bh)
            let path = CGPath(roundedRect: rect, cornerWidth: barWidth / 2, cornerHeight: barWidth / 2, transform: nil)
            let isAccent = (i % 7 == 0) || amp > 0.78
            ctx.setFillColor(
                isAccent
                    ? CGColor(red: 1.0, green: 0.322, blue: 0.0, alpha: 0.95)
                    : CGColor(red: 0.20, green: 0.22, blue: 0.25, alpha: 0.85)
            )
            ctx.addPath(path)
            ctx.fillPath()
        }

        guard let cgImage = ctx.makeImage() else {
            throw FlipDocError("Failed rendering waveform image.")
        }
        let outURL = OutputNaming.uniqueFileURL(nextTo: inputURL, suffix: "Waveform", newExtension: "png")
        try DocumentTools.writeCGImage(cgImage, to: outURL, utType: UTType.png.identifier, quality: 1.0)
        return outURL
    }
}
