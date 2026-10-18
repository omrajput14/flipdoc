import AppKit
import SwiftUI
import UniformTypeIdentifiers
import Combine

@MainActor
public final class DropZoneViewModel: ObservableObject {
    @Published public var isTargeted: Bool = false
    @Published public var lastStatus: String = "Drag & Drop any file here"
    
    public init() {}
}

public struct FloatingDropZoneView: View {
    @ObservedObject private var viewModel = DropZoneViewModel()
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(viewModel.isTargeted ? Color.accentColor.opacity(0.2) : Color.white.opacity(0.1))
                    .frame(width: 64, height: 64)
                    .overlay(
                        Circle()
                            .stroke(viewModel.isTargeted ? Color.accentColor : Color.white.opacity(0.2), lineWidth: 2)
                    )
                
                Image(systemName: viewModel.isTargeted ? "arrow.down.doc.fill" : "doc.badge.plus")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(viewModel.isTargeted ? Color.accentColor : .primary)
            }
            
            VStack(spacing: 4) {
                Text("FlipDoc Drop Zone")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                Text(viewModel.lastStatus)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            HStack(spacing: 6) {
                Label("⇧ Shift", systemImage: "sparkles")
                Label("⌘ Cmd", systemImage: "tablecells")
                Label("⌃ Ctrl", systemImage: "link")
            }
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(.tertiary)
        }
        .padding(20)
        .frame(width: 240, height: 190)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(viewModel.isTargeted ? Color.accentColor : Color.white.opacity(0.2), lineWidth: 1.5)
        )
        .shadow(color: .black.opacity(0.2), radius: 18, x: 0, y: 8)
        .onDrop(of: [.fileURL], isTargeted: Binding(get: { viewModel.isTargeted }, set: { viewModel.isTargeted = $0 })) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let fileURL = url else { return }
                DispatchQueue.main.async {
                    self.viewModel.lastStatus = "Processing: \(fileURL.lastPathComponent)..."
                    let mouseLoc = NSEvent.mouseLocation
                    RadialOverlayWindow.shared.show(at: mouseLoc, for: fileURL, mode: .conversions)
                }
            }
            return true
        }
    }
}

public final class FloatingDropZoneWindow: NSPanel {
    public static let shared = FloatingDropZoneWindow()
    
    public init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 190),
            styleMask: [.nonactivatingPanel, .borderless, .titled],
            backing: .buffered,
            defer: false
        )
        
        self.isOpaque = false
        self.backgroundColor = .clear
        self.level = .floating
        self.hasShadow = false
        self.isMovableByWindowBackground = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.contentView = NSHostingView(rootView: FloatingDropZoneView())
        
        // Position on bottom right of main screen
        if let screen = NSScreen.main {
            let screenRect = screen.visibleFrame
            let origin = NSPoint(
                x: screenRect.maxX - 260,
                y: screenRect.minY + 40
            )
            self.setFrameOrigin(origin)
        }
    }
    
    public func toggleVisibility() {
        if self.isVisible {
            self.orderOut(nil)
        } else {
            self.orderFrontRegardless()
        }
    }
}
