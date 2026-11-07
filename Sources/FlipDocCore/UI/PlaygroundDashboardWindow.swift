import AppKit
import SwiftUI
import UniformTypeIdentifiers
import Combine

/// Generates lightweight local sample files in `~/Library/Caches/FlipDocPlayground` so users can immediately drag or click to test the wheel!
@MainActor
enum SamplePlaygroundFiles {
    struct SampleCard: Identifiable {
        let id: String
        let title: String
        let badge: String
        let icon: String
        let url: URL
    }

    static func prepareSamples() -> [SampleCard] {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("FlipDocPlaygroundSamples", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        var cards: [SampleCard] = []

        // 1. Sample PNG Image
        let pngURL = folder.appendingPathComponent("Studio Poster.png")
        if !FileManager.default.fileExists(atPath: pngURL.path) {
            createSamplePosterPNG(at: pngURL)
        }
        cards.append(SampleCard(id: "png", title: "Studio Poster.png", badge: "IMAGE", icon: "photo.fill", url: pngURL))

        // 2. Sample PDF Invoice
        let pdfURL = folder.appendingPathComponent("Quarterly Invoice.pdf")
        if !FileManager.default.fileExists(atPath: pdfURL.path) {
            createSampleInvoicePDF(at: pdfURL)
        }
        cards.append(SampleCard(id: "pdf", title: "Quarterly Invoice.pdf", badge: "PDF TABLE", icon: "doc.richtext.fill", url: pdfURL))

        // 3. Sample Spreadsheet CSV
        let csvURL = folder.appendingPathComponent("Revenue Metrics.csv")
        if !FileManager.default.fileExists(atPath: csvURL.path) {
            let csv = """
            Month,Plan,MRR,Growth
            January,Pro Studio,"$14,200",+18%
            February,Pro Studio,"$16,850",+19%
            March,Enterprise,"$22,400",+33%
            """
            try? csv.write(to: csvURL, atomically: true, encoding: .utf8)
        }
        cards.append(SampleCard(id: "csv", title: "Revenue Metrics.csv", badge: "SHEET", icon: "tablecells.fill", url: csvURL))

        // 4. Sample SRT Subtitle
        let srtURL = folder.appendingPathComponent("Keynote Captions.srt")
        if !FileManager.default.fileExists(atPath: srtURL.path) {
            let srt = """
            1
            00:00:01,000 --> 00:00:03,800
            Drag any file on your Mac and tap Shift.

            2
            00:00:04,100 --> 00:00:07,200
            Convert locally in milliseconds without cloud uploads.
            """
            try? srt.write(to: srtURL, atomically: true, encoding: .utf8)
        }
        cards.append(SampleCard(id: "srt", title: "Keynote Captions.srt", badge: "SUBTITLE", icon: "captions.bubble.fill", url: srtURL))

        return cards
    }

    private static func createSamplePosterPNG(at url: URL) {
        let width = 800
        let height = 600
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }

        ctx.setFillColor(CGColor(red: 0.98, green: 0.96, blue: 0.93, alpha: 1.0))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        ctx.setFillColor(CGColor(red: 1.0, green: 0.322, blue: 0.0, alpha: 1.0))
        ctx.fillEllipse(in: CGRect(x: 260, y: 180, width: 280, height: 280))

        let str = NSAttributedString(
            string: "FLIPDOC LOCAL STUDIO",
            attributes: [
                .font: NSFont.boldSystemFont(ofSize: 34),
                .foregroundColor: NSColor(calibratedRed: 0.12, green: 0.12, blue: 0.13, alpha: 1)
            ]
        )
        let line = CTLineCreateWithAttributedString(str)
        ctx.textPosition = CGPoint(x: 195, y: 95)
        CTLineDraw(line, ctx)

        if let cg = ctx.makeImage(),
           let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) {
            CGImageDestinationAddImage(dest, cg, nil)
            CGImageDestinationFinalize(dest)
        }
    }

    private static func createSampleInvoicePDF(at url: URL) {
        let rows = [
            ["Item", "Department", "Qty", "Unit Price", "Total"],
            ["Mac Studio M3 Ultra", "Engineering", "2", "$3,999", "$7,998"],
            ["Studio Display", "Design", "3", "$1,599", "$4,797"],
            ["FlipDoc Team License", "Operations", "25", "$29", "$725"]
        ]
        let table = ExtractedTable(page: 1, rows: rows)
        let tmpXlsx = url.deletingLastPathComponent().appendingPathComponent("tmp_inv.xlsx")
        defer { try? FileManager.default.removeItem(at: tmpXlsx) }
        if let _ = try? PDFTableExtractor.exportToXLSX(tables: [table], outputURL: tmpXlsx) {
            _ = try? XLSXtoPDFEngine.convert(inputURL: tmpXlsx, outputURL: url)
        }
    }
}

/// Drop bridge for the Studio Canvas.
@MainActor
private final class StudioDropNSView: NSView {
    var onTargetChanged: ((Bool) -> Void)?
    var onDropped: (([URL]) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL, .URL, NSPasteboard.PasteboardType("NSFilenamesPboardType")])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        onTargetChanged?(true)
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onTargetChanged?(false)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        onTargetChanged?(false)
        let pb = sender.draggingPasteboard
        if let urls = (pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL])?.filter(\.isFileURL),
           !urls.isEmpty {
            onDropped?(urls)
            return true
        }
        return false
    }
}

private struct StudioDropBridge: NSViewRepresentable {
    let onTargetChanged: (Bool) -> Void
    let onDropped: ([URL]) -> Void

    func makeNSView(context: Context) -> StudioDropNSView {
        let v = StudioDropNSView()
        v.onTargetChanged = onTargetChanged
        v.onDropped = onDropped
        return v
    }

    func updateNSView(_ nsView: StudioDropNSView, context: Context) {
        nsView.onTargetChanged = onTargetChanged
        nsView.onDropped = onDropped
    }
}

@MainActor
final class LiveModifierKeyObserver: ObservableObject {
    @Published var heldMode: ModifierMode? = nil
    @Published var samples: [SamplePlaygroundFiles.SampleCard] = []
    @Published var isDropTargeted: Bool = false
    private var localMonitor: Any?
    private var globalMonitor: Any?

    func start() {
        stop()
        let update: (NSEvent.ModifierFlags) -> Void = { [weak self] flags in
            let clean = flags.intersection(.deviceIndependentFlagsMask)
            if clean == .shift { self?.heldMode = .conversions }
            else if clean == .command { self?.heldMode = .tools }
            else if clean == .control { self?.heldMode = .actions }
            else { self?.heldMode = nil }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            update(event.modifierFlags)
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { event in
            MainActor.assumeIsolated {
                update(event.modifierFlags)
            }
        }
    }

    func stop() {
        if let l = localMonitor { NSEvent.removeMonitor(l); localMonitor = nil }
        if let g = globalMonitor { NSEvent.removeMonitor(g); globalMonitor = nil }
    }
}

public struct PlaygroundDashboardView: View {
    @ObservedObject private var prefs = AppPreferences.shared
    @StateObject private var keyObserver = LiveModifierKeyObserver()
    @Environment(\.colorScheme) private var scheme

    public init() {}

    public var body: some View {
        VStack(spacing: 18) {
            // Top Hero Bar (FlipDoc Studio Aesthetic)
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [FlipDocTheme.orange, FlipDocTheme.warmOrange],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 46, height: 46)
                        .shadow(color: FlipDocTheme.orange.opacity(0.32), radius: 8, x: 0, y: 4)

                    Image(systemName: "circle.hexagongrid.fill")
                        .font(.system(size: 21, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text("FlipDoc")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                        Text("LOCAL · ZERO-CLOUD")
                            .font(.system(size: 9.5, weight: .bold, design: .rounded))
                            .tracking(0.6)
                            .foregroundStyle(FlipDocTheme.orange)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2.5)
                            .background(Capsule().fill(FlipDocTheme.orange.opacity(0.14)))
                    }
                    Text("Drag any file in Finder, tap a modifier key, and drop on a petal.")
                        .font(.system(size: 12.5, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 8) {
                    Button(action: { FloatingShelfManager.shared.toggleWindow() }) {
                        Label("Float Shelf", systemImage: "pin.fill")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                    }
                    .buttonStyle(.bordered)

                    Button(action: { SettingsWindowController.shared.show() }) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 13))
                    }
                    .buttonStyle(.bordered)
                    .help("Settings")
                }
            }

            // Live Interactive Modifier Keycaps (lights up when user presses Shift, Cmd, or Ctrl!)
            HStack(spacing: 12) {
                liveKeycapCard(
                    mode: .conversions,
                    keyName: "⇧ Shift",
                    title: "Convert Formats",
                    detail: "PNG · WEBP · HEIC · XLSX · DOCX · MP4 · GIF"
                )
                liveKeycapCard(
                    mode: .tools,
                    keyName: "⌘ Command",
                    title: "Quick Tools",
                    detail: "Compress · Resize · OCR · Split/Merge · Mute"
                )
                liveKeycapCard(
                    mode: .actions,
                    keyName: "⌃ Control",
                    title: "File Actions",
                    detail: "Float · AirDrop · Copy · Move · Copy Path · Terminal"
                )
            }

            // Interactive Drop & Sample Playground Card
            VStack(spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Try It Right Here")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                        Text("Drag a sample card below and tap ⇧ Shift — or drop any real files onto this canvas")
                            .font(.system(size: 11.5, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(action: chooseFilesWithOpenPanel) {
                        Label("Choose Files…", systemImage: "plus.circle.fill")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 6.5)
                            .background(Capsule().fill(FlipDocTheme.orange))
                    }
                    .buttonStyle(.plain)
                }

                // 4 Draggable + Clickable Sample Cards
                HStack(spacing: 10) {
                    ForEach(keyObserver.samples) { sample in
                        samplePracticeCard(sample)
                    }
                }
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(FlipDocTheme.cardBackground(for: scheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        keyObserver.isDropTargeted ? FlipDocTheme.orange : FlipDocTheme.cardBorder(for: scheme),
                        lineWidth: keyObserver.isDropTargeted ? 2.2 : 1.0
                    )
            )
            .overlay(
                StudioDropBridge(
                    onTargetChanged: { keyObserver.isDropTargeted = $0 },
                    onDropped: { urls in
                        RadialOverlayWindow.shared.show(
                            at: NSEvent.mouseLocation,
                            for: urls,
                            mode: .conversions,
                            isDragSession: false
                        )
                    }
                )
            )

            // Bottom Split: Quick Toggles + Recent Conversions
            HStack(alignment: .top, spacing: 14) {
                // Quick Toggles
                VStack(alignment: .leading, spacing: 11) {
                    Text("QUICK CONTROLS")
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        .tracking(0.6)
                        .foregroundStyle(.secondary)

                    Toggle("Drag Modifier Wheel", isOn: $prefs.dragModifiersEnabled)
                        .toggleStyle(.switch)
                        .tint(FlipDocTheme.orange)
                        .font(.system(size: 12.5, weight: .medium, design: .rounded))

                    Toggle("Desktop Drop Zone", isOn: $prefs.showDesktopDropZone)
                        .toggleStyle(.switch)
                        .tint(FlipDocTheme.orange)
                        .font(.system(size: 12.5, weight: .medium, design: .rounded))

                    Toggle("Tick Sounds & Haptics", isOn: $prefs.soundsAndHapticsEnabled)
                        .toggleStyle(.switch)
                        .tint(FlipDocTheme.orange)
                        .font(.system(size: 12.5, weight: .medium, design: .rounded))

                    Spacer(minLength: 0)
                }
                .padding(15)
                .frame(width: 225, height: 158)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(FlipDocTheme.cardBackground(for: scheme)))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(FlipDocTheme.cardBorder(for: scheme), lineWidth: 1))

                // Recent Conversions
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("RECENT OUTPUTS")
                            .font(.system(size: 10.5, weight: .bold, design: .rounded))
                            .tracking(0.6)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if !prefs.recentRecords.isEmpty {
                            Button("Clear") {
                                prefs.clearHistory()
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                        }
                    }

                    if prefs.recentRecords.isEmpty {
                        VStack(spacing: 4) {
                            Spacer()
                            Text("Converted files will appear here")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                            Text("Originals are never overwritten — outputs save right beside your file.")
                                .font(.system(size: 10.5, design: .rounded))
                                .foregroundStyle(.tertiary)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(spacing: 6) {
                                ForEach(prefs.recentRecords.prefix(8)) { rec in
                                    HStack(spacing: 8) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 12))
                                            .foregroundStyle(FlipDocTheme.orange)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(rec.outputName)
                                                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                                                .lineLimit(1)
                                            Text(rec.actionSummary)
                                                .font(.system(size: 10, design: .rounded))
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        if rec.existsOnDisk {
                                            Button("Float") {
                                                FloatingShelfManager.shared.pinFiles([rec.outputURL])
                                            }
                                            .buttonStyle(.bordered)
                                            .controlSize(.mini)

                                            Button("Reveal") {
                                                NSWorkspace.shared.activateFileViewerSelecting([rec.outputURL])
                                            }
                                            .buttonStyle(.bordered)
                                            .controlSize(.mini)
                                        }
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                        }
                    }
                }
                .padding(15)
                .frame(maxWidth: .infinity)
                .frame(height: 158)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(FlipDocTheme.cardBackground(for: scheme)))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(FlipDocTheme.cardBorder(for: scheme), lineWidth: 1))
            }
        }
        .padding(22)
        .frame(width: 720, height: 540)
        .background(FlipDocTheme.canvasBackground(for: scheme))
        .onAppear {
            keyObserver.samples = SamplePlaygroundFiles.prepareSamples()
            keyObserver.start()
        }
        .onDisappear {
            keyObserver.stop()
        }
    }

    private func liveKeycapCard(mode: ModifierMode, keyName: String, title: String, detail: String) -> some View {
        let isHeld = keyObserver.heldMode == mode
        return VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(keyName)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(isHeld ? .white : FlipDocTheme.warmOrange)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(isHeld ? FlipDocTheme.orange : FlipDocTheme.orange.opacity(0.12))
                    )
                Spacer()
                if isHeld {
                    Text("ACTIVE")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(FlipDocTheme.orange)
                }
            }
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
            Text(detail)
                .font(.system(size: 10.5, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(isHeld ? FlipDocTheme.orange.opacity(0.09) : FlipDocTheme.cardBackground(for: scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(isHeld ? FlipDocTheme.orange : FlipDocTheme.cardBorder(for: scheme), lineWidth: isHeld ? 1.8 : 1.0)
        )
        .animation(.easeOut(duration: 0.12), value: isHeld)
    }

    private func samplePracticeCard(_ sample: SamplePlaygroundFiles.SampleCard) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(FlipDocTheme.orange.opacity(0.12))
                        .frame(width: 32, height: 32)
                    Image(systemName: sample.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(FlipDocTheme.orange)
                }
                Spacer()
                Text(sample.badge)
                    .font(.system(size: 8.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.primary.opacity(0.06)))
            }

            Text(sample.title)
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .lineLimit(1)

            Text("Drag + ⇧ or Click")
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(FlipDocTheme.warmOrange)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .overlay(
            NativeFileDragSourceBridge(
                urls: [sample.url],
                onSingleClick: {
                    RadialOverlayWindow.shared.show(
                        at: NSEvent.mouseLocation,
                        for: [sample.url],
                        mode: keyObserver.heldMode ?? .conversions,
                        isDragSession: false
                    )
                },
                onDoubleClick: {
                    NSWorkspace.shared.open(sample.url)
                }
            )
        )
    }

    private func chooseFilesWithOpenPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Open Radial Wheel"
        if panel.runModal() == .OK, !panel.urls.isEmpty {
            let centerPt = NSEvent.mouseLocation
            RadialOverlayWindow.shared.show(
                at: centerPt,
                for: panel.urls,
                mode: .conversions,
                isDragSession: false
            )
        }
    }
}

@MainActor
public final class PlaygroundDashboardWindowController {
    public static let shared = PlaygroundDashboardWindowController()

    private var window: NSWindow?

    private init() {}

    public func show() {
        if window == nil {
            let host = NSHostingController(rootView: PlaygroundDashboardView())
            let w = NSWindow(contentViewController: host)
            w.title = "FlipDoc Studio"
            w.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
            w.titlebarAppearsTransparent = true
            w.isMovableByWindowBackground = true
            w.isReleasedWhenClosed = false
            w.center()
            self.window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
