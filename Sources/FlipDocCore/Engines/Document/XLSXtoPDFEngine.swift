import Foundation
import AppKit
import PDFKit
import CoreGraphics
import CoreText

/// Converts XLSX/XLS spreadsheets and CSV/TSV files into vector PDFs, CSV, TSV, XLSX, or Markdown tables.
public enum XLSXtoPDFEngine {

    // MARK: - Public API

    public static func convert(inputURL: URL, outputURL: URL? = nil) throws -> URL {
        let rows = try parseRows(from: inputURL)
        let out = outputURL ?? OutputNaming.uniqueFileURL(nextTo: inputURL, newExtension: "pdf")
        return try renderVectorPDF(
            rows: rows,
            title: OutputNaming.baseName(for: inputURL),
            outputURL: out
        )
    }

    public static func convertDelimited(inputURL: URL, outputURL: URL? = nil) throws -> URL {
        let rows = try parseDelimitedRows(inputURL: inputURL)
        let out = outputURL ?? OutputNaming.uniqueFileURL(nextTo: inputURL, newExtension: "pdf")
        return try renderVectorPDF(
            rows: rows,
            title: OutputNaming.baseName(for: inputURL),
            outputURL: out
        )
    }

    /// Reads any spreadsheet (`xlsx`, `csv`, `tsv`) into a 2D array of cell strings.
    public static func parseRows(from inputURL: URL) throws -> [[String]] {
        let ext = inputURL.pathExtension.lowercased()
        if ext == "csv" || ext == "tsv" {
            return try parseDelimitedRows(inputURL: inputURL)
        }
        return try parseXLSX(inputURL: inputURL)
    }

    public static func convertSpreadsheet(inputURL: URL, to targetExt: String) throws -> URL {
        let rows = try parseRows(from: inputURL)
        guard !rows.isEmpty else {
            throw FlipDocError("Spreadsheet contains no data rows.")
        }
        let ext = targetExt.lowercased()
        let outURL = OutputNaming.uniqueFileURL(nextTo: inputURL, newExtension: ext)

        switch ext {
        case "pdf":
            return try renderVectorPDF(rows: rows, title: OutputNaming.baseName(for: inputURL), outputURL: outURL)
        case "xlsx":
            let table = ExtractedTable(page: 1, rows: rows)
            return try PDFTableExtractor.exportToXLSX(tables: [table], outputURL: outURL)
        case "csv":
            let table = ExtractedTable(page: 1, rows: rows)
            return try PDFTableExtractor.exportToCSV(tables: [table], outputURL: outURL, delimiter: ",")
        case "tsv":
            let table = ExtractedTable(page: 1, rows: rows)
            return try PDFTableExtractor.exportToCSV(tables: [table], outputURL: outURL, delimiter: "\t")
        case "md":
            let md = renderMarkdownTable(rows: rows, title: OutputNaming.baseName(for: inputURL))
            try md.write(to: outURL, atomically: true, encoding: .utf8)
            return outURL
        default:
            throw FlipDocError("Unsupported spreadsheet target format: \(ext)")
        }
    }

    private static func renderMarkdownTable(rows: [[String]], title: String) -> String {
        let colCount = max(1, rows.map(\.count).max() ?? 1)
        func padRow(_ r: [String]) -> [String] {
            (0..<colCount).map { idx in
                let val = idx < r.count ? r[idx] : ""
                return val.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: " ")
            }
        }
        var lines: [String] = ["# \(title)", ""]
        let header = padRow(rows[0])
        lines.append("| " + header.joined(separator: " | ") + " |")
        lines.append("| " + Array(repeating: "---", count: colCount).joined(separator: " | ") + " |")
        for row in rows.dropFirst() {
            lines.append("| " + padRow(row).joined(separator: " | ") + " |")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - RFC-4180 Quote-Aware CSV/TSV Parser

    public static func parseDelimitedRows(inputURL: URL) throws -> [[String]] {
        let sep: Character = inputURL.pathExtension.lowercased() == "tsv" ? "\t" : ","
        let content = (try? String(contentsOf: inputURL, encoding: .utf8))
            ?? (try? String(contentsOf: inputURL, encoding: .isoLatin1))
            ?? ""

        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentField = ""
        var inQuotes = false
        var iterator = content.makeIterator()
        var peeked: Character? = nil

        func nextChar() -> Character? {
            if let p = peeked {
                peeked = nil
                return p
            }
            return iterator.next()
        }

        while let ch = nextChar() {
            if inQuotes {
                if ch == "\"" {
                    let after = nextChar()
                    if after == "\"" {
                        currentField.append("\"")
                    } else {
                        inQuotes = false
                        peeked = after
                    }
                } else {
                    currentField.append(ch)
                }
            } else {
                if ch == "\"" && currentField.isEmpty {
                    inQuotes = true
                } else if ch == sep {
                    currentRow.append(currentField.trimmingCharacters(in: .whitespaces))
                    currentField = ""
                } else if ch == "\r" || ch == "\n" {
                    if ch == "\r" {
                        let after = nextChar()
                        if after != "\n" { peeked = after }
                    }
                    currentRow.append(currentField.trimmingCharacters(in: .whitespaces))
                    currentField = ""
                    if !currentRow.allSatisfy(\.isEmpty) {
                        rows.append(currentRow)
                    }
                    currentRow = []
                } else {
                    currentField.append(ch)
                }
            }
        }

        if !currentField.isEmpty || !currentRow.isEmpty {
            currentRow.append(currentField.trimmingCharacters(in: .whitespaces))
            if !currentRow.allSatisfy(\.isEmpty) {
                rows.append(currentRow)
            }
        }
        return rows
    }

    // MARK: - XLSX Parsing

    private static func parseXLSX(inputURL: URL) throws -> [[String]] {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        unzip.arguments = ["-q", inputURL.path, "-d", tmp.path]
        unzip.standardError = FileHandle.nullDevice
        try unzip.run()
        unzip.waitUntilExit()

        let xlDir = tmp.appendingPathComponent("xl")
        let ssURL = xlDir.appendingPathComponent("sharedStrings.xml")
        let wsDir = xlDir.appendingPathComponent("worksheets")

        var shared: [String] = []
        if let data = try? Data(contentsOf: ssURL) {
            shared = extractSharedStrings(from: data)
        }

        let sheets = (try? FileManager.default.contentsOfDirectory(atPath: wsDir.path))?
            .filter { $0.hasSuffix(".xml") }.sorted() ?? []

        guard let first = sheets.first,
              let sheetData = try? Data(contentsOf: wsDir.appendingPathComponent(first)) else {
            throw FlipDocError("No worksheet found in \(inputURL.lastPathComponent).")
        }
        return extractRows(from: sheetData, shared: shared)
    }

    private static func extractSharedStrings(from data: Data) -> [String] {
        guard let xml = String(data: data, encoding: .utf8) else { return [] }
        var result: [String] = []
        var remainder = xml[xml.startIndex...]
        while let openTag = remainder.range(of: "<t") {
            let afterT = openTag.upperBound
            guard afterT < remainder.endIndex else { break }
            let nextChar = remainder[afterT]
            guard nextChar == ">" || nextChar == " " else {
                remainder = remainder[afterT...]
                continue
            }
            guard let closeBracket = remainder[openTag.lowerBound...].range(of: ">") else { break }
            let vs = closeBracket.upperBound
            guard let endTag = remainder[vs...].range(of: "</t>") else { break }
            result.append(unescape(String(remainder[vs..<endTag.lowerBound])))
            remainder = remainder[endTag.upperBound...]
        }
        return result
    }

    private static func extractRows(from data: Data, shared: [String]) -> [[String]] {
        guard let xml = String(data: data, encoding: .utf8) else { return [] }
        var rowMap: [Int: [Int: String]] = [:]
        var rem = xml[xml.startIndex...]
        var sequentialRow = 1

        while let rs = rem.range(of: "<row") {
            guard let re = rem[rs.lowerBound...].range(of: "</row>") else { break }
            let block = String(rem[rs.lowerBound..<re.upperBound])
            rem = rem[re.upperBound...]

            let rn = attr("r", in: block).flatMap(Int.init) ?? sequentialRow
            sequentialRow = rn + 1
            var cs = block[block.startIndex...]

            while let cStart = cs.range(of: "<c ") ?? cs.range(of: "<c>") {
                guard let cEnd = cs[cStart.lowerBound...].range(of: "</c>") else { break }
                let cell = String(cs[cStart.lowerBound..<cEnd.upperBound])
                cs = cs[cEnd.upperBound...]

                let col = attr("r", in: cell).map(colIndex) ?? (rowMap[rn]?.keys.max().map { $0 + 1 } ?? 0)
                let type = attr("t", in: cell) ?? ""

                var val = ""
                if let vs = cell.range(of: "<v>"), let ve = cell.range(of: "</v>") {
                    let raw = String(cell[vs.upperBound..<ve.lowerBound])
                    if type == "s", let idx = Int(raw), idx < shared.count {
                        val = shared[idx]
                    } else {
                        val = unescape(raw)
                    }
                }
                if type == "inlineStr" || val.isEmpty {
                    if let ts = cell.range(of: "<t"),
                       let closeB = cell[ts.lowerBound...].range(of: ">"),
                       let te = cell[closeB.upperBound...].range(of: "</t>") {
                        val = unescape(String(cell[closeB.upperBound..<te.lowerBound]))
                    }
                }

                if rowMap[rn] == nil { rowMap[rn] = [:] }
                rowMap[rn]![col] = val
            }
        }

        return rowMap.keys.sorted().compactMap { rn -> [String]? in
            guard let cols = rowMap[rn] else { return nil }
            let maxCol = cols.keys.max() ?? 0
            return (0...maxCol).map { cols[$0] ?? "" }
        }
    }

    // MARK: - Vector PDF Rendering (FlipDoc Studio Accent Styling)

    private static func renderVectorPDF(
        rows: [[String]],
        title: String,
        outputURL: URL
    ) throws -> URL {
        guard !rows.isEmpty else {
            throw FlipDocError("Spreadsheet is empty.")
        }

        let colCount = rows.map(\.count).max() ?? 1
        // Automatically switch to Landscape A4 for wide spreadsheets (> 6 columns)
        let isLandscape = colCount > 6
        let W: CGFloat = isLandscape ? 841.89 : 595.28
        let H: CGFloat = isLandscape ? 595.28 : 841.89
        let margin: CGFloat = 36.0
        let usable = W - margin * 2

        let rowH: CGFloat = 18.0
        let headerH: CGFloat = 22.0
        let titleH: CGFloat = 30.0
        let pad: CGFloat = 5.0

        let titleFont = CTFontCreateWithName("Helvetica-Bold" as CFString, 13, nil)
        let headerFont = CTFontCreateWithName("Helvetica-Bold" as CFString, 8.5, nil)
        let cellFont = CTFontCreateWithName("Helvetica" as CFString, 8.0, nil)

        var maxLen = Array(repeating: 3, count: colCount)
        for row in rows {
            for (ci, cell) in row.enumerated() where ci < colCount {
                maxLen[ci] = max(maxLen[ci], min(cell.count + 2, 42))
            }
        }
        let total = CGFloat(maxLen.reduce(0, +))
        let colWidths = maxLen.map { CGFloat($0) / total * usable }

        var mediaBox = CGRect(x: 0, y: 0, width: W, height: H)
        guard let ctx = CGContext(outputURL as CFURL, mediaBox: &mediaBox, nil) else {
            throw FlipDocError("Failed to create PDF context.")
        }

        let headerOrange = CGColor(red: 0.953, green: 0.357, blue: 0.157, alpha: 1) // #F35B28
        let white = CGColor(gray: 1.0, alpha: 1)
        let darkInk = CGColor(red: 0.15, green: 0.16, blue: 0.15, alpha: 1)
        let stripe = CGColor(red: 0.975, green: 0.975, blue: 0.97, alpha: 1)
        let border = CGColor(gray: 0.86, alpha: 1)

        var ri = 0
        var pageNum = 0

        while ri < rows.count || pageNum == 0 {
            ctx.beginPage(mediaBox: &mediaBox)
            var y = H - margin

            if pageNum == 0 {
                drawText(title, font: titleFont, color: darkInk,
                         in: CGRect(x: margin, y: y - titleH, width: usable, height: titleH),
                         ctx: ctx)
                y -= titleH
            }

            drawRowBg(x: margin, y: y - headerH, w: usable, h: headerH, color: headerOrange, ctx: ctx)
            var cx: CGFloat = margin
            for (ci, cw) in colWidths.enumerated() {
                let cell = ci < rows[0].count ? rows[0][ci] : ""
                drawBorder(x: cx, y: y - headerH, w: cw, h: headerH, color: border, ctx: ctx)
                drawText(cell, font: headerFont, color: white,
                         in: CGRect(x: cx + pad, y: y - headerH, width: max(1, cw - pad * 2), height: headerH),
                         ctx: ctx)
                cx += cw
            }
            y -= headerH

            let topOffset = (pageNum == 0) ? (margin + titleH + headerH) : (margin + headerH)
            let avail = H - topOffset - margin
            let maxRows = max(1, Int(avail / rowH))

            let startRow = (pageNum == 0 && ri == 0) ? 1 : ri
            let endRow = min(rows.count, startRow + maxRows)

            for dataRow in startRow..<endRow {
                let bg: CGColor = dataRow % 2 == 0 ? stripe : white
                drawRowBg(x: margin, y: y - rowH, w: usable, h: rowH, color: bg, ctx: ctx)
                var cx2: CGFloat = margin
                for (ci, cw) in colWidths.enumerated() {
                    let cell = ci < rows[dataRow].count ? rows[dataRow][ci] : ""
                    drawBorder(x: cx2, y: y - rowH, w: cw, h: rowH, color: border, ctx: ctx)
                    drawText(cell, font: cellFont, color: darkInk,
                             in: CGRect(x: cx2 + pad, y: y - rowH, width: max(1, cw - pad * 2), height: rowH),
                             ctx: ctx)
                    cx2 += cw
                }
                y -= rowH
            }

            ctx.endPage()
            ri = endRow
            pageNum += 1
            if ri >= rows.count { break }
        }

        ctx.closePDF()
        return outputURL
    }

    private static func drawText(_ text: String, font: CTFont, color: CGColor, in rect: CGRect, ctx: CGContext) {
        guard !text.isEmpty else { return }
        let nsFont = font as NSFont
        let nsColor = NSColor(cgColor: color) ?? .black
        let attrStr = NSAttributedString(
            string: text,
            attributes: [
                .font: nsFont,
                .foregroundColor: nsColor
            ]
        )
        let line = CTLineCreateWithAttributedString(attrStr)

        let ascent = CTFontGetAscent(font)
        let descent = CTFontGetDescent(font)
        let lineH = ascent + descent
        let textY = rect.minY + (rect.height - lineH) / 2 + descent

        ctx.saveGState()
        ctx.clip(to: rect)
        ctx.textMatrix = .identity
        ctx.textPosition = CGPoint(x: rect.minX, y: textY)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }

    private static func drawRowBg(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, color: CGColor, ctx: CGContext) {
        ctx.setFillColor(color)
        ctx.fill(CGRect(x: x, y: y, width: w, height: h))
    }

    private static func drawBorder(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, color: CGColor, ctx: CGContext) {
        ctx.setStrokeColor(color)
        ctx.setLineWidth(0.4)
        ctx.stroke(CGRect(x: x, y: y, width: w, height: h))
    }

    private static func attr(_ name: String, in xml: String) -> String? {
        let pat = name + "=\""
        guard let s = xml.range(of: pat) else { return nil }
        let vs = s.upperBound
        guard let e = xml[vs...].range(of: "\"") else { return nil }
        return String(xml[vs..<e.lowerBound])
    }

    private static func colIndex(_ ref: String) -> Int {
        var col = 0
        for ch in ref.unicodeScalars {
            guard ch.value >= 65 && ch.value <= 90 else { break }
            col = col * 26 + Int(ch.value - 64)
        }
        return max(0, col - 1)
    }

    private static func unescape(_ s: String) -> String {
        s.replacingOccurrences(of: "&amp;", with: "&")
         .replacingOccurrences(of: "&lt;", with: "<")
         .replacingOccurrences(of: "&gt;", with: ">")
         .replacingOccurrences(of: "&quot;", with: "\"")
         .replacingOccurrences(of: "&apos;", with: "'")
    }
}
