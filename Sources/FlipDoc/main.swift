import AppKit
import Foundation
import FlipDocCore

private enum AppHolder {
    @MainActor static var delegate: FlipDocAppDelegate?
}

let args = CommandLine.arguments

if args.contains("-h") || args.contains("--help") {
    print("""
    FlipDoc — Zero-click local file conversions, tools & actions for Mac

    USAGE:
      FlipDoc                         Launch menu-bar app & drag-and-drop radial wheel
      FlipDoc --studio                Launch and open the interactive FlipDoc Studio
      FlipDoc tables <file.pdf>       Extract tables from PDF into an Excel (.xlsx) workbook
      FlipDoc markdown <file.pdf>     Convert PDF into structured Markdown (.md)
      FlipDoc ocr <file>              Extract text via Apple Vision OCR (Image or Scanned PDF)
    """)
    exit(0)
}

if args.count >= 2 && args[1] == "tables" {
    guard args.count >= 3 else {
        fputs("Usage: FlipDoc tables <path-to-pdf> [-o <out.xlsx>]\n", stderr)
        exit(1)
    }
    let inputURL = URL(fileURLWithPath: args[2])
    do {
        let tables = try PDFTableExtractor.extractTables(from: inputURL)
        let outURL = (args.count >= 5 && args[3] == "-o")
            ? URL(fileURLWithPath: args[4])
            : OutputNaming.uniqueFileURL(nextTo: inputURL, newExtension: "xlsx")
        _ = try PDFTableExtractor.exportToXLSX(tables: tables, outputURL: outURL)
        print("Extracted \(tables.count) table(s) -> \(outURL.path)")
        exit(0)
    } catch {
        fputs("Error: \(error.localizedDescription)\n", stderr)
        exit(1)
    }
} else if args.count >= 2 && args[1] == "markdown" {
    guard args.count >= 3 else {
        fputs("Usage: FlipDoc markdown <path-to-pdf>\n", stderr)
        exit(1)
    }
    let inputURL = URL(fileURLWithPath: args[2])
    let sema = DispatchSemaphore(value: 0)
    nonisolated(unsafe) var exitCode: Int32 = 0
    Task {
        do {
            let out = try await PDFMarkdownConverter.convert(inputURL: inputURL)
            print("Converted to Markdown -> \(out.path)")
        } catch {
            fputs("Error: \(error.localizedDescription)\n", stderr)
            exitCode = 1
        }
        sema.signal()
    }
    sema.wait()
    exit(exitCode)
} else if args.count >= 2 && args[1] == "ocr" {
    guard args.count >= 3 else {
        fputs("Usage: FlipDoc ocr <path-to-image-or-pdf>\n", stderr)
        exit(1)
    }
    let inputURL = URL(fileURLWithPath: args[2])
    let sema = DispatchSemaphore(value: 0)
    nonisolated(unsafe) var exitCode: Int32 = 0
    Task {
        do {
            let text = try await VisionOCREngine.shared.recognizeText(from: inputURL)
            print(text)
        } catch {
            fputs("Error: \(error.localizedDescription)\n", stderr)
            exitCode = 1
        }
        sema.signal()
    }
    sema.wait()
    exit(exitCode)
} else {
    MainActor.assumeIsolated {
        let app = NSApplication.shared
        let delegate = FlipDocAppDelegate()
        AppHolder.delegate = delegate
        app.delegate = delegate
        app.run()
    }
}
