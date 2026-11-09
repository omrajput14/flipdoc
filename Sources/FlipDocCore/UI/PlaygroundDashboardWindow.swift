import AppKit
import SwiftUI
import UniformTypeIdentifiers
import PDFKit
import Combine

/// Generates ready-to-drag sample files inside `~/Library/Application Support/FlipDoc/Samples/`
/// so users can immediately test Image, PDF, Audio, Spreadsheet, Subtitle, and QR workflows inside MELD Studio.
@MainActor
public enum SamplePlaygroundFiles {
    public struct SampleCard: Identifiable {
        public let id: String
        public let title: String
        public let badge: String
        public let icon: String
        public let category: FileCategory
        public let url: URL
    }

    public static func prepareSamples() -> [SampleCard] {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory
        let folder = appSupport.appendingPathComponent("FlipDoc/Samples", isDirectory: true)
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)

        var cards: [SampleCard] = []

        // 1. Sample Image (`landscape.png`)
        let imgURL = folder.appendingPathComponent("landscape.png")
        if !fm.fileExists(atPath: imgURL.path) {
            createSamplePosterPNG(at: imgURL)
        }
        cards.append(SampleCard(id: "img", title: "landscape.png", badge: "IMAGE", icon: "photo.fill", category: .image, url: imgURL))

        // 2. Sample PDF with Table + PII (`field-notes.pdf`)
        let pdfURL = folder.appendingPathComponent("field-notes.pdf")
        if !fm.fileExists(atPath: pdfURL.path) {
            createSampleInvoicePDF(at: pdfURL)
        }
        cards.append(SampleCard(id: "pdf", title: "field-notes.pdf", badge: "PDF", icon: "doc.richtext.fill", category: .pdf, url: pdfURL))

        // 3. Sample Audio (`mixtape.wav`)
        let wavURL = folder.appendingPathComponent("mixtape.wav")
        if !fm.fileExists(atPath: wavURL.path) {
            createSampleAudioWAV(at: wavURL)
        }
        cards.append(SampleCard(id: "audio", title: "mixtape.wav", badge: "AUDIO", icon: "waveform", category: .audio, url: wavURL))

        // 4. Sample CSV Spreadsheet (`revenue-metrics.csv`)
        let csvURL = folder.appendingPathComponent("revenue-metrics.csv")
        if !fm.fileExists(atPath: csvURL.path) {
            let csv = """
            Quarter,Region,Product,ARR,YoY Growth
            Q1 2026,"North America, West",MELD Pro,"$142,500",+38%
            Q2 2026,"Europe, UK",MELD Teams,"$198,000",+44%
            Q3 2026,"Asia Pacific",MELD Enterprise,"$264,900",+52%
            """
            try? csv.write(to: csvURL, atomically: true, encoding: .utf8)
        }
        cards.append(SampleCard(id: "csv", title: "revenue-metrics.csv", badge: "SHEET", icon: "tablecells.fill", category: .spreadsheet, url: csvURL))

        // 5. Sample SRT Subtitle (`captions.srt`)
        let srtURL = folder.appendingPathComponent("captions.srt")
        if !fm.fileExists(atPath: srtURL.path) {
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
        cards.append(SampleCard(id: "srt", title: "captions.srt", badge: "SUBTITLE", icon: "captions.bubble.fill", category: .subtitle, url: srtURL))

        // 6. Sample QR Code (`event-pass-qr.png`)
        let qrURL = folder.appendingPathComponent("event-pass-qr.png")
        if !fm.fileExists(atPath: qrURL.path) {
            _ = try? ImageTransformer.generateQRCode(payload: "https://github.com/omrajput14/flipdoc", outputURL: qrURL, size: 420)
        }
        cards.append(SampleCard(id: "qr", title: "event-pass-qr.png", badge: "QR IMAGE", icon: "qrcode.viewfinder", category: .image, url: qrURL))

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
            string: "MELD LOCAL STUDIO",
            attributes: [
                .font: NSFont.boldSystemFont(ofSize: 34),
                .foregroundColor: NSColor(calibratedRed: 0.12, green: 0.12, blue: 0.13, alpha: 1)
            ]
        )
        let line = CTLineCreateWithAttributedString(str)
        ctx.textPosition = CGPoint(x: 225, y: 95)
        CTLineDraw(line, ctx)

        if let cg = ctx.makeImage(),
           let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) {
            CGImageDestinationAddImage(dest, cg, nil)
            CGImageDestinationFinalize(dest)
        }
    }

    private static func createSampleInvoicePDF(at url: URL) {
        let rows = [
            ["Item", "Department", "Contact", "Unit Price", "Total"],
            ["Mac Studio M3 Ultra", "Engineering", "eng@meld.app", "$3,999", "$7,998"],
            ["Studio Display", "Design", "+1 415-555-0192", "$1,599", "$4,797"],
            ["MELD Team License", "Operations", "ops@meld.app", "$29", "$725"]
        ]
        let table = ExtractedTable(page: 1, rows: rows)
        let tmpXlsx = url.deletingLastPathComponent().appendingPathComponent("tmp_inv.xlsx")
        defer { try? FileManager.default.removeItem(at: tmpXlsx) }
        if let _ = try? PDFTableExtractor.exportToXLSX(tables: [table], outputURL: tmpXlsx) {
            _ = try? XLSXtoPDFEngine.convert(inputURL: tmpXlsx, outputURL: url)
        }
    }

    private static func createSampleAudioWAV(at url: URL) {
        let sr = 44100
        let count = sr / 2
        var data = Data()
        let dataSize = UInt32(count * 2)
        func le<T: FixedWidthInteger>(_ v: T) -> [UInt8] { withUnsafeBytes(of: v.littleEndian) { Array($0) } }
        data.append(contentsOf: "RIFF".utf8)
        data.append(contentsOf: le(UInt32(36 + dataSize)))
        data.append(contentsOf: "WAVEfmt ".utf8)
        data.append(contentsOf: le(UInt32(16)))
        data.append(contentsOf: le(UInt16(1)))
        data.append(contentsOf: le(UInt16(1)))
        data.append(contentsOf: le(UInt32(sr)))
        data.append(contentsOf: le(UInt32(sr * 2)))
        data.append(contentsOf: le(UInt16(2)))
        data.append(contentsOf: le(UInt16(16)))
        data.append(contentsOf: "data".utf8)
        data.append(contentsOf: le(dataSize))
        for i in 0..<count {
            let env = sin(Double.pi * Double(i) / Double(count))
            let v = Int16(sin(2.0 * .pi * 440.0 * Double(i) / Double(sr)) * 12000.0 * env)
            data.append(contentsOf: le(UInt16(bitPattern: v)))
        }
        try? data.write(to: url)
    }
}

public enum StudioExplorerCategory: String, CaseIterable, Identifiable {
    case image = "Images"
    case video = "Video"
    case audio = "Audio"
    case pdf = "PDF"
    case document = "Documents"
    case spreadsheet = "Spreadsheets"
    case subtitle = "Subtitles"
    case archive = "Archives"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .image: return "photo"
        case .video: return "play.rectangle"
        case .audio: return "music.note"
        case .pdf: return "doc.richtext"
        case .document: return "doc.text"
        case .spreadsheet: return "tablecells"
        case .subtitle: return "captions.bubble"
        case .archive: return "archivebox"
        }
    }

    public var dummyURL: URL {
        switch self {
        case .image: return URL(fileURLWithPath: "/tmp/sample.jpg")
        case .video: return URL(fileURLWithPath: "/tmp/sample.mov")
        case .audio: return URL(fileURLWithPath: "/tmp/sample.mp3")
        case .pdf: return URL(fileURLWithPath: "/tmp/sample.pdf")
        case .document: return URL(fileURLWithPath: "/tmp/sample.docx")
        case .spreadsheet: return URL(fileURLWithPath: "/tmp/sample.csv")
        case .subtitle: return URL(fileURLWithPath: "/tmp/sample.srt")
        case .archive: return URL(fileURLWithPath: "/tmp/sample.zip")
        }
    }
}

/// Non-capturing NSView drop receiver for the Studio playground card.
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

/// Observes live `⇧ Shift`, `⌘ Command`, and `⌃ Control` keypresses + selected Explorer tab & hovered petals.
@MainActor
final class LiveModifierKeyObserver: ObservableObject {
    @Published var heldMode: ModifierMode? = nil
    @Published var samples: [SamplePlaygroundFiles.SampleCard] = []
    @Published var isDropTargeted: Bool = false
    @Published var selectedSampleID: String? = "img"
    @Published var explorerCategory: StudioExplorerCategory = .image
    @Published var hoveredConvertIndex: Int? = 0
    @Published var hoveredToolIndex: Int? = 0

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
        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: 20) {
                // 1. Top MELD Navigation Bar
                topNavigationBar

                // 2. Interactive Finder-Icon Playground Canvas (Inspired by the reference video!)
                finderDesktopPlaygroundCard

                // 3. Interactive Category Wheel Explorer (Side-by-side ⇧ Convert & ⌘ Tools wheels!)
                categoryWheelExplorerSection

                // 4. Bottom Split: Quick Toggles + Recent Outputs
                bottomControlsAndRecentsSection
            }
            .padding(24)
        }
        .frame(width: 840, height: 740)
        .background(FlipDocTheme.canvasBackground(for: scheme))
        .onAppear {
            keyObserver.samples = SamplePlaygroundFiles.prepareSamples()
            keyObserver.start()
        }
        .onDisappear {
            keyObserver.stop()
        }
    }

    // MARK: - 1. Top Navigation Bar

    private var topNavigationBar: some View {
        HStack(alignment: .center, spacing: 14) {
            MeldBrandMarkView(size: 46)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("MELD")
                        .font(.system(size: 21, weight: .bold, design: .rounded))
                    Text("TRANSFORM · CONVERT · ORGANIZE")
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .tracking(0.6)
                        .foregroundStyle(FlipDocTheme.orange)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(Capsule().fill(FlipDocTheme.orange.opacity(0.14)))
                }
                Text("The zero-click offline file studio — drag any file, tap ⇧ Shift, ⌘ Command, or ⌃ Control, and drop.")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                Button(action: chooseFilesWithOpenPanel) {
                    Label("Open Files…", systemImage: "plus.circle.fill")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                }
                .buttonStyle(.borderedProminent)
                .tint(FlipDocTheme.orange)

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
                .help("MELD Settings")
            }
        }
    }

    // MARK: - 2. Finder-Icon Desktop Playground Canvas

    private var finderDesktopPlaygroundCard: some View {
        VStack(spacing: 16) {
            // Top Floating Mode Switcher Pill (`[⇧ Convert] [⌘ Tools] [⌃ Actions]`) just like the reference video!
            HStack(spacing: 14) {
                liveModeBadge(mode: .conversions, symbol: "⇧", title: "Convert")
                liveModeBadge(mode: .tools, symbol: "⌘", title: "Tools")
                liveModeBadge(mode: .actions, symbol: "⌃", title: "Actions")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(scheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.92))
                    .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 3)
            )
            .overlay(
                Capsule()
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )

            Text("Drag any sample file below and tap ⇧ Shift, ⌘ Command, or ⌃ Control — or single-click to open the wheel")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)

            // Authentic macOS Finder-Style Desktop Icons Row
            HStack(spacing: 18) {
                ForEach(keyObserver.samples) { sample in
                    finderDesktopIconView(sample)
                }
            }
            .padding(.vertical, 6)
        }
        .padding(.vertical, 22)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: scheme == .dark
                            ? [Color(red: 0.13, green: 0.15, blue: 0.18), Color(red: 0.11, green: 0.12, blue: 0.14)]
                            : [Color(red: 0.91, green: 0.95, blue: 0.99), Color(red: 0.98, green: 0.97, blue: 0.95)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
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
                        mode: keyObserver.heldMode ?? .conversions,
                        isDragSession: false
                    )
                }
            )
        )
    }

    private func liveModeBadge(mode: ModifierMode, symbol: String, title: String) -> some View {
        let isHeld = keyObserver.heldMode == mode
        return Button(action: {
            if let sample = keyObserver.samples.first(where: { $0.id == keyObserver.selectedSampleID }) ?? keyObserver.samples.first {
                RadialOverlayWindow.shared.show(
                    at: NSEvent.mouseLocation,
                    for: [sample.url],
                    mode: mode,
                    isDragSession: false
                )
            }
        }) {
            HStack(spacing: 5) {
                Text(symbol)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(isHeld ? .white : FlipDocTheme.warmOrange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(isHeld ? FlipDocTheme.orange : FlipDocTheme.orange.opacity(0.14))
                    )
                Text(title)
                    .font(.system(size: 12, weight: isHeld ? .bold : .semibold, design: .rounded))
                    .foregroundStyle(isHeld ? FlipDocTheme.orange : .primary)
            }
        }
        .buttonStyle(.plain)
    }

    private func finderDesktopIconView(_ sample: SamplePlaygroundFiles.SampleCard) -> some View {
        let isSelected = keyObserver.selectedSampleID == sample.id
        let finderBlue = Color(red: 0.05, green: 0.42, blue: 0.92)

        return VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.black.opacity(0.10) : Color.clear)
                    .frame(width: 68, height: 68)

                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white)
                        .frame(width: 56, height: 56)
                        .shadow(color: .black.opacity(0.16), radius: 5, x: 0, y: 2)

                    Image(systemName: sample.icon)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(FlipDocTheme.orange)
                }
            }

            // Authentic macOS Finder filename pill (`landscape.png`, `field-notes.pdf`, etc.)
            Text(sample.title)
                .font(.system(size: 11, weight: isSelected ? .semibold : .medium, design: .rounded))
                .foregroundStyle(isSelected ? .white : .primary)
                .lineLimit(1)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isSelected ? finderBlue : Color.clear)
                )
        }
        .frame(width: 110)
        .overlay(
            NativeFileDragSourceBridge(
                urls: [sample.url],
                onSingleClick: {
                    keyObserver.selectedSampleID = sample.id
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

    // MARK: - 3. Interactive Category Wheel Explorer (Side-by-Side ⇧ Shift & ⌘ Command Wheels)

    private var categoryWheelExplorerSection: some View {
        let cat = keyObserver.explorerCategory
        let convertOptions = FileCategory.options(for: [cat.dummyURL], mode: .conversions)
        let toolOptions = FileCategory.options(for: [cat.dummyURL], mode: .tools)

        return VStack(spacing: 14) {
            // Category Selector Tabs (`Images`, `Video`, `Audio`, `PDF`, `Documents`, `Spreadsheets`, `Subtitles`, `Archives`)
            HStack(spacing: 6) {
                ForEach(StudioExplorerCategory.allCases) { item in
                    let active = (keyObserver.explorerCategory == item)
                    Button(action: {
                        keyObserver.explorerCategory = item
                        keyObserver.hoveredConvertIndex = 0
                        keyObserver.hoveredToolIndex = 0
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: item.icon)
                                .font(.system(size: 11, weight: .semibold))
                            Text(item.rawValue)
                                .font(.system(size: 11.5, weight: active ? .bold : .medium, design: .rounded))
                        }
                        .foregroundStyle(active ? .primary : .secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(active ? FlipDocTheme.cardBackground(for: scheme) : Color.clear)
                                .shadow(color: active ? .black.opacity(0.07) : .clear, radius: 4, x: 0, y: 1)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(active ? FlipDocTheme.cardBorder(for: scheme) : Color.clear, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            // Side-by-Side Interactive Wheels Card
            VStack(spacing: 14) {
                Text("\(cat.rawValue) studio wheels")
                    .font(.system(size: 16, weight: .bold, design: .rounded))

                HStack(alignment: .top, spacing: 24) {
                    // Left: ⇧ Shift — Convert Formats Wheel
                    interactiveWheelShowcaseColumn(
                        keySymbol: "⇧",
                        keyName: "shift",
                        subtitle: "Convert formats",
                        options: convertOptions,
                        hoveredIndex: keyObserver.hoveredConvertIndex ?? 0,
                        onHoverIndex: { keyObserver.hoveredConvertIndex = $0 },
                        onClickOption: { option in
                            triggerSampleAction(for: cat, option: option)
                        }
                    )

                    Divider()
                        .frame(height: 290)

                    // Right: ⌘ Command — File Tools Wheel
                    interactiveWheelShowcaseColumn(
                        keySymbol: "⌘",
                        keyName: "command",
                        subtitle: "File tools",
                        options: toolOptions,
                        hoveredIndex: keyObserver.hoveredToolIndex ?? 0,
                        onHoverIndex: { keyObserver.hoveredToolIndex = $0 },
                        onClickOption: { option in
                            triggerSampleAction(for: cat, option: option)
                        }
                    )
                }

                Text("Hover any petal to preview, or click a petal to run it immediately on a sample file.")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(FlipDocTheme.cardBackground(for: scheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(FlipDocTheme.cardBorder(for: scheme), lineWidth: 1)
            )
        }
    }

    private func interactiveWheelShowcaseColumn(
        keySymbol: String,
        keyName: String,
        subtitle: String,
        options: [FanOption],
        hoveredIndex: Int,
        onHoverIndex: @escaping (Int) -> Void,
        onClickOption: @escaping (FanOption) -> Void
    ) -> some View {
        let safeIdx = min(max(0, hoveredIndex), max(0, options.count - 1))
        let activeOption: FanOption? = options.isEmpty ? nil : options[safeIdx]
        let isDense = options.count > 6

        return VStack(spacing: 10) {
            // 3D macOS Keyboard Keycap (`⇧ shift` / `⌘ command`)
            VStack(alignment: .leading, spacing: 4) {
                Text(keySymbol)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Text(keyName)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .frame(minWidth: 56, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(scheme == .dark ? Color(white: 0.20) : Color.white)
                    .shadow(color: .black.opacity(0.14), radius: 3, x: 0, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
            )

            Text(subtitle)
                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)

            // Interactive Mini Radial Wheel
            ZStack {
                DonutBackdropShape()
                    .fill(
                        scheme == .dark
                            ? Color(red: 0.16, green: 0.17, blue: 0.19).opacity(0.88)
                            : Color(red: 0.91, green: 0.93, blue: 0.95).opacity(0.72),
                        style: FillStyle(eoFill: true)
                    )
                    .shadow(color: .black.opacity(0.10), radius: 10, x: 0, y: 4)

                ForEach(Array(options.enumerated()), id: \.element.id) { idx, opt in
                    let isHi = (idx == safeIdx)
                    let shape = PetalShape(index: idx, count: options.count)
                    let labelPos = PetalGeometry.labelPosition(index: idx, count: options.count)

                    ZStack {
                        shape
                            .fill(
                                isHi
                                    ? LinearGradient(colors: [FlipDocTheme.orange, FlipDocTheme.warmOrange], startPoint: .top, endPoint: .bottom)
                                    : LinearGradient(
                                        colors: scheme == .dark
                                            ? [Color(white: 0.24), Color(white: 0.19)]
                                            : [Color.white, Color(white: 0.96)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                            )
                            .overlay(
                                shape.stroke(
                                    isHi ? FlipDocTheme.orange : Color.primary.opacity(0.10),
                                    lineWidth: 0.8
                                )
                            )
                            .onHover { inside in
                                if inside { onHoverIndex(idx) }
                            }
                            .onTapGesture {
                                onHoverIndex(idx)
                                onClickOption(opt)
                            }

                        Group {
                            if opt.showsPetalIcon {
                                VStack(spacing: 2) {
                                    Image(systemName: opt.systemImage)
                                        .font(.system(size: isDense ? 12 : 14, weight: .semibold))
                                        .foregroundStyle(isHi ? .white : .primary)
                                    Text(opt.wheelTitle)
                                        .font(.system(size: isDense ? 7.2 : 8.0, weight: .bold, design: .rounded))
                                        .foregroundStyle(isHi ? .white : .primary)
                                        .lineLimit(1)
                                }
                            } else {
                                Text(opt.wheelTitle)
                                    .font(.system(size: isDense ? 10.5 : 12.0, weight: .bold, design: .rounded))
                                    .foregroundStyle(isHi ? .white : .primary)
                            }
                        }
                        .offset(x: labelPos.x, y: labelPos.y)
                        .allowsHitTesting(false)
                    }
                }

                // Center Hub Pill
                Text(activeOption?.wheelTitle ?? "")
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .frame(minWidth: 64, minHeight: 28)
                    .background(
                        Capsule()
                            .fill(scheme == .dark ? Color(white: 0.22) : Color.white)
                            .shadow(color: .black.opacity(0.10), radius: 4, x: 0, y: 2)
                    )
            }
            .frame(width: PetalGeometry.wheelDiameter, height: PetalGeometry.wheelDiameter)
            .scaleEffect(0.84)
            .frame(width: 210, height: 210)

            Text(activeOption?.label ?? "")
                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func triggerSampleAction(for explorerCat: StudioExplorerCategory, option: FanOption) {
        let matchingSample = keyObserver.samples.first { sample in
            switch explorerCat {
            case .image: return sample.category == .image
            case .pdf: return sample.category == .pdf
            case .audio: return sample.category == .audio
            case .spreadsheet: return sample.category == .spreadsheet
            case .subtitle: return sample.category == .subtitle
            default: return true
            }
        } ?? keyObserver.samples.first

        guard let sample = matchingSample else { return }
        ActionDispatcher.shared.execute(option: option, urls: [sample.url])
    }

    // MARK: - 4. Bottom Controls & Recent Outputs

    private var bottomControlsAndRecentsSection: some View {
        HStack(alignment: .top, spacing: 14) {
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
            .frame(width: 230, height: 150)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(FlipDocTheme.cardBackground(for: scheme)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(FlipDocTheme.cardBorder(for: scheme), lineWidth: 1))

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
            .frame(height: 150)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(FlipDocTheme.cardBackground(for: scheme)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(FlipDocTheme.cardBorder(for: scheme), lineWidth: 1))
        }
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
            w.title = "MELD Studio"
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
