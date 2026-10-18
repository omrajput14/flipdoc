import Foundation
import PDFKit

public enum PDFMarkdownConverter {
    public static func convert(inputURL: URL) throws -> URL {
        guard let doc = PDFDocument(url: inputURL) else {
            throw NSError(domain: "FlipDoc", code: 5, userInfo: [NSLocalizedDescriptionKey: "Failed to load PDF document."])
        }
        
        var markdown = "# \(inputURL.deletingPathExtension().lastPathComponent)\n\n"
        let pageCount = doc.pageCount
        
        for i in 0..<pageCount {
            guard let page = doc.page(at: i) else { continue }
            markdown += "## Page \(i + 1)\n\n"
            if let pageText = page.string {
                // Normalize line breaks and spaces
                let cleaned = pageText
                    .split(separator: "\n")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n\n")
                markdown += cleaned + "\n\n---\n\n"
            }
        }
        
        let outputURL = inputURL.deletingPathExtension().appendingPathExtension("md")
        try markdown.write(to: outputURL, atomically: true, encoding: .utf8)
        return outputURL
    }
}
