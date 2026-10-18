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
        
        // Center window on cursor
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
        
        Task {
            do {
                switch option.actionTag {
                case "extract_tables":
                    let tables = try PDFTableExtractor.extractTables(from: url)
                    let out = url.deletingPathExtension().appendingPathExtension("xlsx")
                    _ = try PDFTableExtractor.exportToXLSX(tables: tables, outputURL: out)
                    NotificationHelper.send(title: "Tables Extracted", subtitle: "\(tables.count) table(s) saved to \(out.lastPathComponent)")
                    
                case "to_markdown":
                    let out = try PDFMarkdownConverter.convert(inputURL: url)
                    NotificationHelper.send(title: "Converted to Markdown", subtitle: out.lastPathComponent)
                    
                case "to_png":
                    let out = try ImageTransformer.convert(inputURL: url, toUTType: .png)
                    NotificationHelper.send(title: "Converted to PNG", subtitle: out.lastPathComponent)
                    
                case "to_jpg":
                    let out = try ImageTransformer.convert(inputURL: url, toUTType: .jpeg)
                    NotificationHelper.send(title: "Converted to JPG", subtitle: out.lastPathComponent)
                    
                case "to_webp":
                    let out = try ImageTransformer.convert(inputURL: url, toUTType: .webP)
                    NotificationHelper.send(title: "Converted to WebP", subtitle: out.lastPathComponent)
                    
                case "ocr_text":
                    let text = try await VisionOCREngine.shared.recognizeText(from: url)
                    let out = url.deletingPathExtension().appendingPathExtension("txt")
                    try text.write(to: out, atomically: true, encoding: .utf8)
                    NotificationHelper.send(title: "OCR Complete", subtitle: "Saved text to \(out.lastPathComponent)")
                    
                case "copy_path":
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.path, forType: .string)
                    NotificationHelper.send(title: "Copied Path", subtitle: url.path)
                    
                default:
                    NotificationHelper.send(title: "FlipDoc", subtitle: "Action \(option.label) executed.")
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
