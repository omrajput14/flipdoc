import AppKit
import SwiftUI
import PDFKit
import UniformTypeIdentifiers
import Combine

// MARK: - 1. Compress Options Sheet (Images & PDFs)

@MainActor
private final class CompressSheetModel: ObservableObject {
    @Published var quality: Double = AppPreferences.shared.imageCompressionQuality
    @Published var maxDimensionChoice: Int = 0
    @Published var isProcessing: Bool = false
}

private struct CompressToolSheetView: View {
    let urls: [URL]
    let onDismiss: () -> Void

    @StateObject private var model = CompressSheetModel()

    private var isImageMode: Bool {
        urls.first.map { FileCategory.classify(url: $0) == .image } ?? true
    }

    private var totalOriginalBytes: Int64 {
        urls.reduce(0) { acc, url in
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
            return acc + size
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            sheetHeader(
                icon: "arrow.down.right.and.arrow.up.left",
                title: isImageMode ? "Compress Image\(urls.count > 1 ? "s" : "")" : "Compress PDF\(urls.count > 1 ? "s" : "")",
                subtitle: "\(urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) files") · Original \(ByteCountFormatter.string(fromByteCount: totalOriginalBytes, countStyle: .file))"
            )

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Compression Quality")
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    Spacer()
                    Text("\(Int((model.quality * 100).rounded()))%")
                        .font(.system(size: 12.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(FlipDocTheme.orange)
                }

                Slider(value: $model.quality, in: 0.15...0.95, step: 0.01)
                    .tint(FlipDocTheme.orange)

                HStack(spacing: 8) {
                    presetPill("Max Savings (42%)", active: abs(model.quality - 0.42) < 0.03) { model.quality = 0.42 }
                    presetPill("Balanced (70%)", active: abs(model.quality - 0.70) < 0.03) { model.quality = 0.70 }
                    presetPill("High Quality (88%)", active: abs(model.quality - 0.88) < 0.03) { model.quality = 0.88 }
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.04)))

            if isImageMode {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Max Pixel Dimension")
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    Picker("", selection: $model.maxDimensionChoice) {
                        Text("Original").tag(0)
                        Text("2560 px").tag(2560)
                        Text("1920 px").tag(1920)
                        Text("1280 px").tag(1280)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.04)))
            }

            Spacer(minLength: 4)

            HStack {
                Button("Cancel", action: onDismiss)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(action: runCompression) {
                    HStack(spacing: 6) {
                        if model.isProcessing {
                            ProgressView().controlSize(.small)
                        }
                        Text(model.isProcessing ? "Compressing…" : "Compress & Save")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(FlipDocTheme.orange))
                }
                .buttonStyle(.plain)
                .disabled(model.isProcessing)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 430, height: isImageMode ? 330 : 256)
    }

    private func runCompression() {
        model.isProcessing = true
        AppPreferences.shared.imageCompressionQuality = model.quality
        let chosenQuality = model.quality
        let maxDim = model.maxDimensionChoice > 0 ? model.maxDimensionChoice : nil
        let targetURLs = urls

        Task { @MainActor in
            do {
                var outputs: [URL] = []
                for url in targetURLs {
                    if FileCategory.classify(url: url) == .pdf {
                        let out = try DocumentTools.compressPDF(inputURL: url, quality: chosenQuality)
                        outputs.append(out)
                        AppPreferences.shared.recordConversion(sourceName: url.lastPathComponent, outputURL: out, summary: "Compressed PDF")
                    } else {
                        let out = try await ImageTransformer.compress(inputURL: url, quality: chosenQuality, maxDimension: maxDim)
                        outputs.append(out)
                        AppPreferences.shared.recordConversion(sourceName: url.lastPathComponent, outputURL: out, summary: "Compressed Image")
                    }
                }
                let outBytes = outputs.reduce(Int64(0)) { acc, u in
                    acc + ((try? FileManager.default.attributesOfItem(atPath: u.path)[.size] as? Int64) ?? 0)
                }
                let savedPct = totalOriginalBytes > 0
                    ? max(0, Int(((Double(totalOriginalBytes - outBytes) / Double(totalOriginalBytes)) * 100).rounded()))
                    : 0
                let detail = savedPct > 0
                    ? "\(ByteCountFormatter.string(fromByteCount: outBytes, countStyle: .file)) (-\(savedPct)%)"
                    : ByteCountFormatter.string(fromByteCount: outBytes, countStyle: .file)

                SoundAndHaptics.shared.playCompletion()
                onDismiss()
                OperationProgressHUD.shared.showSuccess(
                    title: outputs.count == 1 ? "Saved \(outputs[0].lastPathComponent)" : "Compressed \(outputs.count) files",
                    subtitle: detail,
                    outputURLs: outputs
                )
                if AppPreferences.shared.autoFloatOutputs {
                    FloatingShelfManager.shared.pinFiles(outputs)
                }
                if AppPreferences.shared.autoRevealInFinder {
                    NSWorkspace.shared.activateFileViewerSelecting(outputs)
                }
            } catch {
                model.isProcessing = false
                OperationProgressHUD.shared.showError(title: "Compression Failed", message: error.localizedDescription)
            }
        }
    }
}

// MARK: - 2. Resize & Frame Image Sheet (Resize + Round Corners + Add BG)

private enum FrameBackdropPreset: String, CaseIterable {
    case none = "None"
    case white = "White"
    case warm = "Studio"
    case dark = "Dark"
    case accent = "Orange"

    var swiftUIColor: Color {
        switch self {
        case .none: return .clear
        case .white: return .white
        case .warm: return Color(red: 0.957, green: 0.957, blue: 0.953)
        case .dark: return Color(red: 0.11, green: 0.12, blue: 0.13)
        case .accent: return FlipDocTheme.orange
        }
    }

    var cgColor: CGColor? {
        switch self {
        case .none: return nil
        case .white: return CGColor(red: 1, green: 1, blue: 1, alpha: 1)
        case .warm: return CGColor(red: 0.957, green: 0.957, blue: 0.953, alpha: 1)
        case .dark: return CGColor(red: 0.11, green: 0.12, blue: 0.13, alpha: 1)
        case .accent: return CGColor(red: 1.0, green: 0.322, blue: 0.0, alpha: 1)
        }
    }
}

@MainActor
private final class ResizeSheetModel: ObservableObject {
    @Published var origWidth: Int = 1200
    @Published var origHeight: Int = 800
    @Published var targetWidth: Int = 1200
    @Published var targetHeight: Int = 800
    @Published var lockAspect: Bool = true
    @Published var cornerRadius: Double = 0
    @Published var padding: Double = 0
    @Published var backdrop: FrameBackdropPreset = .none
    @Published var previewImage: NSImage? = nil
    @Published var isSaving: Bool = false

    var aspectRatio: Double {
        guard origHeight > 0 else { return 1.0 }
        return Double(origWidth) / Double(origHeight)
    }
}

private struct ResizeFrameToolSheetView: View {
    let urls: [URL]
    let onDismiss: () -> Void

    @StateObject private var model = ResizeSheetModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            sheetHeader(
                icon: "crop",
                title: "Resize & Frame Image\(urls.count > 1 ? "s" : "")",
                subtitle: "Original \(model.origWidth) × \(model.origHeight) px"
            )

            HStack(spacing: 16) {
                // Live Interactive Preview
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.primary.opacity(0.05))

                    ZStack {
                        if model.backdrop != .none {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(model.backdrop.swiftUIColor)
                        }
                        if let img = model.previewImage {
                            Image(nsImage: img)
                                .resizable()
                                .scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: CGFloat(model.cornerRadius * 0.25), style: .continuous))
                                .padding(CGFloat(model.padding * 0.22))
                        }
                    }
                    .padding(12)
                }
                .frame(width: 176, height: 176)

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Width (px)").font(.system(size: 10.5, weight: .medium)).foregroundStyle(.secondary)
                            TextField("Width", value: Binding(
                                get: { model.targetWidth },
                                set: { newW in
                                    let clamped = max(16, min(12000, newW))
                                    model.targetWidth = clamped
                                    if model.lockAspect {
                                        model.targetHeight = max(16, Int((Double(clamped) / model.aspectRatio).rounded()))
                                    }
                                }
                            ), format: .number)
                            .textFieldStyle(.roundedBorder)
                        }

                        Button(action: { model.lockAspect.toggle() }) {
                            Image(systemName: model.lockAspect ? "lock.fill" : "lock.open")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(model.lockAspect ? FlipDocTheme.orange : .secondary)
                                .padding(.top, 14)
                        }
                        .buttonStyle(.plain)
                        .help("Lock Aspect Ratio")

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Height (px)").font(.system(size: 10.5, weight: .medium)).foregroundStyle(.secondary)
                            TextField("Height", value: Binding(
                                get: { model.targetHeight },
                                set: { newH in
                                    let clamped = max(16, min(12000, newH))
                                    model.targetHeight = clamped
                                    if model.lockAspect {
                                        model.targetWidth = max(16, Int((Double(clamped) * model.aspectRatio).rounded()))
                                    }
                                }
                            ), format: .number)
                            .textFieldStyle(.roundedBorder)
                        }
                    }

                    HStack(spacing: 6) {
                        presetPill("50%", active: false) {
                            model.targetWidth = max(16, model.origWidth / 2)
                            model.targetHeight = max(16, model.origHeight / 2)
                        }
                        presetPill("75%", active: false) {
                            model.targetWidth = max(16, Int(Double(model.origWidth) * 0.75))
                            model.targetHeight = max(16, Int(Double(model.origHeight) * 0.75))
                        }
                        presetPill("1080p", active: false) {
                            model.targetWidth = 1920
                            model.targetHeight = model.lockAspect ? max(16, Int((1920.0 / model.aspectRatio).rounded())) : 1080
                        }
                        presetPill("1:1", active: false) {
                            model.lockAspect = false
                            model.targetWidth = 1080
                            model.targetHeight = 1080
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Round Corners").font(.system(size: 11, weight: .medium))
                            Spacer()
                            Text("\(Int(model.cornerRadius)) px").font(.system(size: 10.5, design: .monospaced)).foregroundStyle(.secondary)
                        }
                        Slider(value: $model.cornerRadius, in: 0...64, step: 2).tint(FlipDocTheme.orange)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Frame Padding").font(.system(size: 11, weight: .medium))
                            Spacer()
                            Text("\(Int(model.padding)) px").font(.system(size: 10.5, design: .monospaced)).foregroundStyle(.secondary)
                        }
                        Slider(value: $model.padding, in: 0...96, step: 4).tint(FlipDocTheme.orange)
                    }
                }
            }

            HStack(spacing: 8) {
                Text("Background:")
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                ForEach(FrameBackdropPreset.allCases, id: \.rawValue) { item in
                    presetPill(item.rawValue, active: model.backdrop == item) {
                        model.backdrop = item
                        if item != .none && model.padding == 0 {
                            model.padding = 36
                        }
                    }
                }
            }

            HStack {
                Button("Cancel", action: onDismiss)
                Spacer()
                Button(action: applyResize) {
                    Text(model.isSaving ? "Saving…" : "Save Copy")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(FlipDocTheme.orange))
                }
                .buttonStyle(.plain)
                .disabled(model.isSaving)
            }
        }
        .padding(22)
        .frame(width: 500, height: 365)
        .onAppear {
            if let first = urls.first, let cg = try? ImageTransformer.loadOrientedCGImage(from: first) {
                model.origWidth = cg.width
                model.origHeight = cg.height
                model.targetWidth = cg.width
                model.targetHeight = cg.height
                model.previewImage = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            }
        }
    }

    private func applyResize() {
        model.isSaving = true
        let w = model.targetWidth
        let h = model.targetHeight
        let rad = CGFloat(model.cornerRadius)
        let pad = CGFloat(model.padding)
        let bg = model.backdrop.cgColor
        let targets = urls

        Task { @MainActor in
            do {
                var outputs: [URL] = []
                for url in targets {
                    let out = try ImageTransformer.resizeAndFrame(
                        inputURL: url,
                        targetWidth: w,
                        targetHeight: h,
                        cornerRadius: rad,
                        padding: pad,
                        backgroundColor: bg
                    )
                    outputs.append(out)
                    AppPreferences.shared.recordConversion(sourceName: url.lastPathComponent, outputURL: out, summary: "Resized (\(w)×\(h))")
                }
                SoundAndHaptics.shared.playCompletion()
                onDismiss()
                OperationProgressHUD.shared.showSuccess(
                    title: outputs.count == 1 ? "Saved \(outputs[0].lastPathComponent)" : "Resized \(outputs.count) images",
                    subtitle: "\(w) × \(h) px",
                    outputURLs: outputs
                )
            } catch {
                model.isSaving = false
                OperationProgressHUD.shared.showError(title: "Resize Failed", message: error.localizedDescription)
            }
        }
    }
}

// MARK: - 3. Organize / Merge PDF Sheet

private struct OrganizePDFPageItem: Identifiable {
    let id = UUID()
    let sourceURL: URL
    let sourcePageIndex: Int
    var rotationDegrees: Int
    let thumbnail: NSImage
}

@MainActor
private final class OrganizePDFSheetModel: ObservableObject {
    @Published var pages: [OrganizePDFPageItem] = []
    @Published var selectedID: UUID? = nil
}

private struct OrganizePDFSheetView: View {
    let initialURLs: [URL]
    let onDismiss: () -> Void

    @StateObject private var model = OrganizePDFSheetModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                sheetHeader(
                    icon: "square.grid.2x2",
                    title: "Organize & Merge PDF",
                    subtitle: "\(model.pages.count) page\(model.pages.count == 1 ? "" : "s") · Click a page to rotate, reorder, or remove"
                )
                Spacer()
                Button(action: addMorePDFs) {
                    Label("Add PDFs…", systemImage: "plus")
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.primary.opacity(0.08)))
                }
                .buttonStyle(.plain)
            }

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 118), spacing: 12)], spacing: 12) {
                    ForEach(Array(model.pages.enumerated()), id: \.element.id) { idx, item in
                        let isSelected = model.selectedID == item.id
                        VStack(spacing: 6) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.white)
                                    .shadow(color: .black.opacity(0.10), radius: 4, x: 0, y: 2)

                                Image(nsImage: item.thumbnail)
                                    .resizable()
                                    .scaledToFit()
                                    .rotationEffect(.degrees(Double(item.rotationDegrees)))
                                    .padding(6)
                            }
                            .frame(height: 128)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(isSelected ? FlipDocTheme.orange : Color.clear, lineWidth: 2.2)
                            )

                            Text("\(idx + 1). \(item.sourceURL.deletingPathExtension().lastPathComponent)")
                                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                                .lineLimit(1)

                            HStack(spacing: 6) {
                                miniIconButton("chevron.left", disabled: idx == 0) {
                                    model.pages.swapAt(idx, idx - 1)
                                }
                                miniIconButton("rotate.right", disabled: false) {
                                    model.pages[idx].rotationDegrees = (model.pages[idx].rotationDegrees + 90) % 360
                                }
                                miniIconButton("trash", disabled: model.pages.count <= 1) {
                                    model.pages.remove(at: idx)
                                }
                                miniIconButton("chevron.right", disabled: idx >= model.pages.count - 1) {
                                    model.pages.swapAt(idx, idx + 1)
                                }
                            }
                        }
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(isSelected ? FlipDocTheme.orange.opacity(0.09) : Color.primary.opacity(0.03))
                        )
                        .onTapGesture {
                            model.selectedID = item.id
                        }
                    }
                }
                .padding(4)
            }
            .frame(maxHeight: .infinity)

            HStack {
                Button("Cancel", action: onDismiss)
                Spacer()
                Button(action: saveOrganizedPDF) {
                    Text("Save PDF (\(model.pages.count) pages)")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(FlipDocTheme.orange))
                }
                .buttonStyle(.plain)
                .disabled(model.pages.isEmpty)
            }
        }
        .padding(22)
        .frame(width: 560, height: 440)
        .onAppear {
            appendPages(from: initialURLs)
        }
    }

    private func miniIconButton(_ sysName: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: sysName)
                .font(.system(size: 9.5, weight: .bold))
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.primary.opacity(0.07)))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1.0)
    }

    private func appendPages(from urls: [URL]) {
        for url in urls {
            guard let doc = PDFDocument(url: url) else { continue }
            for i in 0..<doc.pageCount {
                guard let page = doc.page(at: i) else { continue }
                let thumb = page.thumbnail(of: NSSize(width: 180, height: 240), for: .mediaBox)
                model.pages.append(OrganizePDFPageItem(
                    sourceURL: url,
                    sourcePageIndex: i,
                    rotationDegrees: page.rotation,
                    thumbnail: thumb
                ))
            }
        }
    }

    private func addMorePDFs() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            appendPages(from: panel.urls)
        }
    }

    private func saveOrganizedPDF() {
        guard let firstSource = model.pages.first?.sourceURL else { return }
        let outDoc = PDFDocument()
        var cachedDocs: [URL: PDFDocument] = [:]

        for (outIndex, item) in model.pages.enumerated() {
            let srcDoc: PDFDocument
            if let existing = cachedDocs[item.sourceURL] {
                srcDoc = existing
            } else if let loaded = PDFDocument(url: item.sourceURL) {
                cachedDocs[item.sourceURL] = loaded
                srcDoc = loaded
            } else {
                continue
            }
            if let pageCopy = srcDoc.page(at: item.sourcePageIndex)?.copy() as? PDFPage {
                pageCopy.rotation = item.rotationDegrees
                outDoc.insert(pageCopy, at: outIndex)
            }
        }

        let suffix = initialURLs.count > 1 ? "Merged" : "Organized"
        let outURL = OutputNaming.uniqueFileURL(nextTo: firstSource, suffix: suffix, newExtension: "pdf")
        if outDoc.write(to: outURL) {
            AppPreferences.shared.recordConversion(sourceName: firstSource.lastPathComponent, outputURL: outURL, summary: "Organized PDF (\(outDoc.pageCount)p)")
            SoundAndHaptics.shared.playCompletion()
            onDismiss()
            OperationProgressHUD.shared.showSuccess(
                title: "Saved \(outURL.lastPathComponent)",
                subtitle: "\(outDoc.pageCount) pages",
                outputURLs: [outURL]
            )
        } else {
            OperationProgressHUD.shared.showError(title: "PDF Save Failed", message: "Could not write PDF to disk.")
        }
    }
}

// MARK: - 4. Metadata Inspector & Privacy Scrubber Sheet

@MainActor
private final class MetadataSheetModel: ObservableObject {
    @Published var metadataPairs: [(String, String)] = []
}

private struct MetadataInspectorSheetView: View {
    let urls: [URL]
    let onDismiss: () -> Void

    @StateObject private var model = MetadataSheetModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            sheetHeader(
                icon: "tag.slash",
                title: "Metadata & Privacy Inspector",
                subtitle: urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) images selected"
            )

            ScrollView {
                VStack(spacing: 0) {
                    if model.metadataPairs.isEmpty {
                        Text("No EXIF / GPS camera tags found in this file.")
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(24)
                    } else {
                        ForEach(Array(model.metadataPairs.enumerated()), id: \.offset) { idx, pair in
                            HStack {
                                Text(pair.0)
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundStyle(pair.0.contains("GPS") ? FlipDocTheme.orange : .primary)
                                Spacer()
                                Text(pair.1)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.trailing)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(idx.isMultiple(of: 2) ? Color.primary.opacity(0.03) : Color.clear)
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
            }

            HStack {
                Button("Close", action: onDismiss)
                Spacer()
                Button(action: stripAndSave) {
                    Label("Save Copy Without Metadata", systemImage: "shield.lefthalf.filled")
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(FlipDocTheme.orange))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(22)
        .frame(width: 440, height: 340)
        .onAppear {
            if let first = urls.first {
                model.metadataPairs = ImageTransformer.inspectMetadata(url: first)
            }
        }
    }

    private func stripAndSave() {
        do {
            var outputs: [URL] = []
            for url in urls {
                let out = try ImageTransformer.stripMetadata(inputURL: url)
                outputs.append(out)
                AppPreferences.shared.recordConversion(sourceName: url.lastPathComponent, outputURL: out, summary: "Stripped Metadata")
            }
            SoundAndHaptics.shared.playCompletion()
            onDismiss()
            OperationProgressHUD.shared.showSuccess(
                title: outputs.count == 1 ? "Saved \(outputs[0].lastPathComponent)" : "Cleaned \(outputs.count) images",
                subtitle: "EXIF, GPS & camera tags removed",
                outputURLs: outputs
            )
        } catch {
            OperationProgressHUD.shared.showError(title: "Strip Metadata Failed", message: error.localizedDescription)
        }
    }
}

// MARK: - 5. Vision OCR Result Sheet

@MainActor
private final class OCRSheetModel: ObservableObject {
    @Published var extractedText: String
    @Published var didCopy: Bool = true

    init(text: String) {
        self.extractedText = text
    }
}

private struct OCRResultSheetView: View {
    let sourceURL: URL
    let onDismiss: () -> Void
    @StateObject private var model: OCRSheetModel

    init(sourceURL: URL, extractedText: String, onDismiss: @escaping () -> Void) {
        self.sourceURL = sourceURL
        self.onDismiss = onDismiss
        self._model = StateObject(wrappedValue: OCRSheetModel(text: extractedText))
    }

    private var wordCount: Int {
        model.extractedText.split { $0.isWhitespace || $0.isNewline }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                sheetHeader(
                    icon: "text.viewfinder",
                    title: "Extracted Text (Apple Vision OCR)",
                    subtitle: "\(sourceURL.lastPathComponent) · \(wordCount) words · Copied to clipboard"
                )
                Spacer()
            }

            TextEditor(text: $model.extractedText)
                .font(.system(size: 12.5, design: .monospaced))
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.04)))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                )

            HStack(spacing: 8) {
                Button("Close", action: onDismiss)
                Spacer()

                Button("Save .txt") {
                    saveText(ext: "txt")
                }
                .buttonStyle(.bordered)

                Button("Save .md") {
                    saveText(ext: "md")
                }
                .buttonStyle(.bordered)

                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.extractedText, forType: .string)
                    model.didCopy = true
                }) {
                    Label(model.didCopy ? "Copied!" : "Copy Text", systemImage: "doc.on.doc")
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(FlipDocTheme.orange))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(22)
        .frame(width: 520, height: 390)
    }

    private func saveText(ext: String) {
        let outURL = OutputNaming.uniqueFileURL(nextTo: sourceURL, suffix: "OCR", newExtension: ext)
        do {
            try model.extractedText.write(to: outURL, atomically: true, encoding: .utf8)
            AppPreferences.shared.recordConversion(sourceName: sourceURL.lastPathComponent, outputURL: outURL, summary: "OCR to .\(ext)")
            SoundAndHaptics.shared.playCompletion()
            onDismiss()
            OperationProgressHUD.shared.showSuccess(
                title: "Saved \(outURL.lastPathComponent)",
                subtitle: "\(wordCount) words",
                outputURLs: [outURL]
            )
        } catch {
            OperationProgressHUD.shared.showError(title: "Save Failed", message: error.localizedDescription)
        }
    }
}

// MARK: - Shared Header & Pill Helpers

@MainActor
private func sheetHeader(icon: String, title: String, subtitle: String) -> some View {
    HStack(spacing: 12) {
        ZStack {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(FlipDocTheme.orange.opacity(0.14))
                .frame(width: 38, height: 38)
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(FlipDocTheme.orange)
        }
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 15, weight: .bold, design: .rounded))
            Text(subtitle)
                .font(.system(size: 11.5, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

@MainActor
private func presetPill(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Text(title)
            .font(.system(size: 11, weight: active ? .semibold : .medium, design: .rounded))
            .foregroundStyle(active ? .white : .primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(active ? FlipDocTheme.orange : Color.primary.opacity(0.07))
            )
    }
    .buttonStyle(.plain)
}

// MARK: - Window Controller (`FileToolOptionsWindowController`)

@MainActor
public final class ToolOptionsWindowController {
    public static let shared = ToolOptionsWindowController()

    private var activeWindow: NSWindow?

    private init() {}

    public func showCompress(urls: [URL]) {
        presentWindow(title: "Compress") { [weak self] in
            CompressToolSheetView(urls: urls, onDismiss: { self?.close() })
        }
    }

    public func showResize(urls: [URL]) {
        presentWindow(title: "Resize & Frame") { [weak self] in
            ResizeFrameToolSheetView(urls: urls, onDismiss: { self?.close() })
        }
    }

    public func showOrganizePDF(urls: [URL]) {
        presentWindow(title: "Organize & Merge PDF") { [weak self] in
            OrganizePDFSheetView(initialURLs: urls, onDismiss: { self?.close() })
        }
    }

    public func showMetadataInspector(urls: [URL]) {
        presentWindow(title: "Metadata Inspector") { [weak self] in
            MetadataInspectorSheetView(urls: urls, onDismiss: { self?.close() })
        }
    }

    public func showOCRResult(text: String, sourceURL: URL) {
        presentWindow(title: "Vision OCR") { [weak self] in
            OCRResultSheetView(sourceURL: sourceURL, extractedText: text, onDismiss: { self?.close() })
        }
    }

    public func close() {
        activeWindow?.orderOut(nil)
        activeWindow = nil
    }

    private func presentWindow<Content: View>(title: String, @ViewBuilder content: () -> Content) {
        activeWindow?.orderOut(nil)
        let host = NSHostingController(rootView: content())
        let win = NSWindow(contentViewController: host)
        win.title = title
        win.styleMask = [.titled, .closable, .fullSizeContentView]
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.isMovableByWindowBackground = true
        win.level = .floating
        win.isReleasedWhenClosed = false
        win.center()
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
        self.activeWindow = win
    }
}
