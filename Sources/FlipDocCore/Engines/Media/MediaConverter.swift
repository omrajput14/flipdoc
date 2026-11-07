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
}
