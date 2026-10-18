import AppKit
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Run as background menu-bar accessory (no Dock icon, exactly like Tangerine LSUIElement)
        NSApplication.shared.setActivationPolicy(.accessory)
        
        menuBarController = MenuBarController()
        GlobalDragMonitor.shared.start()
        
        NotificationHelper.send(
            title: "FlipDoc Active",
            subtitle: "Drag any file & tap Shift, Cmd, or Ctrl to convert."
        )
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        GlobalDragMonitor.shared.stop()
    }
}

// Global strong reference to avoid ARC releasing the delegate
var appDelegate: AppDelegate?

let args = CommandLine.arguments

if args.contains("-h") || args.contains("--help") {
    print("""
    FlipDoc — The zero-click offline document & file transformer
    
    USAGE:
      FlipDoc                     Launch background menu-bar agent with drag & drop overlay
      FlipDoc tables <file.pdf>   Extract tables from PDF into an Excel (.xlsx) file
      FlipDoc markdown <file.pdf> Convert PDF into Markdown (.md)
    """)
    exit(0)
}

if args.count >= 2 && args[1] == "tables" {
    guard args.count >= 3 else {
        print("Usage: FlipDoc tables <path-to-pdf> [-o <out.xlsx>]")
        exit(1)
    }
    let inputPath = args[2]
    let inputURL = URL(fileURLWithPath: inputPath)
    do {
        let tables = try PDFTableExtractor.extractTables(from: inputURL)
        let outURL = (args.count >= 5 && args[3] == "-o") ? URL(fileURLWithPath: args[4]) : inputURL.deletingPathExtension().appendingPathExtension("xlsx")
        _ = try PDFTableExtractor.exportToXLSX(tables: tables, outputURL: outURL)
        print("Successfully extracted \(tables.count) table(s) -> \(outURL.path)")
        exit(0)
    } catch {
        fputs("Error: \(error.localizedDescription)\n", stderr)
        exit(1)
    }
} else if args.count >= 2 && args[1] == "markdown" {
    guard args.count >= 3 else {
        print("Usage: FlipDoc markdown <path-to-pdf>")
        exit(1)
    }
    let inputURL = URL(fileURLWithPath: args[2])
    do {
        let out = try PDFMarkdownConverter.convert(inputURL: inputURL)
        print("Converted to Markdown -> \(out.path)")
        exit(0)
    } catch {
        fputs("Error: \(error.localizedDescription)\n", stderr)
        exit(1)
    }
} else {
    // Launch GUI background daemon
    let app = NSApplication.shared
    appDelegate = AppDelegate()
    app.delegate = appDelegate
    app.run()
}
