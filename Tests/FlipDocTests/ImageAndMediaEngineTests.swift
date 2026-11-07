import Foundation
import CoreGraphics
import PDFKit
import AVFoundation
import CoreVideo
import Testing
@testable import FlipDocCore

@Suite("Image, Audio & Video Conversion Engines")
struct ImageAndMediaEngineTests {

    @Test("ImageTransformer converts formats including offline WebP, strips EXIF, and creates collages")
    @MainActor
    func imagePipelineEndToEnd() async throws {
        let dir = try TestFixtures.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let src1 = dir.appendingPathComponent("photo1.png")
        let src2 = dir.appendingPathComponent("photo2.png")
        let src3 = dir.appendingPathComponent("photo3.png")
        try TestFixtures.makeTestPNG(at: src1)
        try TestFixtures.makeTestPNG(at: src2)
        try TestFixtures.makeTestPNG(at: src3)

        // Metadata inspection & stripping
        let metaBefore = ImageTransformer.inspectMetadata(url: src1)
        #expect(metaBefore.contains(where: { $0.value.contains("FlipDoc Camera") }))

        let cleaned = try ImageTransformer.stripMetadata(inputURL: src1)
        let metaAfter = ImageTransformer.inspectMetadata(url: cleaned)
        #expect(!metaAfter.contains(where: { $0.value.contains("FlipDoc Camera") }))

        // JPG + HEIC + WebP conversions
        let jpg = try await ImageTransformer.convert(inputURL: src1, toFormat: "jpg")
        #expect(FileManager.default.fileExists(atPath: jpg.path))

        let heic = try await ImageTransformer.convert(inputURL: src1, toFormat: "heic")
        #expect(FileManager.default.fileExists(atPath: heic.path))

        let webp = try await ImageTransformer.convert(inputURL: src1, toFormat: "webp")
        #expect(FileManager.default.fileExists(atPath: webp.path))
        let webpBytes = (try? Data(contentsOf: webp)) ?? Data()
        #expect(webpBytes.count > 24)
        let magicRIFF = String(data: webpBytes.prefix(4), encoding: .ascii)
        let magicWEBP = String(data: webpBytes.subdata(in: 8..<12), encoding: .ascii)
        #expect(magicRIFF == "RIFF")
        #expect(magicWEBP == "WEBP")

        // Resize & Frame
        let framed = try ImageTransformer.resizeAndFrame(
            inputURL: src1,
            targetWidth: 200,
            targetHeight: 150,
            cornerRadius: 16,
            padding: 20,
            backgroundColor: CGColor(red: 1, green: 1, blue: 1, alpha: 1)
        )
        let framedCG = try ImageTransformer.loadOrientedCGImage(from: framed)
        #expect(framedCG.width == 240)
        #expect(framedCG.height == 190)

        // 3-up Collage & Multi-Image PDF
        let collage = try ImageTransformer.createCollage(inputURLs: [src1, src2, src3])
        #expect(FileManager.default.fileExists(atPath: collage.path))

        let combinedPDF = try ImageTransformer.combineImagesToPDF(inputURLs: [src1, src2])
        let pdfDoc = PDFDocument(url: combinedPDF)
        #expect(pdfDoc?.pageCount == 2)
    }

    @Test("MediaConverter and DocumentTools handle Audio, Video, Animated GIF, Snapshots, and DOCX/HTML")
    func audioVideoAndDocumentPipeline() async throws {
        let dir = try TestFixtures.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        // 1. Document -> DOCX, HTML, PDF
        let mdURL = dir.appendingPathComponent("notes.txt")
        try "FlipDoc converts documents offline on macOS.".write(to: mdURL, atomically: true, encoding: .utf8)

        let docx = try await DocumentTools.convertViaTextutil(inputURL: mdURL, targetFormat: "docx")
        #expect(FileManager.default.fileExists(atPath: docx.path))

        let html = try await DocumentTools.convertViaTextutil(inputURL: mdURL, targetFormat: "html")
        #expect(FileManager.default.fileExists(atPath: html.path))

        let docPDF = try DocumentTools.createPDF(from: [mdURL])
        #expect(PDFDocument(url: docPDF)?.pageCount == 1)

        // 2. Audio: synthesize a 0.25s 440Hz WAV file, then convert to M4A, AIFF, and Mono
        let wavURL = dir.appendingPathComponent("tone.wav")
        try writeSineWAV(to: wavURL)

        let m4aURL = try MediaConverter.convertAudio(inputURL: wavURL, format: "m4a")
        #expect(FileManager.default.fileExists(atPath: m4aURL.path))

        let aiffURL = try MediaConverter.convertAudio(inputURL: wavURL, format: "aiff")
        #expect(FileManager.default.fileExists(atPath: aiffURL.path))

        let monoURL = try MediaConverter.convertAudio(inputURL: m4aURL, format: "m4a", forceMono: true)
        #expect(FileManager.default.fileExists(atPath: monoURL.path))

        // 3. Video: generate a 0.5s MP4 via AVAssetWriter, then test MOV, GIF, Mute & Snapshots
        let mp4URL = dir.appendingPathComponent("clip.mp4")
        try makeTinyMP4(at: mp4URL)

        let movURL = try await MediaConverter.convertVideo(inputURL: mp4URL, toFormat: "mov")
        #expect(FileManager.default.fileExists(atPath: movURL.path))

        let gifURL = try await MediaConverter.videoToAnimatedGIF(inputURL: mp4URL, fps: 6, maxWidth: 240)
        #expect(FileManager.default.fileExists(atPath: gifURL.path))
        let gifData = try Data(contentsOf: gifURL)
        #expect(String(data: gifData.prefix(4), encoding: .ascii) == "GIF8")

        let mutedURL = try await MediaConverter.muteVideo(inputURL: mp4URL)
        #expect(FileManager.default.fileExists(atPath: mutedURL.path))

        let snapsFolder = try await MediaConverter.saveVideoSnapshots(inputURL: mp4URL, count: 2)
        let snaps = try FileManager.default.contentsOfDirectory(atPath: snapsFolder.path)
        #expect(!snaps.isEmpty)
    }

    private func writeSineWAV(to url: URL) throws {
        let sr = 44100
        let count = sr / 4
        var data = Data()
        let dataSize = UInt32(count * 2)
        func le<T: FixedWidthInteger>(_ v: T) -> [UInt8] { withUnsafeBytes(of: v.littleEndian) { Array($0) } }
        data.append(contentsOf: "RIFF".utf8)
        data.append(contentsOf: le(UInt32(36 + dataSize)))
        data.append(contentsOf: "WAVEfmt ".utf8)
        data.append(contentsOf: le(UInt32(16)))
        data.append(contentsOf: le(UInt16(1)))
        data.append(contentsOf: le(UInt16(1)))
        data.append(contentsOf: le(UInt32(sr)))
        data.append(contentsOf: le(UInt32(sr * 2)))
        data.append(contentsOf: le(UInt16(2)))
        data.append(contentsOf: le(UInt16(16)))
        data.append(contentsOf: "data".utf8)
        data.append(contentsOf: le(dataSize))
        for i in 0..<count {
            let v = Int16(sin(2.0 * .pi * 440.0 * Double(i) / Double(sr)) * 12000)
            data.append(contentsOf: le(UInt16(bitPattern: v)))
        }
        try data.write(to: url)
    }

    private func makeTinyMP4(at url: URL) throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 320,
            AVVideoHeightKey: 240
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32ARGB),
                kCVPixelBufferWidthKey as String: 320,
                kCVPixelBufferHeightKey as String: 240
            ]
        )
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        for frameIdx in 0..<10 {
            while !input.isReadyForMoreMediaData {
                Thread.sleep(forTimeInterval: 0.005)
            }
            var pb: CVPixelBuffer?
            CVPixelBufferCreate(kCFAllocatorDefault, 320, 240, kCVPixelFormatType_32ARGB, nil, &pb)
            if let pb = pb {
                CVPixelBufferLockBaseAddress(pb, [])
                if let base = CVPixelBufferGetBaseAddress(pb) {
                    memset(base, Int32(40 + frameIdx * 15), CVPixelBufferGetDataSize(pb))
                }
                CVPixelBufferUnlockBaseAddress(pb, [])
                adaptor.append(pb, withPresentationTime: CMTime(value: CMTimeValue(frameIdx), timescale: 20))
            }
        }
        input.markAsFinished()
        let sema = DispatchSemaphore(value: 0)
        writer.finishWriting { sema.signal() }
        sema.wait()
    }
}
