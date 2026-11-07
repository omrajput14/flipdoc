import Foundation
import PDFKit
import Testing
@testable import FlipDocCore

@Suite("Document, Spreadsheet & Table Extraction Engines")
struct DocumentAndTableTests {

    @Test("XLSXtoPDFEngine + PDFTableExtractor round-trip preserves multi-word cells & >26 columns")
    func xlsxAndPDFTableRoundTrip() throws {
        #expect(PDFTableExtractor.excelColumnName(0) == "A")
        #expect(PDFTableExtractor.excelColumnName(25) == "Z")
        #expect(PDFTableExtractor.excelColumnName(26) == "AA")
        #expect(PDFTableExtractor.excelColumnName(27) == "AB")
        #expect(PDFTableExtractor.excelColumnName(51) == "AZ")
        #expect(PDFTableExtractor.excelColumnName(52) == "BA")

        let dir = try TestFixtures.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Test RFC-4180 CSV with quoted commas & multi-word strings
        let csvURL = dir.appendingPathComponent("sales.csv")
        let csvContent = """
        Product Name,Region,Revenue
        MacBook Pro 16,"North America, West","$4,999.00"
        Studio Display,"Europe, UK","$1,599.00"
        """
        try csvContent.write(to: csvURL, atomically: true, encoding: .utf8)

        let parsedCSV = try XLSXtoPDFEngine.parseDelimitedRows(inputURL: csvURL)
        #expect(parsedCSV.count == 3)
        #expect(parsedCSV[1] == ["MacBook Pro 16", "North America, West", "$4,999.00"])

        // Convert CSV -> XLSX -> Vector PDF -> Extract Tables back out
        let xlsxURL = try XLSXtoPDFEngine.convertSpreadsheet(inputURL: csvURL, to: "xlsx")
        #expect(FileManager.default.fileExists(atPath: xlsxURL.path))
        let reparsedXLSX = try XLSXtoPDFEngine.parseRows(from: xlsxURL)
        #expect(reparsedXLSX.count == 3)

        let pdfURL = try XLSXtoPDFEngine.convert(inputURL: xlsxURL)
        #expect(FileManager.default.fileExists(atPath: pdfURL.path))
        let pdfRawString = PDFDocument(url: pdfURL)?.string ?? ""
        #expect(pdfRawString.contains("MacBook"))

        let extracted = try PDFTableExtractor.extractTables(from: pdfURL)
        try #require(!extracted.isEmpty)
        #expect(extracted[0].rows.count == 3)
        #expect(extracted[0].rows[0] == ["Product Name", "Region", "Revenue"])
        #expect(extracted[0].rows[1] == ["MacBook Pro 16", "North America, West", "$4,999.00"])
        #expect(extracted[0].rows[2] == ["Studio Display", "Europe, UK", "$1,599.00"])
    }

    @Test("DocumentTools handles Subtitles, Archives, PDF Split/Merge/Compress, and Vision OCR")
    func documentToolsAndVisionOCR() async throws {
        let dir = try TestFixtures.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        // SRT -> VTT -> Transcript TXT
        let srt = dir.appendingPathComponent("demo.srt")
        try """
        1
        00:00:01,250 --> 00:00:03,500
        <i>Hello FlipDoc World</i>
        """.write(to: srt, atomically: true, encoding: .utf8)

        let vtt = try DocumentTools.convertSubtitles(inputURL: srt, targetFormat: "vtt")
        let vttText = try String(contentsOf: vtt, encoding: .utf8)
        #expect(vttText.hasPrefix("WEBVTT"))
        #expect(vttText.contains("00:00:01.250 --> 00:00:03.500"))

        let transcript = try DocumentTools.convertSubtitles(inputURL: vtt, targetFormat: "txt")
        let txtBody = try String(contentsOf: transcript, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(txtBody == "Hello FlipDoc World")

        // Archive ZIP + Extract
        let zipURL = try DocumentTools.createArchive(inputURLs: [srt, vtt], format: "zip")
        #expect(FileManager.default.fileExists(atPath: zipURL.path))
        let extractedDir = try DocumentTools.extractArchive(inputURL: zipURL)
        let extractedFiles = try FileManager.default.contentsOfDirectory(atPath: extractedDir.path)
        #expect(extractedFiles.contains("demo.srt"))

        // Vision OCR on generated text PNG and scanned image-only PDF
        let ocrImage = dir.appendingPathComponent("ocr_card.png")
        try TestFixtures.makeTestPNG(at: ocrImage, width: 640, height: 220, text: "FLIPDOC 2026")
        let recognizedImgText = try await VisionOCREngine.shared.recognizeText(from: ocrImage)
        #expect(recognizedImgText.uppercased().contains("FLIPDOC"))

        let scannedPDF = try ImageTransformer.combineImagesToPDF(inputURLs: [ocrImage])
        let recognizedPDFText = try await VisionOCREngine.shared.recognizeText(from: scannedPDF)
        #expect(recognizedPDFText.uppercased().contains("FLIPDOC"))

        // PDF Merge, Split & Compress
        let mergedPDF = try DocumentTools.mergePDFs(inputURLs: [scannedPDF, scannedPDF])
        #expect(PDFDocument(url: mergedPDF)?.pageCount == 2)

        let splitFolder = try DocumentTools.splitPDF(inputURL: mergedPDF)
        let splitPages = try FileManager.default.contentsOfDirectory(atPath: splitFolder.path)
        #expect(splitPages.count == 2)

        let compressedPDF = try DocumentTools.compressPDF(inputURL: mergedPDF, quality: 0.55)
        #expect(PDFDocument(url: compressedPDF)?.pageCount == 2)
    }
}
