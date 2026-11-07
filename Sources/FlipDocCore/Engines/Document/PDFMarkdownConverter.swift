import Foundation
import PDFKit

public enum PDFMarkdownConverter {
    /// Converts a PDF to structured Markdown, automatically falling back to Apple Vision OCR on scanned pages.
    public static func convert(inputURL: URL) async throws -> URL {
        guard let doc = PDFDocument(url: inputURL) else {
            throw FlipDocError("Failed to load PDF document \(inputURL.lastPathComponent).")
        }

        let title = OutputNaming.baseName(for: inputURL)
        var markdown = "# \(title)\n\n"
        let pageCount = doc.pageCount

        for i in 0..<pageCount {
            guard let page = doc.page(at: i) else { continue }
            if pageCount > 1 {
                markdown += "## Page \(i + 1)\n\n"
            }

            let rawText = (page.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let effectiveText: String
            if rawText.count >= 12 {
                effectiveText = rawText
            } else {
                // Scanned PDF page fallback via local Apple Vision OCR!
                let cg = try VisionOCREngine.shared.renderPDFPageToCGImage(page: page, scale: 2.75)
                effectiveText = try await VisionOCREngine.shared.recognizeCGImage(cg)
            }

            let lines = effectiveText
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }

            if !lines.isEmpty {
                markdown += lines.joined(separator: "\n\n") + "\n\n"
            }
            if pageCount > 1 && i < pageCount - 1 {
                markdown += "---\n\n"
            }
        }

        let outputURL = OutputNaming.uniqueFileURL(nextTo: inputURL, newExtension: "md")
        try markdown.write(to: outputURL, atomically: true, encoding: .utf8)
        return outputURL
    }
}

