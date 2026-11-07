import Foundation
import PDFKit

public struct ExtractedTable: Sendable, Equatable {
    public let page: Int
    public let rows: [[String]]

    public init(page: Int, rows: [[String]]) {
        self.page = page
        self.rows = rows
    }
}

public enum PDFTableExtractor {

    /// Coordinate-aware & multi-space-aware PDF table extraction.
    /// Avoids splitting ordinary prose words on single spaces while accurately reconstructing multi-column rows!
    public static func extractTables(from inputURL: URL) throws -> [ExtractedTable] {
        guard let doc = PDFDocument(url: inputURL) else {
            throw FlipDocError("Failed to open PDF document \(inputURL.lastPathComponent).")
        }

        var results: [ExtractedTable] = []
        for pageIndex in 0..<doc.pageCount {
            guard let page = doc.page(at: pageIndex) else { continue }
            let coordRows = extractCoordinateTableRows(from: page)
            if coordRows.count >= 2 {
                results.append(ExtractedTable(page: pageIndex + 1, rows: coordRows))
                continue
            }
            let textRows = extractDelimitedRowsFallback(from: page.string ?? "")
            if !textRows.isEmpty {
                results.append(ExtractedTable(page: pageIndex + 1, rows: textRows))
            }
        }
        return results
    }

    /// Groups visible glyphs on each visual Y-baseline:
    /// - Small horizontal gaps (`1.3pt ... ~1.25× glyph height`) insert normal word spaces inside a cell.
    /// - Larger horizontal gaps (`> max(10pt, 1.35× glyph height)`) split into distinct table columns!
    private static func extractCoordinateTableRows(from page: PDFPage) -> [[String]] {
        let charCount = page.numberOfCharacters
        guard charCount > 0, let fullText = page.string else { return [] }
        let nsText = fullText as NSString
        let limit = min(charCount, nsText.length)
        guard limit > 0 else { return [] }

        struct GlyphRun {
            var text: String
            var minX: CGFloat
            var maxX: CGFloat
            var midY: CGFloat
        }

        var lineBuckets: [(y: CGFloat, chars: [(ch: String, rect: CGRect)])] = []
        let yTolerance: CGFloat = 4.0

        // Skip whitespace/newlines via nsText first (PDFSelection at a newline index clamps onto the preceding character!),
        // then query PDFSelection(range) for exact glyph bounds on the page.
        for idx in 0..<limit {
            let ch = nsText.substring(with: NSRange(location: idx, length: 1))
            if ch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                continue
            }
            let selBounds = page.selection(for: NSRange(location: idx, length: 1))?.bounds(for: page) ?? .zero
            let bounds = (selBounds.width > 0 && !selBounds.isNull && !selBounds.isInfinite)
                ? selBounds
                : page.characterBounds(at: idx)
            guard bounds.width > 0.01, bounds.height > 0.1, !bounds.isNull, !bounds.isInfinite else { continue }
            let midY = bounds.midY

            if let bucketIdx = lineBuckets.firstIndex(where: { abs($0.y - midY) <= yTolerance }) {
                lineBuckets[bucketIdx].chars.append((ch, bounds))
            } else {
                lineBuckets.append((midY, [(ch, bounds)]))
            }
        }

        // PDF Y coordinates run bottom-to-top, so sort descending for top-to-bottom reading order
        lineBuckets.sort { $0.y > $1.y }

        var candidateLines: [[GlyphRun]] = []
        for bucket in lineBuckets {
            let sortedChars = bucket.chars.sorted { $0.rect.minX < $1.rect.minX }
            guard !sortedChars.isEmpty else { continue }

            let avgHeight = sortedChars.reduce(CGFloat(0)) { $0 + $1.rect.height } / CGFloat(sortedChars.count)
            let wordSpaceThreshold = max(1.2, avgHeight * 0.16)
            let columnGapThreshold = max(10.0, avgHeight * 1.35)

            var cells: [GlyphRun] = []
            var currentText = ""
            var startX: CGFloat = 0
            var lastMaxX: CGFloat = 0
            var hasStarted = false

            for item in sortedChars {
                if !hasStarted {
                    currentText = item.ch
                    startX = item.rect.minX
                    lastMaxX = item.rect.maxX
                    hasStarted = true
                } else {
                    let gap = item.rect.minX - lastMaxX
                    if gap > columnGapThreshold {
                        let trimmed = currentText.trimmingCharacters(in: .whitespaces)
                        if !trimmed.isEmpty {
                            cells.append(GlyphRun(text: trimmed, minX: startX, maxX: lastMaxX, midY: bucket.y))
                        }
                        currentText = item.ch
                        startX = item.rect.minX
                        lastMaxX = item.rect.maxX
                    } else {
                        if gap > wordSpaceThreshold {
                            currentText += " " + item.ch
                        } else {
                            currentText += item.ch
                        }
                        lastMaxX = max(lastMaxX, item.rect.maxX)
                    }
                }
            }

            let finalTrimmed = currentText.trimmingCharacters(in: .whitespaces)
            if !finalTrimmed.isEmpty {
                cells.append(GlyphRun(text: finalTrimmed, minX: startX, maxX: lastMaxX, midY: bucket.y))
            }

            if cells.count >= 2 {
                candidateLines.append(cells)
            }
        }

        guard candidateLines.count >= 2 else { return [] }

        // Align column X anchors across detected multi-cell rows so sparse cells land in the right column
        var anchors: [CGFloat] = []
        let anchorThreshold: CGFloat = 28.0
        for row in candidateLines {
            for cell in row {
                if let match = anchors.firstIndex(where: { abs($0 - cell.minX) <= anchorThreshold }) {
                    anchors[match] = (anchors[match] + cell.minX) / 2.0
                } else {
                    anchors.append(cell.minX)
                }
            }
        }
        anchors.sort()

        return candidateLines.map { row in
            var aligned = Array(repeating: "", count: anchors.count)
            for cell in row {
                if let bestIdx = anchors.enumerated().min(by: { abs($0.element - cell.minX) < abs($1.element - cell.minX) })?.offset {
                    if aligned[bestIdx].isEmpty {
                        aligned[bestIdx] = cell.text
                    } else {
                        aligned[bestIdx] += " " + cell.text
                    }
                }
            }
            return aligned
        }
    }

    /// Fallback parser splitting only on tabs, pipes, or 2+ consecutive spaces (never single spaces!).
    private static func extractDelimitedRowsFallback(from text: String) -> [[String]] {
        let lines = text.components(separatedBy: .newlines)
        var rows: [[String]] = []

        for rawLine in lines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            let cols: [String]
            if trimmed.contains("\t") {
                cols = trimmed.components(separatedBy: "\t").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            } else if trimmed.contains("|") {
                cols = trimmed.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            } else {
                // Split on 2+ spaces using regex
                cols = trimmed.replacingOccurrences(of: " {2,}", with: "\t", options: .regularExpression)
                    .components(separatedBy: "\t")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            }

            if cols.count >= 2 {
                rows.append(cols)
            }
        }
        return rows
    }

    public static func exportToCSV(tables: [ExtractedTable], outputURL: URL, delimiter: String = ",") throws -> URL {
        var out = ""
        for (idx, table) in tables.enumerated() {
            if tables.count > 1 {
                out += "# Page \(table.page)\n"
            }
            for row in table.rows {
                let escaped = row.map { cell -> String in
                    if cell.contains(delimiter) || cell.contains("\"") || cell.contains("\n") {
                        return "\"\(cell.replacingOccurrences(of: "\"", with: "\"\""))\""
                    }
                    return cell
                }
                out += escaped.joined(separator: delimiter) + "\n"
            }
            if idx < tables.count - 1 { out += "\n" }
        }
        try out.write(to: outputURL, atomically: true, encoding: .utf8)
        return outputURL
    }

    /// Converts 0-based column index to Excel column reference (`0 -> A`, `25 -> Z`, `26 -> AA`, `27 -> AB`, ...).
    public static func excelColumnName(_ colIndex: Int) -> String {
        var idx = max(0, colIndex) + 1
        var letters = ""
        while idx > 0 {
            let rem = (idx - 1) % 26
            letters.insert(Character(UnicodeScalar(65 + rem)!), at: letters.startIndex)
            idx = (idx - 1) / 26
        }
        return letters
    }

    public static func exportToXLSX(tables: [ExtractedTable], outputURL: URL) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let relsDir = tempDir.appendingPathComponent("_rels")
        let xlDir = tempDir.appendingPathComponent("xl")
        let xlRelsDir = xlDir.appendingPathComponent("_rels")
        let worksheetsDir = xlDir.appendingPathComponent("worksheets")

        try FileManager.default.createDirectory(at: relsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: xlDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: xlRelsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: worksheetsDir, withIntermediateDirectories: true)

        let validTables = tables.isEmpty ? [ExtractedTable(page: 1, rows: [["No structured tables detected in PDF"]])] : tables

        var contentTypes = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
            <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
            <Default Extension="xml" ContentType="application/xml"/>
            <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
            <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
        """
        for i in 1...validTables.count {
            contentTypes += "\n    <Override PartName=\"/xl/worksheets/sheet\(i).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>"
        }
        contentTypes += "\n</Types>"
        try contentTypes.write(to: tempDir.appendingPathComponent("[Content_Types].xml"), atomically: true, encoding: .utf8)

        let rootRels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
            <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
        </Relationships>
        """
        try rootRels.write(to: relsDir.appendingPathComponent(".rels"), atomically: true, encoding: .utf8)

        let stylesXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
            <fonts count="2">
                <font><sz val="11"/><name val="Calibri"/></font>
                <font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Calibri"/></font>
            </fonts>
            <fills count="3">
                <fill><patternFill patternType="none"/></fill>
                <fill><patternFill patternType="gray125"/></fill>
                <fill><patternFill patternType="solid"><fgColor rgb="FFFF5200"/></patternFill></fill>
            </fills>
            <borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>
            <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
            <cellXfs count="2">
                <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
                <xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1"/>
            </cellXfs>
        </styleSheet>
        """
        try stylesXML.write(to: xlDir.appendingPathComponent("styles.xml"), atomically: true, encoding: .utf8)

        var workbookXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
            <sheets>
        """
        var workbookRels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
            <Relationship Id="rIdStyles" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
        """

        for (idx, table) in validTables.enumerated() {
            let sheetId = idx + 1
            let name = validTables.count == 1 ? "Extracted_Table" : "Page_\(table.page)_T\(sheetId)"
            workbookXML += "\n        <sheet name=\"\(xmlEscape(name))\" sheetId=\"\(sheetId)\" r:id=\"rId\(sheetId)\"/>"
            workbookRels += "\n    <Relationship Id=\"rId\(sheetId)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet\(sheetId).xml\"/>"

            var sheetXML = """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
                <sheetData>
            """
            for (rowIdx, row) in table.rows.enumerated() {
                sheetXML += "\n        <row r=\"\(rowIdx + 1)\">"
                let styleAttr = (rowIdx == 0 && table.rows.count > 1) ? " s=\"1\"" : ""
                for (colIdx, cell) in row.enumerated() {
                    let cellRef = "\(excelColumnName(colIdx))\(rowIdx + 1)"
                    let trimmed = cell.trimmingCharacters(in: .whitespaces)
                    // Write clean numeric cells as numbers when appropriate
                    if rowIdx > 0, let num = Double(trimmed.replacingOccurrences(of: ",", with: "")),
                       !trimmed.hasPrefix("0") || trimmed == "0" || trimmed.hasPrefix("0.") {
                        sheetXML += "<c r=\"\(cellRef)\"\(styleAttr)><v>\(num)</v></c>"
                    } else {
                        sheetXML += "<c r=\"\(cellRef)\"\(styleAttr) t=\"inlineStr\"><is><t xml:space=\"preserve\">\(xmlEscape(cell))</t></is></c>"
                    }
                }
                sheetXML += "</row>"
            }
            sheetXML += "\n    </sheetData>\n</worksheet>"
            try sheetXML.write(to: worksheetsDir.appendingPathComponent("sheet\(sheetId).xml"), atomically: true, encoding: .utf8)
        }

        workbookXML += "\n    </sheets>\n</workbook>"
        workbookRels += "\n</Relationships>"
        try workbookXML.write(to: xlDir.appendingPathComponent("workbook.xml"), atomically: true, encoding: .utf8)
        try workbookRels.write(to: xlRelsDir.appendingPathComponent("workbook.xml.rels"), atomically: true, encoding: .utf8)

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = tempDir
        process.arguments = ["-q", "-r", outputURL.path, "[Content_Types].xml", "_rels", "xl"]
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0, FileManager.default.fileExists(atPath: outputURL.path) else {
            throw FlipDocError("Failed packaging XLSX workbook.")
        }
        return outputURL
    }

    private static func xmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
         .replacingOccurrences(of: "'", with: "&apos;")
    }
}
