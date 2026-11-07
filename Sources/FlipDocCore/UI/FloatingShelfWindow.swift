import AppKit
import SwiftUI
import QuickLookThumbnailing
import UniformTypeIdentifiers
import Combine

public struct FloatedFileItem: Identifiable, Hashable, Sendable {
    public let id: String
    public let url: URL

    public init(url: URL) {
        self.id = url.standardizedFileURL.path
        self.url = url.standardizedFileURL
    }

    public var fileName: String {
        url.lastPathComponent
    }

    public var sizeSummary: String {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            let count = (try? FileManager.default.contentsOfDirectory(atPath: url.path).count) ?? 0
            return "\(count) items"
        }
        let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

/// Native AppKit `NSDraggingSource` bridge allowing files to be dragged OUT of the Float Shelf (or Practice cards)
/// into any macOS app (Finder, Mail, Slack, Browser, or FlipDoc's own `⇧` radial wheel!).
@MainActor
public final class NativeFileDragSourceNSView: NSView, NSDraggingSource {
    public var urlsProvider: (() -> [URL])?
    public var onSingleClick: (() -> Void)?
    public var onDoubleClick: (() -> Void)?

    private var mouseDownLocation: NSPoint = .zero
    private var didStartDragSession: Bool = false

    public func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? [.copy, .move, .link] : .copy
    }

    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    public override func mouseDown(with event: NSEvent) {
        mouseDownLocation = convert(event.locationInWindow, from: nil)
        didStartDragSession = false
    }

    public override func mouseDragged(with event: NSEvent) {
        guard !didStartDragSession else { return }
        let current = convert(event.locationInWindow, from: nil)
        guard hypot(current.x - mouseDownLocation.x, current.y - mouseDownLocation.y) >= 4.0 else { return }
        guard let urls = urlsProvider?().filter({ FileManager.default.fileExists(atPath: $0.path) }),
              !urls.isEmpty else { return }

        didStartDragSession = true
        var draggingItems: [NSDraggingItem] = []

        for (index, url) in urls.enumerated() {
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 44, height: 44)
            let offset = CGFloat(min(index, 3)) * 5.0
            let frame = NSRect(
                x: current.x - 22 + offset,
                y: current.y - 22 - offset,
                width: 44,
                height: 44
            )
            item.setDraggingFrame(frame, contents: icon)
            draggingItems.append(item)
        }

        beginDraggingSession(with: draggingItems, event: event, source: self)
    }

    public override func mouseUp(with event: NSEvent) {
        guard !didStartDragSession else { return }
        if event.clickCount >= 2 {
            onDoubleClick?()
        } else {
            onSingleClick?()
        }
    }
}

public struct NativeFileDragSourceBridge: NSViewRepresentable {
    public let urls: [URL]
    public var onSingleClick: (() -> Void)? = nil
    public var onDoubleClick: (() -> Void)? = nil

    public init(
        urls: [URL],
        onSingleClick: (() -> Void)? = nil,
        onDoubleClick: (() -> Void)? = nil
    ) {
        self.urls = urls
        self.onSingleClick = onSingleClick
        self.onDoubleClick = onDoubleClick
    }

    public func makeNSView(context: Context) -> NativeFileDragSourceNSView {
        let v = NativeFileDragSourceNSView()
        v.urlsProvider = { urls }
        v.onSingleClick = onSingleClick
        v.onDoubleClick = onDoubleClick
        return v
    }

    public func updateNSView(_ nsView: NativeFileDragSourceNSView, context: Context) {
        nsView.urlsProvider = { urls }
        nsView.onSingleClick = onSingleClick
        nsView.onDoubleClick = onDoubleClick
    }
}

/// Native AppKit drop receiver for adding files into the Float shelf without intercepting normal clicks.
@MainActor
private final class ShelfDropReceiverNSView: NSView {
    var onTargetChanged: ((Bool) -> Void)?
    var onFilesDropped: (([URL]) -> Void)?

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
            onFilesDropped?(urls)
            return true
        }
        return false
    }
}

private struct ShelfDropReceiverBridge: NSViewRepresentable {
    let onTargetChanged: (Bool) -> Void
    let onFilesDropped: ([URL]) -> Void

    func makeNSView(context: Context) -> ShelfDropReceiverNSView {
        let v = ShelfDropReceiverNSView()
        v.onTargetChanged = onTargetChanged
        v.onFilesDropped = onFilesDropped
        return v
    }

    func updateNSView(_ nsView: ShelfDropReceiverNSView, context: Context) {
        nsView.onTargetChanged = onTargetChanged
        nsView.onFilesDropped = onFilesDropped
    }
}

@MainActor
final class FileThumbnailViewModel: ObservableObject {
    @Published var image: NSImage?
    @Published var isHovered: Bool = false

    func load(for url: URL) {
        let fallback = NSWorkspace.shared.icon(forFile: url.path)
        fallback.size = NSSize(width: 40, height: 40)
        if image == nil {
            image = fallback
        }
        let req = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: 72, height: 72),
            scale: 2.0,
            representationTypes: .thumbnail
        )
        QLThumbnailGenerator.shared.generateBestRepresentation(for: req) { [weak self] rep, _ in
            guard let nsImg = rep?.nsImage else { return }
            Task { @MainActor in
                self?.image = nsImg
            }
        }
    }
}

private struct FloatedItemRowView: View {
    let item: FloatedFileItem
    let onSummonWheel: () -> Void
    let onRemove: () -> Void

    @StateObject private var thumb = FileThumbnailViewModel()

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
                    .frame(width: 38, height: 38)

                if let img = thumb.image {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 32, height: 32)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
            }
            .overlay(
                NativeFileDragSourceBridge(
                    urls: [item.url],
                    onDoubleClick: {
                        NSWorkspace.shared.open(item.url)
                    }
                )
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(item.fileName)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Text(item.sizeSummary)
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(
                NativeFileDragSourceBridge(
                    urls: [item.url],
                    onDoubleClick: {
                        NSWorkspace.shared.open(item.url)
                    }
                )
            )

            HStack(spacing: 4) {
                Button(action: onSummonWheel) {
                    Image(systemName: "circle.hexagongrid.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(FlipDocTheme.orange)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(FlipDocTheme.orange.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .help("Open Conversion Wheel")

                Button(action: {
                    NSWorkspace.shared.activateFileViewerSelecting([item.url])
                }) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.primary.opacity(0.06)))
                }
                .buttonStyle(.plain)
                .help("Reveal in Finder")

                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .help("Unpin from Float")
            }
            .opacity(thumb.isHovered ? 1.0 : 0.72)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(thumb.isHovered ? Color.primary.opacity(0.06) : Color.primary.opacity(0.025))
        )
        .onHover { thumb.isHovered = $0 }
        .onAppear {
            thumb.load(for: item.url)
        }
    }
}

struct FloatingShelfView: View {
    @ObservedObject var manager: FloatingShelfManager

    var body: some View {
        Group {
            if manager.isCollapsed {
                collapsedPill
            } else {
                expandedShelf
            }
        }
        .overlay(
            ShelfDropReceiverBridge(
                onTargetChanged: { manager.isDropTargeted = $0 },
                onFilesDropped: { urls in
                    manager.pinFiles(urls)
                }
            )
        )
        .padding(12)
    }

    private var collapsedPill: some View {
        Button(action: {
            manager.setCollapsed(false)
        }) {
            HStack(spacing: 7) {
                Image(systemName: "pin.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(FlipDocTheme.orange)
                Text("Float")
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                Text("\(manager.items.count)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6.5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(FlipDocTheme.orange))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                Capsule()
                    .fill(.regularMaterial)
            )
            .overlay(
                Capsule()
                    .stroke(manager.isDropTargeted ? FlipDocTheme.orange : Color.white.opacity(0.32), lineWidth: manager.isDropTargeted ? 2 : 1)
            )
            .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }

    private var expandedShelf: some View {
        VStack(spacing: 10) {
            // Header
            HStack(spacing: 7) {
                Image(systemName: "pin.fill")
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(FlipDocTheme.orange)
                    .rotationEffect(.degrees(-25))

                Text("Float Shelf")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))

                if !manager.items.isEmpty {
                    Text("\(manager.items.count)")
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        .foregroundStyle(FlipDocTheme.warmOrange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(FlipDocTheme.orange.opacity(0.14)))
                }

                Spacer()

                if manager.items.count > 1 {
                    ZStack {
                        HStack(spacing: 4) {
                            Image(systemName: "hand.draw.fill")
                                .font(.system(size: 10))
                            Text("Drag All")
                                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(FlipDocTheme.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(FlipDocTheme.orange.opacity(0.12)))

                        NativeFileDragSourceBridge(
                            urls: manager.items.map(\.url),
                            onSingleClick: {
                                RadialOverlayWindow.shared.show(
                                    at: NSEvent.mouseLocation,
                                    for: manager.items.map(\.url),
                                    mode: .conversions,
                                    isDragSession: false
                                )
                            }
                        )
                    }
                    .frame(width: 72, height: 22)
                    .help("Drag all pinned files at once, or click to convert batch")
                }

                Button(action: { manager.setCollapsed(true) }) {
                    Image(systemName: "minus")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Color.primary.opacity(0.07)))
                }
                .buttonStyle(.plain)
                .help("Collapse to Pill")

                Button(action: { manager.hideWindow() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Color.primary.opacity(0.07)))
                }
                .buttonStyle(.plain)
                .help("Close Float Shelf")
            }

            if manager.items.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(FlipDocTheme.orange)
                    Text("Drop files here to keep them handy")
                        .font(.system(size: 11.5, weight: .medium, design: .rounded))
                    Text("Or drag any file + tap ⌃ Control → Float")
                        .font(.system(size: 10.5, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
                        .foregroundStyle(Color.secondary.opacity(0.35))
                )
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 6) {
                        ForEach(manager.items) { item in
                            FloatedItemRowView(
                                item: item,
                                onSummonWheel: {
                                    RadialOverlayWindow.shared.show(
                                        at: NSEvent.mouseLocation,
                                        for: [item.url],
                                        mode: .conversions,
                                        isDragSession: false
                                    )
                                },
                                onRemove: {
                                    manager.remove(item)
                                }
                            )
                        }
                    }
                }
                .frame(maxHeight: 230)

                HStack {
                    Text("Drag any item out into any app")
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear All") {
                        manager.clearAll()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .frame(width: 296)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(
                    manager.isDropTargeted ? FlipDocTheme.orange : Color.white.opacity(0.28),
                    lineWidth: manager.isDropTargeted ? 2.0 : 1.0
                )
        )
        .shadow(color: .black.opacity(0.20), radius: 14, x: 0, y: 6)
    }
}

/// Manages FlipDoc's floating pin shelf (`FloatingShelfManager`).
@MainActor
public final class FloatingShelfManager: ObservableObject {
    public static let shared = FloatingShelfManager()

    @Published public private(set) var items: [FloatedFileItem] = []
    @Published public private(set) var isCollapsed: Bool = false
    @Published public var isDropTargeted: Bool = false

    private var panel: NSPanel?

    private init() {}

    public func pinFiles(_ urls: [URL]) {
        let valid = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !valid.isEmpty else { return }

        for url in valid {
            let item = FloatedFileItem(url: url)
            if !items.contains(item) {
                items.insert(item, at: 0)
            }
        }
        isCollapsed = false
        showWindow()
        SoundAndHaptics.shared.playCompletion()
    }

    public func remove(_ item: FloatedFileItem) {
        items.removeAll { $0.id == item.id }
        resizePanelToFit()
    }

    public func clearAll() {
        items.removeAll()
        resizePanelToFit()
    }

    public func setCollapsed(_ collapsed: Bool) {
        isCollapsed = collapsed
        resizePanelToFit()
    }

    public func showWindow() {
        if panel == nil {
            let p = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 320, height: 220),
                styleMask: [.nonactivatingPanel, .borderless],
                backing: .buffered,
                defer: false
            )
            p.isOpaque = false
            p.backgroundColor = .clear
            p.level = .floating
            p.hasShadow = false
            p.isMovableByWindowBackground = true
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            p.contentView = NSHostingView(rootView: FloatingShelfView(manager: self))

            if let screen = NSScreen.main?.visibleFrame {
                p.setFrameOrigin(NSPoint(
                    x: screen.maxX - 336,
                    y: screen.midY - 90
                ))
            }
            self.panel = p
        }
        resizePanelToFit()
        panel?.orderFrontRegardless()
    }

    public func hideWindow() {
        panel?.orderOut(nil)
    }

    public func toggleWindow() {
        if panel?.isVisible == true {
            hideWindow()
        } else {
            showWindow()
        }
    }

    private func resizePanelToFit() {
        guard let panel = panel else { return }
        let oldTopRight = NSPoint(x: panel.frame.maxX, y: panel.frame.maxY)
        let newSize: NSSize
        if isCollapsed {
            newSize = NSSize(width: 156, height: 64)
        } else if items.isEmpty {
            newSize = NSSize(width: 320, height: 190)
        } else {
            let rowCount = min(items.count, 4)
            let contentH = CGFloat(92 + rowCount * 56)
            newSize = NSSize(width: 320, height: min(340, contentH))
        }
        let newOrigin = NSPoint(x: oldTopRight.x - newSize.width, y: oldTopRight.y - newSize.height)
        panel.setFrame(NSRect(origin: newOrigin, size: newSize), display: true, animate: true)
    }
}
