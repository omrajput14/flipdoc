import Foundation
import AppKit
import CoreGraphics
import ImageIO
import PDFKit
import UniformTypeIdentifiers
@preconcurrency import Vision

public enum SensitiveDataKind: String, CaseIterable, Sendable {
    case email = "Emails"
    case phone = "Phone Numbers"
    case idOrCard = "IDs & Card Numbers"
    case amount = "Currency Amounts"
    case custom = "Custom Keyword"
}

public struct RedactionOptions: Sendable {
    public var redactEmails: Bool
    public var redactPhones: Bool
    public var redactIDs: Bool
    public var redactAmounts: Bool
    public var customTerms: [String]

    public init(
        redactEmails: Bool = true,
        redactPhones: Bool = true,
        redactIDs: Bool = true,
        redactAmounts: Bool = false,
        customTerms: [String] = []
    ) {
        self.redactEmails = redactEmails
        self.redactPhones = redactPhones
        self.redactIDs = redactIDs
        self.redactAmounts = redactAmounts
        self.customTerms = customTerms
    }
}

public struct RedactionResult: Sendable {
    public let outputURL: URL
    public let redactedCount: Int
}

/// Permanently redacts sensitive PII (emails, phone numbers, IDs/cards, currency amounts, and custom terms)
/// from Images and PDFs by burning opaque redaction bars into the rasterized pixels so underlying text cannot be recovered.
public enum RedactionEngine {

    /// Scans an image or PDF and returns a summary of detected sensitive strings for preview in the Redact tool sheet.
    public static func previewMatches(in url: URL, options: RedactionOptions) async throws -> [String] {
        if url.pathExtension.lowercased() == "pdf" {
            guard let doc = PDFDocument(url: url) else { return [] }
            var found: [String] = []
            for i in 0..<doc.pageCount {
                guard let page = doc.page(at: i) else { continue }
                let pageText = page.string ?? ""
                if pageText.trimmingCharacters(in: .whitespacesAndNewlines).count >= 4 {
                    for range in matchingRanges(in: pageText, options: options) {
                        found.append(String(pageText[range]))
                    }
                } else if let cg = try? VisionOCREngine.shared.renderPDFPageToCGImage(page: page, scale: 2.0) {
                    let boxes = try await recognizeBoxes(in: cg, options: options)
                    found.append(contentsOf: boxes.map(\.matchedString))
                }
            }
            return Array(NSOrderedSet(array: found)) as? [String] ?? found
        } else {
            let cg = try ImageTransformer.loadOrientedCGImage(from: url)
            let boxes = try await recognizeBoxes(in: cg, options: options)
            let strings = boxes.map(\.matchedString)
            return Array(NSOrderedSet(array: strings)) as? [String] ?? strings
        }
    }

    /// Permanently burns black redaction rectangles over all matched sensitive tokens in an image or PDF.
    public static func applyRedaction(inputURL: URL, options: RedactionOptions) async throws -> RedactionResult {
        if inputURL.pathExtension.lowercased() == "pdf" {
            return try await redactPDF(inputURL: inputURL, options: options)
        } else {
            return try await redactImage(inputURL: inputURL, options: options)
        }
    }

    // MARK: - Image Redaction

    private static func redactImage(inputURL: URL, options: RedactionOptions) async throws -> RedactionResult {
        let cgImage = try ImageTransformer.loadOrientedCGImage(from: inputURL)
        let matches = try await recognizeBoxes(in: cgImage, options: options)
        let redactedCG = try drawRedactionBoxes(matches.map(\.normalizedRect), onto: cgImage)

        let outURL = OutputNaming.uniqueFileURL(nextTo: inputURL, suffix: "Redacted", newExtension: "png")
        try DocumentTools.writeCGImage(redactedCG, to: outURL, utType: UTType.png.identifier, quality: 1.0)
        return RedactionResult(outputURL: outURL, redactedCount: matches.count)
    }

    // MARK: - PDF Redaction (Burned-In Rasterized Pages for True Unrecoverable Redaction)

    private static func redactPDF(inputURL: URL, options: RedactionOptions) async throws -> RedactionResult {
        guard let doc = PDFDocument(url: inputURL), doc.pageCount > 0 else {
            throw FlipDocError("Failed to open PDF for redaction.")
        }

        let outDoc = PDFDocument()
        var totalRedacted = 0
        let scale: CGFloat = 3.0 // 216 DPI crisp raster burn-in

        for pageIndex in 0..<doc.pageCount {
            guard let page = doc.page(at: pageIndex) else { continue }
            let mediaBounds = page.bounds(for: .mediaBox)
            let renderedCG = try VisionOCREngine.shared.renderPDFPageToCGImage(page: page, scale: scale)

            // Collect normalized [0..1] rects (origin bottom-left) from both PDFKit character selection and Vision OCR
            var normalizedRects: [CGRect] = []
            let pageText = page.string ?? ""
            if pageText.trimmingCharacters(in: .whitespacesAndNewlines).count >= 4 {
                let ranges = matchingRanges(in: pageText, options: options)
                for range in ranges {
                    let nsRange = NSRange(range, in: pageText)
                    if let sel = page.selection(for: nsRange) {
                        let b = sel.bounds(for: page)
                        if b.width > 1 && b.height > 1 && mediaBounds.width > 0 && mediaBounds.height > 0 {
                            let norm = CGRect(
                                x: (b.minX - mediaBounds.minX) / mediaBounds.width,
                                y: (b.minY - mediaBounds.minY) / mediaBounds.height,
                                width: b.width / mediaBounds.width,
                                height: b.height / mediaBounds.height
                            )
                            normalizedRects.append(norm)
                            totalRedacted += 1
                        }
                    }
                }
            }

            if normalizedRects.isEmpty {
                let visionMatches = try await recognizeBoxes(in: renderedCG, options: options)
                normalizedRects.append(contentsOf: visionMatches.map(\.normalizedRect))
                totalRedacted += visionMatches.count
            }

            let burnedCG = try drawRedactionBoxes(normalizedRects, onto: renderedCG)
            let nsImage = NSImage(cgImage: burnedCG, size: mediaBounds.size)
            if let cleanPage = PDFPage(image: nsImage) {
                cleanPage.setBounds(mediaBounds, for: .mediaBox)
                outDoc.insert(cleanPage, at: outDoc.pageCount)
            }
        }

        outDoc.documentAttributes = [:]
        let outURL = OutputNaming.uniqueFileURL(nextTo: inputURL, suffix: "Redacted", newExtension: "pdf")
        guard outDoc.write(to: outURL) else {
            throw FlipDocError("Failed saving redacted PDF.")
        }
        return RedactionResult(outputURL: outURL, redactedCount: totalRedacted)
    }

    // MARK: - Vision Bounding Box Lookup

    private struct MatchedBox: Sendable {
        let matchedString: String
        /// Normalized `[0, 1]` rect in CoreGraphics/Vision coordinates (origin bottom-left).
        let normalizedRect: CGRect
    }

    private static func recognizeBoxes(in cgImage: CGImage, options: RedactionOptions) async throws -> [MatchedBox] {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: [])
                    return
                }

                var results: [MatchedBox] = []
                for obs in observations {
                    guard let candidate = obs.topCandidates(1).first else { continue }
                    let lineText = candidate.string
                    let ranges = matchingRanges(in: lineText, options: options)
                    for range in ranges {
                        let sub = String(lineText[range])
                        if let boxObs = try? candidate.boundingBox(for: range) {
                            results.append(MatchedBox(matchedString: sub, normalizedRect: boxObs.boundingBox))
                        } else {
                            results.append(MatchedBox(matchedString: sub, normalizedRect: obs.boundingBox))
                        }
                    }
                }
                continuation.resume(returning: results)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: - Pattern Matching (Emails, Phones, IDs/Cards, Amounts, Custom)

    public static func matchingRanges(in text: String, options: RedactionOptions) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []

        func addRegex(_ pattern: String, caseInsensitive: Bool = false) {
            var regOpts: NSRegularExpression.Options = []
            if caseInsensitive { regOpts.insert(.caseInsensitive) }
            guard let regex = try? NSRegularExpression(pattern: pattern, options: regOpts) else { return }
            let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
            for match in regex.matches(in: text, options: [], range: nsRange) {
                if let r = Range(match.range, in: text) {
                    ranges.append(r)
                }
            }
        }

        if options.redactEmails {
            addRegex("[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}")
        }

        if options.redactPhones {
            // International, US, and Indian phone patterns
            addRegex("(?:\\+?\\d{1,3}[\\s.-]?)?(?:\\(\\d{2,4}\\)|\\d{3,5})[\\s.-]\\d{3,5}(?:[\\s.-]\\d{3,5})?")
            if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.phoneNumber.rawValue) {
                let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
                for match in detector.matches(in: text, options: [], range: nsRange) where match.resultType == .phoneNumber {
                    if let r = Range(match.range, in: text) {
                        ranges.append(r)
                    }
                }
            }
        }

        if options.redactIDs {
            // 12-16 digit card / Aadhaar / account numbers, SSN (XXX-XX-XXXX), Indian PAN (ABCDE1234F)
            addRegex("\\b\\d{4}[\\s-]\\d{4}[\\s-]\\d{4}(?:[\\s-]\\d{4})?\\b")
            addRegex("\\b\\d{3}-\\d{2}-\\d{4}\\b")
            addRegex("\\b[A-Z]{5}\\d{4}[A-Z]\\b")
        }

        if options.redactAmounts {
            addRegex("(?:[$₹€£]|USD|INR|EUR)\\s?\\d[\\d,]*(?:\\.\\d{1,2})?")
        }

        for term in options.customTerms {
            let clean = term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { continue }
            let escaped = NSRegularExpression.escapedPattern(for: clean)
            addRegex(escaped, caseInsensitive: true)
        }

        return ranges
    }

    // MARK: - Permanent Pixel Burn-In

    private static func drawRedactionBoxes(_ normalizedRects: [CGRect], onto cgImage: CGImage) throws -> CGImage {
        let w = cgImage.width
        let h = cgImage.height
        let cs = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw FlipDocError("Failed creating redaction graphics context.")
        }

        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
        ctx.setFillColor(CGColor(srgbRed: 0.06, green: 0.07, blue: 0.09, alpha: 1.0))

        for norm in normalizedRects {
            let padX = max(4.0, CGFloat(w) * 0.004)
            let padY = max(3.0, CGFloat(h) * 0.004)
            let rect = CGRect(
                x: norm.minX * CGFloat(w) - padX,
                y: norm.minY * CGFloat(h) - padY,
                width: norm.width * CGFloat(w) + padX * 2,
                height: norm.height * CGFloat(h) + padY * 2
            )
            let rounded = CGPath(roundedRect: rect, cornerWidth: 4, cornerHeight: 4, transform: nil)
            ctx.addPath(rounded)
            ctx.fillPath()
        }

        guard let out = ctx.makeImage() else {
            throw FlipDocError("Failed finalizing redacted image.")
        }
        return out
    }
}

