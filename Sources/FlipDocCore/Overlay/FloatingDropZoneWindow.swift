import AppKit
import SwiftUI
import UniformTypeIdentifiers
import Combine

@MainActor
public final class DropZoneViewModel: ObservableObject {
    @Published public var isTargeted: Bool = false
    @Published public var statusText: String = "Drop files or tap ⇧ while dragging"

    public init() {}
}

/// Native AppKit drop target view ensuring 100% reliable Finder multi-file drops onto the desktop widget.
@MainActor
private final class NativeFileDropOverlayView: NSView {
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
        // Let normal mouse clicks pass through to SwiftUI buttons/window drag, while NSDraggingDestination still receives drags!
        return nil
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

private struct NativeDropBridge: NSViewRepresentable {
    let onTargetChanged: (Bool) -> Void
    let onFilesDropped: ([URL]) -> Void

    func makeNSView(context: Context) -> NativeFileDropOverlayView {
        let v = NativeFileDropOverlayView()
        v.onTargetChanged = onTargetChanged
        v.onFilesDropped = onFilesDropped
        return v
    }

    func updateNSView(_ nsView: NativeFileDropOverlayView, context: Context) {
        nsView.onTargetChanged = onTargetChanged
        nsView.onFilesDropped = onFilesDropped
    }
}

public struct FloatingDropZoneView: View {
    @StateObject private var viewModel = DropZoneViewModel()
    public let onClose: () -> Void

    public init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    public var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 11) {
                ZStack {
                    Circle()
                        .fill(viewModel.isTargeted ? FlipDocTheme.orange.opacity(0.18) : FlipDocTheme.orange.opacity(0.10))
                        .frame(width: 54, height: 54)
                        .overlay(
                            Circle()
                                .stroke(viewModel.isTargeted ? FlipDocTheme.orange : FlipDocTheme.orange.opacity(0.35), lineWidth: 1.5)
                        )
                        .scaleEffect(viewModel.isTargeted ? 1.08 : 1.0)
                        .animation(.spring(response: 0.24, dampingFraction: 0.72), value: viewModel.isTargeted)

                    Image(systemName: viewModel.isTargeted ? "arrow.down.doc.fill" : "sparkles")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(FlipDocTheme.orange)
                }

                VStack(spacing: 3) {
                    Text("MELD Drop Zone")
                        .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                    Text(viewModel.statusText)
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }

                HStack(spacing: 6) {
                    keyPill("⇧", "Convert")
                    keyPill("⌘", "Tools")
                    keyPill("⌃", "Actions")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .frame(width: 244, height: 174)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(
                        viewModel.isTargeted ? FlipDocTheme.orange : Color.white.opacity(0.28),
                        lineWidth: viewModel.isTargeted ? 2.0 : 1.0
                    )
            )

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(Color.primary.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .padding(10)
        }
        .overlay(
            NativeDropBridge(
                onTargetChanged: { targeted in
                    viewModel.isTargeted = targeted
                },
                onFilesDropped: { urls in
                    let label = urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) files"
                    viewModel.statusText = "Selected \(label)"
                    RadialOverlayWindow.shared.show(
                        at: NSEvent.mouseLocation,
                        for: urls,
                        mode: .conversions,
                        isDragSession: false
                    )
                }
            )
        )
        .padding(12) // Space for soft shadow inside borderless panel
        .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 5)
    }

    private func keyPill(_ key: String, _ title: String) -> some View {
        HStack(spacing: 3) {
            Text(key)
                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                .foregroundStyle(FlipDocTheme.warmOrange)
            Text(title)
                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }
}

@MainActor
public final class FloatingDropZoneWindow: NSPanel {
    public static let shared = FloatingDropZoneWindow()

    public init() {
        // Pure `.borderless` + `.nonactivatingPanel` (fixed ghost titlebar bug caused by combining `.borderless` and `.titled`)
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 268, height: 198),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        self.isOpaque = false
        self.backgroundColor = .clear
        self.level = .floating
        self.hasShadow = false
        self.isMovableByWindowBackground = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.contentView = NSHostingView(rootView: FloatingDropZoneView(onClose: {
            AppPreferences.shared.showDesktopDropZone = false
        }))

        if let screen = NSScreen.main {
            let screenRect = screen.visibleFrame
            self.setFrameOrigin(NSPoint(
                x: screenRect.maxX - 284,
                y: screenRect.minY + 32
            ))
        }
    }

    public func setVisible(_ visible: Bool) {
        if visible {
            orderFrontRegardless()
        } else {
            orderOut(nil)
        }
    }

    public func toggleVisibility() {
        let next = !isVisible
        AppPreferences.shared.showDesktopDropZone = next
    }
}

