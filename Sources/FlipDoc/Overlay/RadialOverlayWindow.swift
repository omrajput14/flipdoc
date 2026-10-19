import AppKit
import SwiftUI

public final class RadialOverlayWindow: NSPanel {
    public static let shared = RadialOverlayWindow()
    
    private var activeURL: URL?
    private var currentMode: ModifierMode = .conversions
    
    public init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 360),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        
        self.isOpaque = false
        self.backgroundColor = .clear
        self.level = .floating
        self.hasShadow = false
        self.ignoresMouseEvents = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isMovableByWindowBackground = false
    }
    
    public func show(at screenPoint: NSPoint, for fileURL: URL, mode: ModifierMode) {
        self.activeURL = fileURL
        self.currentMode = mode
        
        let category = FileCategory.classify(url: fileURL)
        let options = category.options(for: mode)
        
        let fanView = RadialFanView(mode: mode, category: category, options: options) { [weak self] selected in
            self?.executeAction(selected)
        }
        
        self.contentView = NSHostingView(rootView: fanView)
        
        let windowOrigin = NSPoint(
            x: screenPoint.x - (frame.width / 2.0),
            y: screenPoint.y - (frame.height / 2.0)
        )
        self.setFrameOrigin(windowOrigin)
        self.orderFrontRegardless()
    }
    
    public func hide() {
        self.orderOut(nil)
        self.activeURL = nil
    }
    
    private func executeAction(_ option: FanOption) {
        guard let url = activeURL else { return }
        hide()
        
        // Run conversion on a high-priority background task so UI stays responsive
        Task.detached(priority: .userInitiated) {
            do {
                switch option.actionTag {
                case "extract_tables":
                    let tables = try PDFTableExtractor.extractTables(from: url)
                    let outXLSX = url.deletingPathExtension().appendingPathExtension("xlsx")
                    let outCSV = url.deletingPathExtension().appendingPathExtension("csv")
                    _ = try PDFTableExtractor.exportToCSV(tables: tables, outputURL: outCSV)
                    _ = try PDFTableExtractor.exportToXLSX(tables: tables, outputURL: outXLSX)
                    NotificationHelper.send(title: "Tables Extracted", subtitle: "\(tables.count) table(s) saved to \(outXLSX.lastPathComponent)")
                    
                case "to_markdown":
                    let out = try PDFMarkdownConverter.convert(inputURL: url)
                    NotificationHelper.send(title: "Converted to Markdown", subtitle: out.lastPathComponent)
                    
                case "to_images":
                    let images = try DocumentTools.pdfToImages(inputURL: url)
                    NotificationHelper.send(title: "Exported Pages", subtitle: "\(images.count) image(s) saved")
                    
                case "to_text":
                    let out = try DocumentTools.pdfToPlainText(inputURL: url)
                    NotificationHelper.send(title: "Text Extracted", subtitle: out.lastPathComponent)
                    
                case "to_docx":
                    let out = try DocumentTools.toDocx(inputURL: url)
                    NotificationHelper.send(title: "Converted to Word", subtitle: out.lastPathComponent)
                    
                case "to_png":
                    let out = try ImageTransformer.convert(inputURL: url, toUTType: .png)
                    NotificationHelper.send(title: "Converted to PNG", subtitle: out.lastPathComponent)
                    
                case "to_jpg":
                    let out = try ImageTransformer.convert(inputURL: url, toUTType: .jpeg)
                    NotificationHelper.send(title: "Converted to JPG", subtitle: out.lastPathComponent)
                    
                case "to_webp":
                    let out = try ImageTransformer.convert(inputURL: url, toUTType: .webP)
                    NotificationHelper.send(title: "Converted to WebP", subtitle: out.lastPathComponent)
                    
                case "to_pdf":
                    let out = try DocumentTools.createPDF(from: url)
                    NotificationHelper.send(title: "Converted to PDF", subtitle: out.lastPathComponent)
                    
                case "ocr_text", "ocr_full":
                    let text = try await VisionOCREngine.shared.recognizeText(from: url)
                    let out = url.deletingPathExtension().appendingPathExtension("txt")
                    try text.write(to: out, atomically: true, encoding: .utf8)
                    NotificationHelper.send(title: "OCR Complete", subtitle: "Saved text to \(out.lastPathComponent)")
                    
                case "to_mp3", "to_m4a", "to_wav":
                    let fmt = option.actionTag.replacingOccurrences(of: "to_", with: "")
                    let out = try DocumentTools.convertAudio(inputURL: url, format: fmt)
                    NotificationHelper.send(title: "Audio Converted", subtitle: out.lastPathComponent)
                    
                case "compress_pdf":
                    let out = try DocumentTools.compressPDF(inputURL: url)
                    NotificationHelper.send(title: "PDF Compressed", subtitle: out.lastPathComponent)
                    
                case "split_pages":
                    let pages = try DocumentTools.splitPDF(inputURL: url)
                    NotificationHelper.send(title: "PDF Split", subtitle: "\(pages.count) page(s) created")
                    
                case "strip_exif":
                    let out = try DocumentTools.stripEXIF(inputURL: url)
                    NotificationHelper.send(title: "EXIF Stripped", subtitle: out.lastPathComponent)
                    
                case "compress_image":
                    let out = try ImageTransformer.convert(inputURL: url, toUTType: .jpeg)
                    NotificationHelper.send(title: "Image Compressed", subtitle: out.lastPathComponent)
                    
                case "zip_compress":
                    let out = try DocumentTools.zipCompress(inputURL: url)
                    NotificationHelper.send(title: "Zip Created", subtitle: out.lastPathComponent)
                    
                case "float_file":
                    let proc = Process()
                    proc.executableURL = URL(fileURLWithPath: "/usr/bin/qlmanage")
                    proc.arguments = ["-p", url.path]
                    try proc.run()
                    
                case "airdrop_file":
                    DispatchQueue.main.async {
                        if let airdrop = NSSharingService(named: .sendViaAirDrop) {
                            airdrop.perform(withItems: [url])
                        }
                    }
                    
                case "copy_path":
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.path, forType: .string)
                    NotificationHelper.send(title: "Copied Path", subtitle: url.path)
                    
                case "open_terminal":
                    let folder = url.hasDirectoryPath ? url : url.deletingLastPathComponent()
                    let proc = Process()
                    proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                    proc.arguments = ["-a", "Terminal", folder.path]
                    try proc.run()
                    
                default:
                    NotificationHelper.send(title: "FlipDoc", subtitle: "Action \(option.label) completed.")
                }
            } catch {
                NotificationHelper.send(title: "FlipDoc Error", subtitle: error.localizedDescription)
            }
        }
    }
}

public enum NotificationHelper {
    public static func send(title: String, subtitle: String) {
        let notification = NSUserNotification()
        notification.title = title
        notification.subtitle = subtitle
        notification.soundName = NSUserNotificationDefaultSoundName
        NSUserNotificationCenter.default.deliver(notification)
    }
}
