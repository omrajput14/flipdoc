import Foundation
import PDFKit

public struct ExtractedTable: Sendable {
    public let page: Int
    public let rows: [[String]]
}

public enum PDFTableExtractor {
    public static func extractTables(from inputURL: URL) throws -> [ExtractedTable] {
        guard let doc = PDFDocument(url: inputURL) else {
            throw NSError(domain: "FlipDoc", code: 6, userInfo: [NSLocalizedDescriptionKey: "Failed to open PDF document."])
        }
        
        var results: [ExtractedTable] = []
        
        for pageIndex in 0..<doc.pageCount {
            guard let page = doc.page(at: pageIndex) else { continue }
            guard let pageText = page.string, !pageText.isEmpty else { continue }
            
            // Simple heuristic row/column parser for structured text lines
            let lines = pageText.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            
            var tableRows: [[String]] = []
            for line in lines {
                // Split on multiple spaces or tab characters
                let cols = line.components(separatedBy: CharacterSet.whitespaces.union(.init(charactersIn: "\t")))
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                
                if cols.count >= 2 {
                    tableRows.append(cols)
                }
            }
            
            if !tableRows.isEmpty {
                results.append(ExtractedTable(page: pageIndex + 1, rows: tableRows))
            }
        }
        
        return results
    }
    
    public static func exportToCSV(tables: [ExtractedTable], outputURL: URL) throws -> URL {
        var csvContent = ""
        for table in tables {
            csvContent += "# Page \(table.page)\n"
            for row in table.rows {
                let escaped = row.map { cell -> String in
                    if cell.contains(",") || cell.contains("\"") || cell.contains("\n") {
                        return "\"\(cell.replacingOccurrences(of: "\"", with: "\"\""))\""
                    }
                    return cell
                }
                csvContent += escaped.joined(separator: ",") + "\n"
            }
            csvContent += "\n"
        }
        try csvContent.write(to: outputURL, atomically: true, encoding: .utf8)
        return outputURL
    }
    
    public static func exportToXLSX(tables: [ExtractedTable], outputURL: URL) throws -> URL {
        // Build OpenXML spreadsheet folder structure in temporary directory, then zip into .xlsx
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        let relsDir = tempDir.appendingPathComponent("_rels")
        let xlDir = tempDir.appendingPathComponent("xl")
        let xlRelsDir = xlDir.appendingPathComponent("_rels")
        let worksheetsDir = xlDir.appendingPathComponent("worksheets")
        
        try FileManager.default.createDirectory(at: relsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: xlDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: xlRelsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: worksheetsDir, withIntermediateDirectories: true)
        
        // 1. [Content_Types].xml
        var contentTypes = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
            <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
            <Default Extension="xml" ContentType="application/xml"/>
            <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
        """
        for i in 1...max(1, tables.count) {
            contentTypes += "<Override PartName=\"/xl/worksheets/sheet\(i).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>\n"
        }
        contentTypes += "</Types>"
        try contentTypes.write(to: tempDir.appendingPathComponent("[Content_Types].xml"), atomically: true, encoding: .utf8)
        
        // 2. _rels/.rels
        let rootRels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
            <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
        </Relationships>
        """
        try rootRels.write(to: relsDir.appendingPathComponent(".rels"), atomically: true, encoding: .utf8)
        
        // 3. xl/workbook.xml & xl/_rels/workbook.xml.rels
        var workbookXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
            <sheets>
        """
        var workbookRels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        """
        
        let validTables = tables.isEmpty ? [ExtractedTable(page: 1, rows: [["No tables detected"]])] : tables
        for (idx, table) in validTables.enumerated() {
            let sheetId = idx + 1
            let name = "Page_\(table.page)_Table_\(sheetId)"
            workbookXML += "<sheet name=\"\(name)\" sheetId=\"\(sheetId)\" r:id=\"rId\(sheetId)\"/>\n"
            workbookRels += "<Relationship Id=\"rId\(sheetId)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet\(sheetId).xml\"/>\n"
            
            // 4. Generate worksheet xml
            var sheetXML = """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
                <sheetData>
            """
            for (rowIdx, row) in table.rows.enumerated() {
                sheetXML += "<row r=\"\(rowIdx + 1)\">\n"
                for (colIdx, cell) in row.enumerated() {
                    let colLetter = Character(UnicodeScalar(65 + (colIdx % 26))!)
                    let cellRef = "\(colLetter)\(rowIdx + 1)"
                    let escaped = cell.replacingOccurrences(of: "&", with: "&amp;")
                                      .replacingOccurrences(of: "<", with: "&lt;")
                                      .replacingOccurrences(of: ">", with: "&gt;")
                    sheetXML += "<c r=\"\(cellRef)\" t=\"inlineStr\"><is><t>\(escaped)</t></is></c>\n"
                }
                sheetXML += "</row>\n"
            }
            sheetXML += "</sheetData></worksheet>"
            try sheetXML.write(to: worksheetsDir.appendingPathComponent("sheet\(sheetId).xml"), atomically: true, encoding: .utf8)
        }
        
        workbookXML += "</sheets></workbook>"
        workbookRels += "</Relationships>"
        try workbookXML.write(to: xlDir.appendingPathComponent("workbook.xml"), atomically: true, encoding: .utf8)
        try workbookRels.write(to: xlRelsDir.appendingPathComponent("workbook.xml.rels"), atomically: true, encoding: .utf8)
        
        // 5. Zip temp directory into .xlsx via /usr/bin/zip
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = tempDir
        process.arguments = ["-q", "-r", outputURL.path, "[Content_Types].xml", "_rels", "xl"]
        try process.run()
        process.waitUntilExit()
        
        return outputURL
    }
}
