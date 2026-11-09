import Foundation
@preconcurrency import Vision
import CoreImage
import AppKit
import PDFKit

public final class VisionOCREngine: Sendable {
    public static let shared = VisionOCREngine()

    private init() {}

    /// Performs high-accuracy local Apple Vision OCR on either an image OR a multi-page scanned PDF.
    public func recognizeText(from url: URL) async throws -> String {
        if url.pathExtension.lowercased() == "pdf" {
            return try await recognizePDF(from: url)
        }
        let cgImage = try ImageTransformer.loadOrientedCGImage(from: url)
        return try await recognizeCGImage(cgImage)
    }

    /// Scans QR codes and barcodes in an image or PDF using Apple Vision + CoreImage `CIDetectorTypeQRCode` fallback.
    public func detectBarcodes(from url: URL) async throws -> [String] {
        let cgImages: [CGImage]
        if url.pathExtension.lowercased() == "pdf" {
            guard let doc = PDFDocument(url: url) else {
                throw FlipDocError("Failed to open PDF for QR scanning.")
            }
            cgImages = (0..<doc.pageCount).compactMap { idx in
                guard let page = doc.page(at: idx) else { return nil }
                return try? renderPDFPageToCGImage(page: page, scale: 2.5)
            }
        } else {
            cgImages = [try ImageTransformer.loadOrientedCGImage(from: url)]
        }

        var payloads: [String] = []
        for cgImage in cgImages {
            // 1. CoreImage CIDetector QR fast-path (100% deterministic on CPU & CI VMs)
            let ciImage = CIImage(cgImage: cgImage)
            if let detector = CIDetector(
                ofType: CIDetectorTypeQRCode,
                context: nil,
                options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]
            ) {
                let features = detector.features(in: ciImage)
                for case let qr as CIQRCodeFeature in features {
                    if let msg = qr.messageString?.trimmingCharacters(in: .whitespacesAndNewlines), !msg.isEmpty {
                        payloads.append(msg)
                    }
                }
            }

            // 2. Vision VNDetectBarcodesRequest for 1D/2D barcodes (EAN, Code128, Aztec, PDF417, QR)
            let visionPayloads = (try? await detectVisionBarcodes(in: cgImage)) ?? []
            payloads.append(contentsOf: visionPayloads)
        }

        var unique: [String] = []
        for p in payloads where !unique.contains(p) {
            unique.append(p)
        }
        return unique
    }

    private func detectVisionBarcodes(in cgImage: CGImage) async throws -> [String] {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNDetectBarcodesRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = (request.results as? [VNBarcodeObservation]) ?? []
                let strings = observations.compactMap { $0.payloadStringValue?.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                continuation.resume(returning: strings)
            }
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: [])
            }
        }
    }

    private func recognizePDF(from pdfURL: URL) async throws -> String {
        guard let doc = PDFDocument(url: pdfURL) else {
            throw FlipDocError("Failed to open PDF for OCR.")
        }
        var sections: [String] = []
        for index in 0..<doc.pageCount {
            guard let page = doc.page(at: index) else { continue }
            let cgImage = try renderPDFPageToCGImage(page: page, scale: 3.0)
            let pageText = try await recognizeCGImage(cgImage)
            let trimmed = pageText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                if doc.pageCount > 1 {
                    sections.append("--- Page \(index + 1) ---\n\(trimmed)")
                } else {
                    sections.append(trimmed)
                }
            }
        }
        return sections.joined(separator: "\n\n")
    }

    public func renderPDFPageToCGImage(page: PDFPage, scale: CGFloat = 3.0) throws -> CGImage {
        let bounds = page.bounds(for: .mediaBox)
        let width = max(1, Int((bounds.width * scale).rounded()))
        let height = max(1, Int((bounds.height * scale).rounded()))
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
            throw FlipDocError("Failed creating bitmap buffer for PDF page.")
        }

        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.saveGState()
        ctx.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: ctx)
        ctx.restoreGState()

        guard let image = ctx.makeImage() else {
            throw FlipDocError("Failed rendering PDF page.")
        }
        return image
    }

    public func recognizeCGImage(_ cgImage: CGImage) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: "")
                    return
                }
                // Sort top-to-bottom (Vision normalized Y increases bottom-to-top)
                let sorted = observations.sorted { lhs, rhs in
                    let dy = abs(lhs.boundingBox.midY - rhs.boundingBox.midY)
                    if dy > 0.014 {
                        return lhs.boundingBox.midY > rhs.boundingBox.midY
                    }
                    return lhs.boundingBox.minX < rhs.boundingBox.minX
                }
                let lines = sorted.compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: lines.joined(separator: "\n"))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
