import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
public final class ActionDispatcher: NSObject, NSSharingServiceDelegate {
    public static let shared = ActionDispatcher()

    private var activeSharingService: NSSharingService?
    private var airDropAnchorWindow: NSWindow?

    private override init() {
        super.init()
    }

    public func execute(option: FanOption, urls: [URL]) {
        let validURLs = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !validURLs.isEmpty else {
            OperationProgressHUD.shared.showError(title: "File Not Found", message: "The selected file could not be read.")
            return
        }

        // 1. Core File Actions (`⌃ Control`)
        switch option.actionTag {
        case "float_file":
            FloatingShelfManager.shared.pinFiles(validURLs)
            OperationProgressHUD.shared.showToast(
                title: validURLs.count == 1 ? "Pinned \(validURLs[0].lastPathComponent)" : "Pinned \(validURLs.count) files",
                subtitle: "Available on your Float Shelf",
                systemImage: "pin.fill"
            )
            return

        case "airdrop_file":
            presentAirDrop(for: validURLs)
            return

        case "copy_file":
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects(validURLs as [NSURL])
            SoundAndHaptics.shared.playCompletion()
            OperationProgressHUD.shared.showToast(
                title: validURLs.count == 1 ? "Copied \(validURLs[0].lastPathComponent)" : "Copied \(validURLs.count) files",
                subtitle: "Ready to paste (⌘V) anywhere",
                systemImage: "doc.on.doc"
            )
            return

        case "move_file":
            moveFilesInteractive(validURLs)
            return

        case "copy_path":
            let joined = validURLs.map(\.path).joined(separator: "\n")
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(joined, forType: .string)
            SoundAndHaptics.shared.playCompletion()
            OperationProgressHUD.shared.showToast(
                title: "Copied File Path\(validURLs.count > 1 ? "s" : "")",
                subtitle: validURLs[0].path,
                systemImage: "doc.text"
            )
            return

        case "open_terminal":
            openInTerminal(validURLs[0])
            return

        // 2. Interactive Studio Tool Sheets (`opensToolSheet`)
        case "tool_compress":
            ToolOptionsWindowController.shared.showCompress(urls: validURLs)
            return

        case "tool_resize_image":
            ToolOptionsWindowController.shared.showResize(urls: validURLs)
            return

        case "tool_organize_pdf":
            ToolOptionsWindowController.shared.showOrganizePDF(urls: validURLs)
            return

        case "tool_metadata":
            ToolOptionsWindowController.shared.showMetadataInspector(urls: validURLs)
            return

        case "tool_protect_pdf":
            ToolOptionsWindowController.shared.showProtectPDF(urls: validURLs)
            return

        case "tool_redact":
            ToolOptionsWindowController.shared.showRedact(urls: validURLs)
            return

        case "scan_qr":
            runQRScanInteractive(validURLs)
            return

        case "ocr_full":
            runOCRInteractive(validURLs)
            return

        default:
            break
        }

        // 3. Asynchronous Conversions & Instant Batch Tools
        let sourceLabel = validURLs.count == 1 ? validURLs[0].lastPathComponent : "\(validURLs.count) files"
        OperationProgressHUD.shared.showProgress(
            title: option.label,
            subtitle: "Processing \(sourceLabel)…"
        )

        Task { @MainActor in
            do {
                let outputs = try await performConversionOrTool(tag: option.actionTag, urls: validURLs)
                for (index, outURL) in outputs.enumerated() {
                    let srcName = index < validURLs.count ? validURLs[index].lastPathComponent : sourceLabel
                    AppPreferences.shared.recordConversion(
                        sourceName: srcName,
                        outputURL: outURL,
                        summary: option.label
                    )
                }

                SoundAndHaptics.shared.playCompletion()
                let titleText = outputs.count == 1
                    ? "Saved \(outputs[0].lastPathComponent)"
                    : "Saved \(outputs.count) files"
                let subtitleText = outputs.count == 1
                    ? "Beside \(validURLs[0].deletingLastPathComponent().lastPathComponent)/"
                    : option.label

                OperationProgressHUD.shared.showSuccess(
                    title: titleText,
                    subtitle: subtitleText,
                    outputURLs: outputs
                )

                if AppPreferences.shared.autoFloatOutputs {
                    FloatingShelfManager.shared.pinFiles(outputs)
                }
                if AppPreferences.shared.autoRevealInFinder {
                    NSWorkspace.shared.activateFileViewerSelecting(outputs)
                }
            } catch {
                OperationProgressHUD.shared.showError(
                    title: "\(option.wheelTitle) Failed",
                    message: error.localizedDescription
                )
            }
        }
    }

    // MARK: - Conversion & Instant Tool Router

    private func performConversionOrTool(tag: String, urls: [URL]) async throws -> [URL] {
        // Multi-file combined outputs first:
        switch tag {
        case "to_pdf" where urls.allSatisfy({ FileCategory.classify(url: $0) == .image }):
            return [try ImageTransformer.combineImagesToPDF(inputURLs: urls)]

        case "create_collage":
            return [try ImageTransformer.createCollage(inputURLs: urls)]

        case "quick_merge_pdf":
            return [try DocumentTools.mergePDFs(inputURLs: urls)]

        case "to_zip":
            return [try DocumentTools.createArchive(inputURLs: urls, format: "zip")]

        case "to_tar":
            return [try DocumentTools.createArchive(inputURLs: urls, format: "tar")]

        case "to_targz":
            return [try DocumentTools.createArchive(inputURLs: urls, format: "tar.gz")]

        default:
            break
        }

        // Per-file outputs (works seamlessly for 1 or N files!):
        var results: [URL] = []
        for url in urls {
            let out: URL
            switch tag {
            // Image formats
            case "to_jpg":
                out = try await ImageTransformer.convert(inputURL: url, toFormat: "jpg")
            case "to_png":
                out = try await ImageTransformer.convert(inputURL: url, toFormat: "png")
            case "to_webp":
                out = try await ImageTransformer.convert(inputURL: url, toFormat: "webp")
            case "to_heic":
                out = try await ImageTransformer.convert(inputURL: url, toFormat: "heic")
            case "to_avif":
                out = try await ImageTransformer.convert(inputURL: url, toFormat: "avif")
            case "to_tiff":
                out = try await ImageTransformer.convert(inputURL: url, toFormat: "tiff")
            case "to_bmp":
                out = try await ImageTransformer.convert(inputURL: url, toFormat: "bmp")
            case "strip_exif":
                out = try ImageTransformer.stripMetadata(inputURL: url)
            case "remove_bg":
                out = try await ImageTransformer.removeBackground(inputURL: url)

            // PDF & Document exports
            case "to_pdf":
                out = try DocumentTools.createPDF(from: [url])
            case "pdf_handout":
                out = try DocumentTools.createStudyHandoutPDF(inputURL: url)
            case "extract_tables":
                let tables = try PDFTableExtractor.extractTables(from: url)
                let dest = OutputNaming.uniqueFileURL(nextTo: url, newExtension: "xlsx")
                out = try PDFTableExtractor.exportToXLSX(tables: tables, outputURL: dest)
            case "to_docx":
                out = try await DocumentTools.convertViaTextutil(inputURL: url, targetFormat: "docx")
            case "to_rtf":
                out = try await DocumentTools.convertViaTextutil(inputURL: url, targetFormat: "rtf")
            case "to_html":
                out = try await DocumentTools.convertViaTextutil(inputURL: url, targetFormat: "html")
            case "to_markdown":
                out = try await PDFMarkdownConverter.convert(inputURL: url)
            case "pdf_to_png":
                out = try DocumentTools.pdfToImages(inputURL: url, format: "png")
            case "pdf_to_jpg":
                out = try DocumentTools.pdfToImages(inputURL: url, format: "jpg")
            case "to_text":
                out = try await DocumentTools.pdfToPlainText(inputURL: url)
            case "doc_to_md":
                out = try DocumentTools.documentToPlainOrMarkdown(inputURL: url, asMarkdown: true)
            case "doc_to_txt":
                out = try DocumentTools.documentToPlainOrMarkdown(inputURL: url, asMarkdown: false)
            case "split_pages":
                out = try DocumentTools.splitPDF(inputURL: url)
            case "strip_pdf_metadata":
                out = try DocumentTools.stripPDFMetadata(inputURL: url)

            // Spreadsheets
            case "sheet_to_xlsx":
                out = try XLSXtoPDFEngine.convertSpreadsheet(inputURL: url, to: "xlsx")
            case "sheet_to_csv":
                out = try XLSXtoPDFEngine.convertSpreadsheet(inputURL: url, to: "csv")
            case "sheet_to_tsv":
                out = try XLSXtoPDFEngine.convertSpreadsheet(inputURL: url, to: "tsv")
            case "sheet_to_md":
                out = try XLSXtoPDFEngine.convertSpreadsheet(inputURL: url, to: "md")

            // Subtitles
            case "sub_to_srt":
                out = try DocumentTools.convertSubtitles(inputURL: url, targetFormat: "srt")
            case "sub_to_vtt":
                out = try DocumentTools.convertSubtitles(inputURL: url, targetFormat: "vtt")
            case "sub_to_txt":
                out = try DocumentTools.convertSubtitles(inputURL: url, targetFormat: "txt")

            // Video
            case "to_mp4":
                out = try await MediaConverter.convertVideo(inputURL: url, toFormat: "mp4")
            case "to_mov":
                out = try await MediaConverter.convertVideo(inputURL: url, toFormat: "mov")
            case "to_gif":
                out = try await MediaConverter.videoToAnimatedGIF(inputURL: url)
            case "extract_m4a":
                out = try await MediaConverter.extractAudioFromVideo(inputURL: url, format: "m4a")
            case "extract_wav":
                out = try await MediaConverter.extractAudioFromVideo(inputURL: url, format: "wav")
            case "compress_video":
                out = try await MediaConverter.convertVideo(inputURL: url, toFormat: "mp4", compress: true)
            case "mute_video":
                out = try await MediaConverter.muteVideo(inputURL: url)
            case "video_snapshots":
                out = try await MediaConverter.saveVideoSnapshots(inputURL: url)

            // Audio
            case "to_m4a":
                out = try MediaConverter.convertAudio(inputURL: url, format: "m4a")
            case "to_wav":
                out = try MediaConverter.convertAudio(inputURL: url, format: "wav")
            case "to_aiff":
                out = try MediaConverter.convertAudio(inputURL: url, format: "aiff")
            case "to_flac":
                out = try MediaConverter.convertAudio(inputURL: url, format: "flac")
            case "audio_mono":
                let ext = ["m4a", "wav", "aiff", "flac"].contains(url.pathExtension.lowercased()) ? url.pathExtension.lowercased() : "m4a"
                out = try MediaConverter.convertAudio(inputURL: url, format: ext, forceMono: true)

            // Archives
            case "extract_archive":
                out = try DocumentTools.extractArchive(inputURL: url)

            default:
                throw FlipDocError("Unsupported action tag: \(tag)")
            }
            results.append(out)
        }
        return results
    }

    // MARK: - OCR Interactive Runner

    private func runOCRInteractive(_ urls: [URL]) {
        let first = urls[0]
        OperationProgressHUD.shared.showProgress(
            title: "Vision OCR",
            subtitle: "Recognizing text in \(first.lastPathComponent)…"
        )
        Task { @MainActor in
            do {
                var chunks: [String] = []
                for url in urls {
                    let recognized = try await VisionOCREngine.shared.recognizeText(from: url)
                    if urls.count > 1 {
                        chunks.append("=== \(url.lastPathComponent) ===\n\(recognized)")
                    } else {
                        chunks.append(recognized)
                    }
                }
                let combined = chunks.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
                if combined.isEmpty {
                    OperationProgressHUD.shared.showError(title: "No Text Detected", message: "Vision OCR did not find readable text.")
                    return
                }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(combined, forType: .string)
                SoundAndHaptics.shared.playCompletion()
                OperationProgressHUD.shared.dismiss()
                ToolOptionsWindowController.shared.showOCRResult(text: combined, sourceURL: first)
            } catch {
                OperationProgressHUD.shared.showError(title: "OCR Failed", message: error.localizedDescription)
            }
        }
    }

    private func runQRScanInteractive(_ urls: [URL]) {
        let first = urls[0]
        OperationProgressHUD.shared.showProgress(
            title: "Scanning QR & Barcodes",
            subtitle: "Inspecting \(first.lastPathComponent)…"
        )
        Task { @MainActor in
            do {
                var allPayloads: [String] = []
                for url in urls {
                    let found = try await VisionOCREngine.shared.detectBarcodes(from: url)
                    for item in found where !allPayloads.contains(item) {
                        allPayloads.append(item)
                    }
                }
                if allPayloads.isEmpty {
                    OperationProgressHUD.shared.showError(
                        title: "No QR or Barcode Found",
                        message: "No readable QR code or barcode was detected in \(first.lastPathComponent)."
                    )
                    return
                }
                let joined = allPayloads.joined(separator: "\n")
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(joined, forType: .string)
                SoundAndHaptics.shared.playCompletion()
                OperationProgressHUD.shared.dismiss()
                ToolOptionsWindowController.shared.showQRResult(payloads: allPayloads, sourceURL: first)
            } catch {
                OperationProgressHUD.shared.showError(title: "QR Scan Failed", message: error.localizedDescription)
            }
        }
    }

    // MARK: - File Action Helpers (AirDrop, Move, Terminal)

    private func presentAirDrop(for urls: [URL]) {
        guard let service = NSSharingService(named: .sendViaAirDrop) else {
            OperationProgressHUD.shared.showError(title: "AirDrop Unavailable", message: "macOS AirDrop sharing service is not available.")
            return
        }
        let mouse = NSEvent.mouseLocation
        let anchor = NSWindow(
            contentRect: NSRect(x: mouse.x - 10, y: mouse.y - 10, width: 20, height: 20),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        anchor.isOpaque = false
        anchor.backgroundColor = .clear
        anchor.level = .floating
        anchor.isReleasedWhenClosed = false
        anchor.orderFrontRegardless()
        self.airDropAnchorWindow = anchor

        service.delegate = self
        self.activeSharingService = service
        NSApp.activate(ignoringOtherApps: true)
        service.perform(withItems: urls)
    }

    public nonisolated func sharingService(_ sharingService: NSSharingService, sourceWindowForShareItems items: [Any], sharingContentScope: UnsafeMutablePointer<NSSharingService.SharingContentScope>) -> NSWindow? {
        MainActor.assumeIsolated {
            self.airDropAnchorWindow
        }
    }

    public nonisolated func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        Task { @MainActor in
            self.cleanupAirDrop()
        }
    }

    public nonisolated func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error) {
        Task { @MainActor in
            self.cleanupAirDrop()
        }
    }

    private func cleanupAirDrop() {
        airDropAnchorWindow?.orderOut(nil)
        airDropAnchorWindow = nil
        activeSharingService = nil
    }

    private func moveFilesInteractive(_ urls: [URL]) {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.title = "Choose Destination Folder"
        panel.prompt = "Move Here"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let destFolder = panel.url else { return }

        do {
            var movedURLs: [URL] = []
            for src in urls {
                let ext = src.pathExtension
                let placeholder = destFolder.appendingPathComponent(src.lastPathComponent)
                let finalDest: URL
                if !FileManager.default.fileExists(atPath: placeholder.path) {
                    finalDest = placeholder
                } else {
                    finalDest = OutputNaming.uniqueFileURL(nextTo: placeholder, newExtension: ext)
                }
                try FileManager.default.moveItem(at: src, to: finalDest)
                movedURLs.append(finalDest)
            }
            SoundAndHaptics.shared.playCompletion()
            OperationProgressHUD.shared.showSuccess(
                title: movedURLs.count == 1 ? "Moved \(movedURLs[0].lastPathComponent)" : "Moved \(movedURLs.count) files",
                subtitle: "Into \(destFolder.lastPathComponent)/",
                outputURLs: movedURLs
            )
        } catch {
            OperationProgressHUD.shared.showError(title: "Move Failed", message: error.localizedDescription)
        }
    }

    private func openInTerminal(_ url: URL) {
        var isDir: ObjCBool = false
        let targetDir: URL
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            targetDir = url
        } else {
            targetDir = url.deletingLastPathComponent()
        }
        let terminalURL = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.open([targetDir], withApplicationAt: terminalURL, configuration: config) { _, error in
            if let error = error {
                Task { @MainActor in
                    OperationProgressHUD.shared.showError(title: "Terminal Error", message: error.localizedDescription)
                }
            }
        }
    }
}

