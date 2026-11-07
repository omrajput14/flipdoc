import AppKit
import SwiftUI
import Combine

public enum HUDState: Equatable {
    case idle
    case running(title: String, subtitle: String)
    case succeeded(title: String, subtitle: String, outputURLs: [URL])
    case toast(title: String, subtitle: String, systemImage: String)
    case failed(title: String, message: String)
}

@MainActor
public final class OperationProgressHUDModel: ObservableObject {
    @Published public var state: HUDState = .idle
    @Published public var isHovered: Bool = false

    public init() {}
}

struct OperationProgressHUDView: View {
    @ObservedObject var model: OperationProgressHUDModel
    let onReveal: ([URL]) -> Void
    let onFloat: ([URL]) -> Void
    let onDismiss: () -> Void

    var body: some View {
        Group {
            switch model.state {
            case .idle:
                EmptyView()

            case .running(let title, let subtitle):
                hudCard {
                    HStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.small)
                            .tint(FlipDocTheme.orange)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(FlipDocTheme.orange.opacity(0.12)))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(title)
                                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                                .lineLimit(1)
                            Text(subtitle)
                                .font(.system(size: 11, design: .rounded))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 4)
                    }
                }

            case .succeeded(let title, let subtitle, let urls):
                hudCard {
                    HStack(spacing: 11) {
                        ZStack {
                            Circle()
                                .fill(FlipDocTheme.orange.opacity(0.15))
                                .frame(width: 30, height: 30)
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(FlipDocTheme.orange)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(title)
                                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                                .lineLimit(1)
                            Text(subtitle)
                                .font(.system(size: 11, design: .rounded))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 6)

                        if !urls.isEmpty {
                            HStack(spacing: 6) {
                                Button("Float") {
                                    onFloat(urls)
                                }
                                .buttonStyle(HUDActionButtonStyle(prominent: false))

                                Button("Reveal") {
                                    onReveal(urls)
                                }
                                .buttonStyle(HUDActionButtonStyle(prominent: true))
                            }
                        }

                        dismissButton
                    }
                }

            case .toast(let title, let subtitle, let systemImage):
                hudCard {
                    HStack(spacing: 11) {
                        ZStack {
                            Circle()
                                .fill(FlipDocTheme.orange.opacity(0.15))
                                .frame(width: 28, height: 28)
                            Image(systemName: systemImage)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(FlipDocTheme.orange)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(title)
                                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                                .lineLimit(1)
                            Text(subtitle)
                                .font(.system(size: 11, design: .rounded))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 4)
                        dismissButton
                    }
                }

            case .failed(let title, let message):
                hudCard {
                    HStack(spacing: 11) {
                        ZStack {
                            Circle()
                                .fill(Color.red.opacity(0.15))
                                .frame(width: 30, height: 30)
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.red)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(title)
                                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                                .lineLimit(1)
                            Text(message)
                                .font(.system(size: 11, design: .rounded))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }

                        Spacer(minLength: 4)
                        dismissButton
                    }
                }
            }
        }
        .onHover { hovering in
            model.isHovered = hovering
        }
    }

    private var dismissButton: some View {
        Button(action: onDismiss) {
            Image(systemName: "xmark")
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.primary.opacity(0.07)))
        }
        .buttonStyle(.plain)
    }

    private func hudCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(width: 368)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.regularMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.28), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 5)
            .padding(12)
    }
}

private struct HUDActionButtonStyle: ButtonStyle {
    let prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(prominent ? FlipDocTheme.orange : Color.primary.opacity(0.08))
            )
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}

/// Non-activating floating progress & completion toast panel.
@MainActor
public final class OperationProgressHUD: NSPanel {
    public static let shared = OperationProgressHUD()

    private let model = OperationProgressHUDModel()
    private var dismissWorkItem: DispatchWorkItem?

    private init() {
        let rect = NSRect(x: 0, y: 0, width: 392, height: 86)
        super.init(
            contentRect: rect,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        self.isOpaque = false
        self.backgroundColor = .clear
        self.level = .statusBar
        self.hasShadow = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isMovableByWindowBackground = true

        let root = OperationProgressHUDView(
            model: model,
            onReveal: { [weak self] urls in
                NSWorkspace.shared.activateFileViewerSelecting(urls)
                self?.dismiss()
            },
            onFloat: { [weak self] urls in
                FloatingShelfManager.shared.pinFiles(urls)
                self?.dismiss()
            },
            onDismiss: { [weak self] in
                self?.dismiss()
            }
        )
        self.contentView = NSHostingView(rootView: root)
    }

    public func showProgress(title: String, subtitle: String) {
        dismissWorkItem?.cancel()
        model.state = .running(title: title, subtitle: subtitle)
        presentInCorner()
    }

    public func showSuccess(title: String, subtitle: String, outputURLs: [URL]) {
        dismissWorkItem?.cancel()
        model.state = .succeeded(title: title, subtitle: subtitle, outputURLs: outputURLs)
        presentInCorner()
        scheduleAutoDismiss(after: 5.5)
    }

    public func showToast(title: String, subtitle: String, systemImage: String = "sparkles") {
        dismissWorkItem?.cancel()
        model.state = .toast(title: title, subtitle: subtitle, systemImage: systemImage)
        presentInCorner()
        scheduleAutoDismiss(after: 3.2)
    }

    public func showError(title: String, message: String) {
        dismissWorkItem?.cancel()
        model.state = .failed(title: title, message: message)
        presentInCorner()
        scheduleAutoDismiss(after: 6.5)
    }

    public func dismiss() {
        dismissWorkItem?.cancel()
        model.state = .idle
        orderOut(nil)
    }

    private func presentInCorner() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            // Stack neatly above Desktop Drop Zone if visible
            let yOffset: CGFloat = FloatingDropZoneWindow.shared.isVisible ? 236 : 20
            let origin = NSPoint(
                x: visible.maxX - frame.width - 16,
                y: visible.minY + yOffset
            )
            setFrameOrigin(origin)
        }
        orderFrontRegardless()
    }

    private func scheduleAutoDismiss(after delay: TimeInterval) {
        dismissWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self = self else { return }
                if self.model.isHovered {
                    self.scheduleAutoDismiss(after: 2.5)
                } else {
                    self.dismiss()
                }
            }
        }
        dismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
}

