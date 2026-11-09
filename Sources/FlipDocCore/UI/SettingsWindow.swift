import AppKit
import SwiftUI

public struct SettingsView: View {
    @ObservedObject private var prefs = AppPreferences.shared
    @Environment(\.colorScheme) private var scheme

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Header
            HStack(spacing: 12) {
                MeldBrandMarkView(size: 42)
                VStack(alignment: .leading, spacing: 2) {
                    Text("MELD Settings")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Text("TRANSFORM · CONVERT · ORGANIZE — 100% offline on Mac")
                        .font(.system(size: 11.5, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            // Section 1: Drag & Workflow
            settingsCard(title: "WORKFLOW & SHORTCUTS") {
                VStack(spacing: 12) {
                    settingToggleRow(
                        title: "Enable Drag Modifier Wheel (⇧ / ⌘ / ⌃)",
                        subtitle: "Tap Shift, Command, or Control while dragging any file to summon the radial wheel",
                        isOn: $prefs.dragModifiersEnabled
                    )
                    Divider()
                    settingToggleRow(
                        title: "Show Desktop Drop Zone Widget",
                        subtitle: "Keep a compact floating drop card in the corner of your screen",
                        isOn: $prefs.showDesktopDropZone
                    )
                    Divider()
                    settingToggleRow(
                        title: "Auto-Reveal Output in Finder",
                        subtitle: "Automatically highlight converted files in Finder when finished",
                        isOn: $prefs.autoRevealInFinder
                    )
                    Divider()
                    settingToggleRow(
                        title: "Auto-Pin Outputs to Float Shelf",
                        subtitle: "Automatically add newly converted files to your Float Shelf",
                        isOn: $prefs.autoFloatOutputs
                    )
                    Divider()
                    settingToggleRow(
                        title: "Launch MELD at Login",
                        subtitle: "Start quietly in the macOS menu bar when you sign in",
                        isOn: Binding(
                            get: { prefs.launchAtLoginEnabled },
                            set: { prefs.launchAtLoginEnabled = $0 }
                        )
                    )
                }
            }

            // Section 2: Appearance & Feedback
            settingsCard(title: "WHEEL APPEARANCE & HAPTICS") {
                VStack(spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Radial Wheel Theme")
                                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                            Text("Choose frosted glass style for the conversion wheel")
                                .font(.system(size: 11, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Picker("", selection: $prefs.wheelTheme) {
                            ForEach(WheelVisualTheme.allCases, id: \.rawValue) { theme in
                                Text(theme.rawValue).tag(theme)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 240)
                    }

                    Divider()

                    HStack {
                        settingToggleRow(
                            title: "Petal Tick Sounds & Force Touch Haptics",
                            subtitle: "Play subtle glass ticks and trackpad alignment feedback",
                            isOn: $prefs.soundsAndHapticsEnabled
                        )
                        Button("Test") {
                            SoundAndHaptics.shared.playPetalTick()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Default Compression Quality")
                                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                            Spacer()
                            Text("\(Int((prefs.imageCompressionQuality * 100).rounded()))%")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundStyle(FlipDocTheme.orange)
                        }
                        Slider(value: $prefs.imageCompressionQuality, in: 0.25...0.95, step: 0.01)
                            .tint(FlipDocTheme.orange)
                    }
                }
            }
        }
        .padding(24)
        .frame(width: 520)
        .background(FlipDocTheme.canvasBackground(for: scheme))
    }

    private func settingsCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                .tracking(0.6)
                .foregroundStyle(.secondary)
            content()
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(FlipDocTheme.cardBackground(for: scheme))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(FlipDocTheme.cardBorder(for: scheme), lineWidth: 1)
                )
        }
    }

    private func settingToggleRow(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                Text(subtitle)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .tint(FlipDocTheme.orange)
                .labelsHidden()
        }
    }
}

@MainActor
public final class SettingsWindowController {
    public static let shared = SettingsWindowController()

    private var window: NSWindow?

    private init() {}

    public func show() {
        if window == nil {
            let host = NSHostingController(rootView: SettingsView())
            let w = NSWindow(contentViewController: host)
            w.title = "MELD Settings"
            w.styleMask = [.titled, .closable, .fullSizeContentView]
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

