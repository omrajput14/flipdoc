import Foundation
import AppKit
import CoreText
import PDFKit
import ImageIO
import UniformTypeIdentifiers

public enum DocumentTools {

    // MARK: - PDF Page Export (PNG / JPG at 300 DPI)

    /// Exports PDF pages as high-DPI images. Single-page PDFs save beside original; multi-page PDFs create `<Name> Pages/`.
    public static func pdfToImages(inputURL: URL, format: String = "png") throws -> URL {
        guard let doc = PDFDocument(url: inputURL), doc.pageCount > 0 else {
            throw FlipDocError("Failed to open PDF \(inputURL.lastPathComponent).")
        }
        let isJPEG = format.lowercased() == "jpg" || format.lowercased() == "jpeg"
        let ext = isJPEG ? "jpg" : "png"
        let utType = isJPEG ? UTType.jpeg.identifier : UTType.png.identifier
        let scale: CGFloat = 300.0 / 72.0 // Crisp 300 DPI print-grade rasterization

        if doc.pageCount == 1, let page = doc.page(at: 0) {
            let cg = try VisionOCREngine.shared.renderPDFPageToCGImage(page: page, scale: scale)
            let outURL = OutputNaming.uniqueFileURL(nextTo: inputURL, newExtension: ext)
            try writeCGImage(cg, to: outURL, utType: utType, quality: 0.94)
            return outURL
        }

        let folder = try OutputNaming.uniqueDirectoryURL(nextTo: inputURL, suffix: "Pages")
        let base = OutputNaming.baseName(for: inputURL)
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            let cg = try VisionOCREngine.shared.renderPDFPageToCGImage(page: page, scale: scale)
            let pageName = String(format: "%@ Page %02d.%@", base, i + 1, ext)
            let pageURL = folder.appendingPathComponent(pageName)
            try writeCGImage(cg, to: pageURL, utType: utType, quality: 0.94)
        }
        return folder
    }

    internal static func writeCGImage(_ cg: CGImage, to url: URL, utType: String, quality: Double) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, utType as CFString, 1, nil) else {
            throw FlipDocError("Could not create image writer.")
        }
        let props: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality,
            kCGImageDestinationEmbedThumbnail: false
        ]
        CGImageDestinationAddImage(dest, cg, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            throw FlipDocError("Failed writing page image.")
        }
    }

    // MARK: - PDF Text & Document Exports

    public static func pdfToPlainText(inputURL: URL) async throws -> URL {
        guard let doc = PDFDocument(url: inputURL) else {
            throw FlipDocError("Failed to open PDF.")
        }
        var text = (doc.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if text.count < 10 {
            text = try await VisionOCREngine.shared.recognizeText(from: inputURL)
        }
        let outURL = OutputNaming.uniqueFileURL(nextTo: inputURL, newExtension: "txt")
        try text.write(to: outURL, atomically: true, encoding: .utf8)
        return outURL
    }

    /// Converts PDF or Text/Rich-Text documents into `.docx`, `.rtf`, or `.html` via macOS `/usr/bin/textutil` (with OCR fallback for scanned PDFs).
    public static func convertViaTextutil(inputURL: URL, targetFormat: String) async throws -> URL {
        let ext = targetFormat.lowercased()
        let outURL = OutputNaming.uniqueFileURL(nextTo: inputURL, newExtension: ext)
        var tempSource: URL? = nil
        defer {
            if let t = tempSource { try? FileManager.default.removeItem(at: t) }
        }

        let sourcePath: String
        if inputURL.pathExtension.lowercased() == "pdf" {
            let doc = PDFDocument(url: inputURL)
            var extracted = (doc?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if extracted.count < 10 {
                extracted = try await VisionOCREngine.shared.recognizeText(from: inputURL)
            }
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
            try extracted.write(to: tmp, atomically: true, encoding: .utf8)
            tempSource = tmp
            sourcePath = tmp.path
        } else {
            sourcePath = inputURL.path
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/textutil")
        proc.arguments = ["-convert", ext, sourcePath, "-output", outURL.path]
        try proc.run()
        proc.waitUntilExit()

        guard proc.terminationStatus == 0, FileManager.default.fileExists(atPath: outURL.path) else {
            throw FlipDocError("Document conversion to \(ext.uppercased()) failed.")
        }
        return outURL
    }

    public static func documentToPlainOrMarkdown(inputURL: URL, asMarkdown: Bool) throws -> URL {
        let outExt = asMarkdown ? "md" : "txt"
        let outURL = OutputNaming.uniqueFileURL(nextTo: inputURL, newExtension: outExt)
        let inputExt = inputURL.pathExtension.lowercased()

        if ["txt", "md", "markdown"].contains(inputExt) {
            let raw = try String(contentsOf: inputURL, encoding: .utf8)
            if asMarkdown && inputExt == "txt" {
                let title = OutputNaming.baseName(for: inputURL)
                try "# \(title)\n\n\(raw)\n".write(to: outURL, atomically: true, encoding: .utf8)
            } else {
                try raw.write(to: outURL, atomically: true, encoding: .utf8)
            }
            return outURL
        }

        let tempTxt = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        defer { try? FileManager.default.removeItem(at: tempTxt) }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/textutil")
        proc.arguments = ["-convert", "txt", inputURL.path, "-output", tempTxt.path]
        try proc.run()
        proc.waitUntilExit()

        let text = (try? String(contentsOf: tempTxt, encoding: .utf8)) ?? ""
        if asMarkdown {
            let title = OutputNaming.baseName(for: inputURL)
            let paragraphs = text.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n")
            try "# \(title)\n\n\(paragraphs)\n".write(to: outURL, atomically: true, encoding: .utf8)
        } else {
            try text.write(to: outURL, atomically: true, encoding: .utf8)
        }
        return outURL
    }

    /// Creates a vector/rich PDF from Images, Spreadsheets, or Text/Word/RTF/Markdown/HTML documents.
    public static func createPDF(from inputURLs: [URL]) throws -> URL {
        guard let first = inputURLs.first else {
            throw FlipDocError("No input files provided.")
        }
        if inputURLs.allSatisfy({ FileCategory.classify(url: $0) == .image }) {
            return try ImageTransformer.combineImagesToPDF(inputURLs: inputURLs)
        }

        let ext = first.pathExtension.lowercased()
        let outURL = OutputNaming.uniqueFileURL(nextTo: first, newExtension: "pdf")

        if ["xlsx", "xls"].contains(ext) {
            return try XLSXtoPDFEngine.convert(inputURL: first, outputURL: outURL)
        } else if ["csv", "tsv"].contains(ext) {
            return try XLSXtoPDFEngine.convertDelimited(inputURL: first, outputURL: outURL)
        } else if FileCategory.documentExtensions.contains(ext) {
            // Render attributed string cleanly to paginated A4 PDF using CoreText
            let attrString: NSAttributedString
            if ["txt", "md", "markdown"].contains(ext),
               let raw = try? String(contentsOf: first, encoding: .utf8) {
                let para = NSMutableParagraphStyle()
                para.lineSpacing = 4
                para.paragraphSpacing = 8
                attrString = NSAttributedString(
                    string: raw,
                    attributes: [
                        .font: NSFont.systemFont(ofSize: 11.5),
                        .foregroundColor: NSColor.black,
                        .paragraphStyle: para
                    ]
                )
            } else if let loaded = try? NSAttributedString(url: first, options: [:], documentAttributes: nil) {
                attrString = loaded
            } else {
                throw FlipDocError("Unable to read document \(first.lastPathComponent).")
            }
            return try renderAttributedStringToPDF(attrString, outputURL: outURL)
        }

        throw FlipDocError("Conversion to PDF is not supported for .\(ext) files.")
    }

    private static func renderAttributedStringToPDF(_ attrString: NSAttributedString, outputURL: URL) throws -> URL {
        let pageW: CGFloat = 595.28
        let pageH: CGFloat = 841.89
        let margin: CGFloat = 50.0
        var mediaBox = CGRect(x: 0, y: 0, width: pageW, height: pageH)

        guard let ctx = CGContext(outputURL as CFURL, mediaBox: &mediaBox, nil) else {
            throw FlipDocError("Failed creating PDF graphics context.")
        }

        let framesetter = CTFramesetterCreateWithAttributedString(attrString as CFAttributedString)
        let textRect = CGRect(x: margin, y: margin, width: pageW - margin * 2, height: pageH - margin * 2)
        let path = CGPath(rect: textRect, transform: nil)

        var currentIndex: CFIndex = 0
        let totalLength = attrString.length

        repeat {
            ctx.beginPage(mediaBox: &mediaBox)
            let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(currentIndex, 0), path, nil)
            CTFrameDraw(frame, ctx)
            ctx.endPage()

            let visibleRange = CTFrameGetVisibleStringRange(frame)
            currentIndex += max(1, visibleRange.length)
        } while currentIndex < totalLength

        ctx.closePDF()
        return outputURL
    }

    // MARK: - PDF Tools (Split, Merge, Organize, Compress, Metadata)

    /// Splits a PDF into individual pages inside `<Name> Pages/` folder.
    public static func splitPDF(inputURL: URL) throws -> URL {
        guard let doc = PDFDocument(url: inputURL), doc.pageCount > 0 else {
            throw FlipDocError("Failed to open PDF.")
        }
        let folder = try OutputNaming.uniqueDirectoryURL(nextTo: inputURL, suffix: "Pages")
        let base = OutputNaming.baseName(for: inputURL)

        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            let singleDoc = PDFDocument()
            if let copied = page.copy() as? PDFPage {
                singleDoc.insert(copied, at: 0)
            } else {
                singleDoc.insert(page, at: 0)
            }
            let name = String(format: "%@ Page %02d.pdf", base, i + 1)
            singleDoc.write(to: folder.appendingPathComponent(name))
        }
        return folder
    }

    /// Combines multiple PDFs in order into a single merged PDF.
    public static func mergePDFs(inputURLs: [URL]) throws -> URL {
        guard let first = inputURLs.first else {
            throw FlipDocError("No PDFs selected to merge.")
        }
        let merged = PDFDocument()
        var insertIndex = 0

        for url in inputURLs {
            guard let doc = PDFDocument(url: url) else { continue }
            for p in 0..<doc.pageCount {
                if let page = doc.page(at: p)?.copy() as? PDFPage {
                    merged.insert(page, at: insertIndex)
                    insertIndex += 1
                }
            }
        }
        guard insertIndex > 0 else {
            throw FlipDocError("Could not read pages from the selected PDFs.")
        }
        let outURL = OutputNaming.uniqueFileURL(nextTo: first, suffix: "Merged", newExtension: "pdf")
        guard merged.write(to: outURL) else {
            throw FlipDocError("Failed writing merged PDF.")
        }
        return outURL
    }

    /// Compresses a PDF by downsampling heavy pages with JPEG compression when smaller than lossless rewrite,
    /// with optional strict `targetMaxBytes` portal limit (`< 200 KB`, `< 500 KB`, `< 1 MB`, `< 2 MB`).
    public static func compressPDF(inputURL: URL, quality: Double = 0.65, targetMaxBytes: Int64? = nil) throws -> URL {
        guard let doc = PDFDocument(url: inputURL), doc.pageCount > 0 else {
            throw FlipDocError("Failed to open PDF.")
        }
        let outURL = OutputNaming.uniqueFileURL(nextTo: inputURL, suffix: "Compressed", newExtension: "pdf")
        let originalBytes = (try? FileManager.default.attributesOfItem(atPath: inputURL.path)[.size] as? Int) ?? Int.max

        // First write optimized lossless PDFKit stream to a temp file
        let losslessTemp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: losslessTemp) }
        doc.write(to: losslessTemp)
        let losslessBytes = (try? FileManager.default.attributesOfItem(atPath: losslessTemp.path)[.size] as? Int) ?? Int.max

        func buildRasterPDF(dpiScale: CGFloat, jpegQuality: Double, to destURL: URL) -> Int {
            let compressedDoc = PDFDocument()
            for i in 0..<doc.pageCount {
                guard let page = doc.page(at: i),
                      let cg = try? VisionOCREngine.shared.renderPDFPageToCGImage(page: page, scale: dpiScale) else { continue }
                let data = NSMutableData()
                if let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) {
                    let props: [CFString: Any] = [
                        kCGImageDestinationLossyCompressionQuality: max(0.16, min(0.92, jpegQuality)),
                        kCGImageDestinationEmbedThumbnail: false
                    ]
                    CGImageDestinationAddImage(dest, cg, props as CFDictionary)
                    CGImageDestinationFinalize(dest)
                    if let jpgImg = NSImage(data: data as Data), let newPage = PDFPage(image: jpgImg) {
                        newPage.setBounds(page.bounds(for: .mediaBox), for: .mediaBox)
                        compressedDoc.insert(newPage, at: compressedDoc.pageCount)
                    }
                }
            }
            guard compressedDoc.pageCount == doc.pageCount else { return Int.max }
            compressedDoc.write(to: destURL)
            return (try? FileManager.default.attributesOfItem(atPath: destURL.path)[.size] as? Int) ?? Int.max
        }

        // If a strict portal byte limit is requested, step down DPI & JPEG quality until under limit
        if let maxBytes = targetMaxBytes, maxBytes > 0 {
            if Int64(losslessBytes) <= maxBytes {
                try FileManager.default.copyItem(at: losslessTemp, to: outURL)
                return outURL
            }
            let candidates: [(CGFloat, Double)] = [
                (1.75, 0.65),
                (1.40, 0.52),
                (1.10, 0.42),
                (0.85, 0.34),
                (0.65, 0.25),
                (0.50, 0.18)
            ]
            var smallestTemp: URL? = nil
            var smallestSize = losslessBytes

            defer {
                if let s = smallestTemp { try? FileManager.default.removeItem(at: s) }
            }

            for (scale, q) in candidates {
                let candidateTemp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
                let bytes = buildRasterPDF(dpiScale: scale, jpegQuality: q, to: candidateTemp)
                if bytes < smallestSize {
                    if let old = smallestTemp { try? FileManager.default.removeItem(at: old) }
                    smallestTemp = candidateTemp
                    smallestSize = bytes
                } else {
                    try? FileManager.default.removeItem(at: candidateTemp)
                }
                if Int64(bytes) <= maxBytes {
                    break
                }
            }

            let winner = smallestTemp ?? losslessTemp
            try FileManager.default.copyItem(at: winner, to: outURL)
            return outURL
        }

        // Standard quality slider mode
        let rasterTemp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: rasterTemp) }
        let dpiScale: CGFloat = quality > 0.75 ? 2.2 : (quality > 0.45 ? 1.75 : 1.35)
        let rasterBytes = buildRasterPDF(dpiScale: dpiScale, jpegQuality: quality, to: rasterTemp)

        // Pick whichever valid output actually achieves smaller size without inflating pure-vector text PDFs
        let bestSource = (rasterBytes < losslessBytes && rasterBytes < originalBytes) ? rasterTemp : losslessTemp
        try FileManager.default.copyItem(at: bestSource, to: outURL)
        return outURL
    }

    public static func stripPDFMetadata(inputURL: URL) throws -> URL {
        guard let doc = PDFDocument(url: inputURL) else {
            throw FlipDocError("Failed to open PDF.")
        }
        doc.documentAttributes = [:]
        let outURL = OutputNaming.uniqueFileURL(nextTo: inputURL, suffix: "No Metadata", newExtension: "pdf")
        guard doc.write(to: outURL) else {
            throw FlipDocError("Failed saving cleaned PDF.")
        }
        return outURL
    }

    /// Applies a diagonal vector watermark stamp (`CONFIDENTIAL`, `DRAFT`, `APPROVED`, or custom text)
    /// and/or encrypts the PDF with a user password (`LOCK PDF`).
    public static func protectAndWatermarkPDF(
        inputURL: URL,
        userPassword: String? = nil,
        ownerPassword: String? = nil,
        watermarkText: String? = nil,
        watermarkOpacity: Double = 0.18
    ) throws -> URL {
        guard let doc = PDFDocument(url: inputURL), doc.pageCount > 0 else {
            throw FlipDocError("Failed to open PDF.")
        }

        let cleanPassword = userPassword?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let cleanStamp = watermarkText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasPassword = !cleanPassword.isEmpty
        let hasStamp = !cleanStamp.isEmpty

        let suffix: String
        if hasPassword && hasStamp {
            suffix = "Protected"
        } else if hasPassword {
            suffix = "Locked"
        } else {
            suffix = "Stamped"
        }
        let outURL = OutputNaming.uniqueFileURL(nextTo: inputURL, suffix: suffix, newExtension: "pdf")

        var auxInfo: [CFString: Any] = [:]
        if hasPassword {
            auxInfo[kCGPDFContextUserPassword] = cleanPassword
            auxInfo[kCGPDFContextOwnerPassword] = (ownerPassword?.isEmpty == false) ? ownerPassword! : cleanPassword
        }

        var defaultBox = doc.page(at: 0)?.bounds(for: .mediaBox) ?? CGRect(x: 0, y: 0, width: 595.28, height: 841.89)
        guard let ctx = CGContext(outURL as CFURL, mediaBox: &defaultBox, auxInfo as CFDictionary) else {
            throw FlipDocError("Failed creating protected PDF context.")
        }

        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            var pageBox = page.bounds(for: .mediaBox)
            ctx.beginPage(mediaBox: &pageBox)

            // Draw original vector PDF page
            ctx.saveGState()
            page.draw(with: .mediaBox, to: ctx)
            ctx.restoreGState()

            // Draw diagonal vector stamp if requested
            if hasStamp {
                ctx.saveGState()
                ctx.translateBy(x: pageBox.midX, y: pageBox.midY)
                ctx.rotate(by: -34.0 * .pi / 180.0)

                let maxSpan = hypot(pageBox.width, pageBox.height) * 0.68
                let baseFontSize = min(68.0, max(28.0, maxSpan / CGFloat(max(5, cleanStamp.count)) * 1.45))
                let font = NSFont.boldSystemFont(ofSize: baseFontSize)
                let alpha = CGFloat(max(0.06, min(0.65, watermarkOpacity)))
                let stampColor = NSColor(srgbRed: 0.85, green: 0.16, blue: 0.12, alpha: alpha)

                let attr = NSAttributedString(
                    string: cleanStamp.uppercased(),
                    attributes: [
                        .font: font,
                        .foregroundColor: stampColor,
                        .kern: 3.0
                    ]
                )
                let line = CTLineCreateWithAttributedString(attr)
                let bounds = CTLineGetBoundsWithOptions(line, [])

                // Outer stamp frame
                let padX: CGFloat = 22
                let padY: CGFloat = 12
                let frameRect = CGRect(
                    x: -bounds.width / 2 - padX,
                    y: -bounds.height / 2 - padY,
                    width: bounds.width + padX * 2,
                    height: bounds.height + padY * 2
                )
                let borderPath = CGPath(roundedRect: frameRect, cornerWidth: 10, cornerHeight: 10, transform: nil)
                ctx.addPath(borderPath)
                ctx.setStrokeColor(stampColor.cgColor)
                ctx.setLineWidth(3.0)
                ctx.strokePath()

                ctx.textPosition = CGPoint(x: -bounds.width / 2, y: -bounds.height / 2 - bounds.origin.y * 0.35)
                CTLineDraw(line, ctx)
                ctx.restoreGState()
            }

            ctx.endPage()
        }

        ctx.closePDF()
        return outURL
    }

    /// Generates a 3-Up Lecture / Study Handout PDF (`<Name> Handout.pdf`) with slide thumbnails on the left
    /// and ruled note-taking lines on the right for iPad (GoodNotes/Notability) or printing.
    public static func createStudyHandoutPDF(inputURL: URL, slidesPerPage: Int = 3) throws -> URL {
        guard let doc = PDFDocument(url: inputURL), doc.pageCount > 0 else {
            throw FlipDocError("Failed to open PDF for handout generation.")
        }

        let perPage = max(2, min(4, slidesPerPage))
        let outURL = OutputNaming.uniqueFileURL(nextTo: inputURL, suffix: "Handout", newExtension: "pdf")
        let title = OutputNaming.baseName(for: inputURL)

        let pageW: CGFloat = 595.28 // A4 Portrait
        let pageH: CGFloat = 841.89
        let margin: CGFloat = 36.0
        let headerH: CGFloat = 38.0
        var mediaBox = CGRect(x: 0, y: 0, width: pageW, height: pageH)

        guard let ctx = CGContext(outURL as CFURL, mediaBox: &mediaBox, nil) else {
            throw FlipDocError("Failed creating handout PDF context.")
        }

        let totalHandoutPages = Int(ceil(Double(doc.pageCount) / Double(perPage)))
        let usableTop = pageH - margin - headerH
        let usableHeight = usableTop - margin
        let slotGap: CGFloat = 18.0
        let slotHeight = (usableHeight - slotGap * CGFloat(perPage - 1)) / CGFloat(perPage)

        func drawText(_ s: String, x: CGFloat, y: CGFloat, size: CGFloat, bold: Bool = false, color: NSColor = .black) {
            let font = bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size, weight: .medium)
            let attr = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color])
            ctx.textPosition = CGPoint(x: x, y: y)
            CTLineDraw(CTLineCreateWithAttributedString(attr), ctx)
        }

        for handoutPage in 0..<totalHandoutPages {
            ctx.beginPage(mediaBox: &mediaBox)

            // White canvas
            ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
            ctx.fill(mediaBox)

            // Header bar
            let headerY = pageH - margin - 16
            drawText(title, x: margin, y: headerY, size: 13, bold: true, color: NSColor(srgbRed: 0.12, green: 0.13, blue: 0.15, alpha: 1))
            let rightLabel = "Study Handout  •  Page \(handoutPage + 1) of \(totalHandoutPages)"
            drawText(rightLabel, x: pageW - margin - 175, y: headerY, size: 10, bold: false, color: .gray)

            ctx.setStrokeColor(CGColor(srgbRed: 0.88, green: 0.89, blue: 0.90, alpha: 1))
            ctx.setLineWidth(1.0)
            ctx.move(to: CGPoint(x: margin, y: pageH - margin - 26))
            ctx.addLine(to: CGPoint(x: pageW - margin, y: pageH - margin - 26))
            ctx.strokePath()

            for slot in 0..<perPage {
                let slideIdx = handoutPage * perPage + slot
                guard slideIdx < doc.pageCount, let slidePage = doc.page(at: slideIdx) else { break }

                let slotTop = usableTop - CGFloat(slot) * (slotHeight + slotGap)
                let slotBottom = slotTop - slotHeight

                // Left column: Slide Box (46% of content width)
                let contentW = pageW - margin * 2
                let slideColW = contentW * 0.46
                let badgeSpace: CGFloat = 18.0
                let boxMaxH = slotHeight - badgeSpace
                let srcBounds = slidePage.bounds(for: .mediaBox)
                let srcW = max(1.0, srcBounds.width)
                let srcH = max(1.0, srcBounds.height)
                let scale = min(slideColW / srcW, boxMaxH / srcH)
                let drawW = srcW * scale
                let drawH = srcH * scale
                let drawX = margin + (slideColW - drawW) / 2.0
                let drawY = slotBottom + badgeSpace + (boxMaxH - drawH) / 2.0
                let slideRect = CGRect(x: drawX, y: drawY, width: drawW, height: drawH)

                // Subtle shadow & border around slide
                ctx.saveGState()
                ctx.setFillColor(CGColor(srgbRed: 0.985, green: 0.985, blue: 0.99, alpha: 1))
                ctx.fill(slideRect)
                ctx.clip(to: slideRect)
                ctx.translateBy(x: drawX - srcBounds.minX * scale, y: drawY - srcBounds.minY * scale)
                ctx.scaleBy(x: scale, y: scale)
                slidePage.draw(with: .mediaBox, to: ctx)
                ctx.restoreGState()

                ctx.setStrokeColor(CGColor(srgbRed: 0.78, green: 0.80, blue: 0.83, alpha: 1))
                ctx.setLineWidth(0.9)
                ctx.stroke(slideRect)

                // Slide number caption beneath thumbnail
                drawText(
                    "Slide \(slideIdx + 1) of \(doc.pageCount)",
                    x: drawX,
                    y: drawY - 13,
                    size: 9.0,
                    bold: true,
                    color: NSColor(srgbRed: 1.0, green: 0.322, blue: 0.0, alpha: 1)
                )

                // Right column: Ruled Note-Taking Lines (50% of content width)
                let notesX = margin + slideColW + 20.0
                let notesW = pageW - margin - notesX
                let lineCount = 8
                let topLineY = slotTop - 16.0
                let bottomLineY = slotBottom + 14.0
                let lineStep = (topLineY - bottomLineY) / CGFloat(max(1, lineCount - 1))

                drawText(
                    "KEY NOTES & ACTION ITEMS",
                    x: notesX,
                    y: slotTop - 4,
                    size: 8.0,
                    bold: true,
                    color: NSColor(srgbRed: 0.55, green: 0.57, blue: 0.60, alpha: 1)
                )

                ctx.setStrokeColor(CGColor(srgbRed: 0.85, green: 0.87, blue: 0.90, alpha: 1))
                ctx.setLineWidth(0.75)
                for l in 0..<lineCount {
                    let ly = topLineY - CGFloat(l) * lineStep
                    ctx.move(to: CGPoint(x: notesX, y: ly))
                    ctx.addLine(to: CGPoint(x: notesX + notesW, y: ly))
                }
                ctx.strokePath()
            }

            ctx.endPage()
        }

        ctx.closePDF()
        return outURL
    }

    // MARK: - Subtitles (SRT <-> VTT & Transcript)

    public static func convertSubtitles(inputURL: URL, targetFormat: String) throws -> URL {
        let raw = (try? String(contentsOf: inputURL, encoding: .utf8))
            ?? (try? String(contentsOf: inputURL, encoding: .isoLatin1))
            ?? ""
        let target = targetFormat.lowercased()
        let outURL = OutputNaming.uniqueFileURL(nextTo: inputURL, newExtension: target)

        if target == "vtt" {
            var body = raw.replacingOccurrences(of: "\r\n", with: "\n")
            // Convert SRT timestamp commas 00:01:23,450 --> 00:01:25,800 to dots
            body = body.replacingOccurrences(
                of: "(\\d{2}:\\d{2}:\\d{2}),(\\d{3})",
                with: "$1.$2",
                options: .regularExpression
            )
            if !body.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("WEBVTT") {
                body = "WEBVTT\n\n" + body.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
            }
            try body.write(to: outURL, atomically: true, encoding: .utf8)
            return outURL
        } else if target == "srt" {
            var lines = raw.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
            if let first = lines.first, first.hasPrefix("WEBVTT") {
                lines.removeFirst()
            }
            let joined = lines.joined(separator: "\n")
                .replacingOccurrences(
                    of: "(\\d{2}:\\d{2}:\\d{2})\\.(\\d{3})",
                    with: "$1,$2",
                    options: .regularExpression
                )
                .trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
            try joined.write(to: outURL, atomically: true, encoding: .utf8)
            return outURL
        } else {
            // Plain transcript TXT: strip cue indices, WEBVTT header, timestamps, and HTML tags
            let lines = raw.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
            var spoken: [String] = []
            for line in lines {
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.isEmpty || t.hasPrefix("WEBVTT") || t.hasPrefix("NOTE") { continue }
                if Int(t) != nil { continue }
                if t.contains("-->") { continue }
                let clean = t.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                if !clean.isEmpty { spoken.append(clean) }
            }
            try (spoken.joined(separator: "\n") + "\n").write(to: outURL, atomically: true, encoding: .utf8)
            return outURL
        }
    }

    // MARK: - Archives (ZIP / TAR / TAR.GZ / Extract)

    public static func createArchive(inputURLs: [URL], format: String) throws -> URL {
        guard let first = inputURLs.first else {
            throw FlipDocError("No files selected to archive.")
        }
        let fmt = format.lowercased()
        let baseSource = inputURLs.count == 1 ? first : first.deletingLastPathComponent().appendingPathComponent("Archive.tmp")

        if fmt == "zip" {
            let outURL = OutputNaming.uniqueFileURL(nextTo: baseSource, newExtension: "zip")
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
            let commonDir = first.deletingLastPathComponent()
            proc.currentDirectoryURL = commonDir
            let relNames = inputURLs.map { $0.lastPathComponent }
            proc.arguments = ["-q", "-r", outURL.path] + relNames
            try proc.run()
            proc.waitUntilExit()
            guard proc.terminationStatus == 0 else {
                throw FlipDocError("Failed creating ZIP archive.")
            }
            return outURL
        } else {
            let isGzip = (fmt == "gz" || fmt == "tgz" || fmt == "tar.gz")
            let outURL = OutputNaming.uniqueFileURL(nextTo: baseSource, newExtension: isGzip ? "tar.gz" : "tar")

            // If input is a single existing archive (.zip), unpack to temp first so archive-to-archive conversion works cleanly
            var stagingDir: URL? = nil
            defer { if let s = stagingDir { try? FileManager.default.removeItem(at: s) } }

            let workDir: URL
            let itemNames: [String]
            if inputURLs.count == 1 && FileCategory.classify(url: first) == .archive {
                let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
                stagingDir = tmp
                try unpackArchive(first, into: tmp)
                workDir = tmp
                itemNames = (try? FileManager.default.contentsOfDirectory(atPath: tmp.path)) ?? []
            } else {
                workDir = first.deletingLastPathComponent()
                itemNames = inputURLs.map { $0.lastPathComponent }
            }

            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
            proc.currentDirectoryURL = workDir
            proc.arguments = [isGzip ? "-czf" : "-cf", outURL.path] + itemNames
            try proc.run()
            proc.waitUntilExit()
            guard proc.terminationStatus == 0 else {
                throw FlipDocError("Failed creating \(isGzip ? "TAR.GZ" : "TAR") archive.")
            }
            return outURL
        }
    }

    public static func extractArchive(inputURL: URL) throws -> URL {
        let destFolder = try OutputNaming.uniqueDirectoryURL(nextTo: inputURL, suffix: "Extracted")
        try unpackArchive(inputURL, into: destFolder)
        return destFolder
    }

    private static func unpackArchive(_ archiveURL: URL, into destination: URL) throws {
        let lower = archiveURL.lastPathComponent.lowercased()
        let proc = Process()
        if lower.hasSuffix(".zip") {
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            proc.arguments = ["-x", "-k", archiveURL.path, destination.path]
        } else {
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
            proc.arguments = ["-xf", archiveURL.path, "-C", destination.path]
        }
        try proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            throw FlipDocError("Failed extracting archive \(archiveURL.lastPathComponent).")
        }
    }
}
