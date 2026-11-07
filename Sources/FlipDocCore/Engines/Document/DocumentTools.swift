import Foundation
import AppKit
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

    /// Compresses a PDF by downsampling heavy pages with JPEG compression when smaller than lossless rewrite.
    public static func compressPDF(inputURL: URL, quality: Double = 0.65) throws -> URL {
        guard let doc = PDFDocument(url: inputURL), doc.pageCount > 0 else {
            throw FlipDocError("Failed to open PDF.")
        }
        let outURL = OutputNaming.uniqueFileURL(nextTo: inputURL, suffix: "Compressed", newExtension: "pdf")
        let originalBytes = (try? FileManager.default.attributesOfItem(atPath: inputURL.path)[.size] as? Int) ?? Int.max

        // First write optimized lossless PDFKit stream to a temp file
        let losslessTemp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: losslessTemp) }
        doc.write(to: losslessTemp)

        // Also build a raster-compressed PDF at adaptive DPI for image-heavy scans
        let rasterTemp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: rasterTemp) }

        let dpiScale: CGFloat = quality > 0.75 ? 2.2 : (quality > 0.45 ? 1.75 : 1.35)
        let compressedDoc = PDFDocument()
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i),
                  let cg = try? VisionOCREngine.shared.renderPDFPageToCGImage(page: page, scale: dpiScale) else { continue }
            let data = NSMutableData()
            if let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) {
                let props: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: max(0.25, min(0.92, quality))]
                CGImageDestinationAddImage(dest, cg, props as CFDictionary)
                CGImageDestinationFinalize(dest)
                if let jpgImg = NSImage(data: data as Data), let newPage = PDFPage(image: jpgImg) {
                    newPage.setBounds(page.bounds(for: .mediaBox), for: .mediaBox)
                    compressedDoc.insert(newPage, at: compressedDoc.pageCount)
                }
            }
        }
        compressedDoc.write(to: rasterTemp)

        let losslessBytes = (try? FileManager.default.attributesOfItem(atPath: losslessTemp.path)[.size] as? Int) ?? Int.max
        let rasterBytes = (try? FileManager.default.attributesOfItem(atPath: rasterTemp.path)[.size] as? Int) ?? Int.max

        // Pick whichever valid output actually achieves smaller size without inflating pure-vector text PDFs
        let bestSource: URL
        if rasterBytes < losslessBytes && rasterBytes < originalBytes && compressedDoc.pageCount == doc.pageCount {
            bestSource = rasterTemp
        } else {
            bestSource = losslessTemp
        }
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
