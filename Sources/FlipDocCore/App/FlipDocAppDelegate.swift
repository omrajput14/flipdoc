import AppKit
import Foundation

@MainActor
public final class FlipDocAppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?

    public override init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Run as background menu-bar accessory (no Dock clutter via LSUIElement)
        NSApplication.shared.setActivationPolicy(.accessory)

        menuBarController = MenuBarController()

        if AppPreferences.shared.dragModifiersEnabled {
            GlobalDragMonitor.shared.start()
        }

        if AppPreferences.shared.showDesktopDropZone {
            FloatingDropZoneWindow.shared.setVisible(true)
        }

        let launchSilent = CommandLine.arguments.contains("--background")
        if !launchSilent {
            if !AppPreferences.shared.hasShownWelcome || CommandLine.arguments.contains("--studio") {
                AppPreferences.shared.hasShownWelcome = true
                PlaygroundDashboardWindowController.shared.show()
            } else {
                OperationProgressHUD.shared.showToast(
                    title: "FlipDoc Ready",
                    subtitle: "Drag any file & tap ⇧ Shift, ⌘ Cmd, or ⌃ Ctrl",
                    systemImage: "circle.hexagongrid.fill"
                )
            }
        }
    }

    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        PlaygroundDashboardWindowController.shared.show()
        return true
    }

    public func application(_ application: NSApplication, open urls: [URL]) {
        let valid = urls.filter(\.isFileURL)
        guard !valid.isEmpty else { return }
        let pt = NSScreen.main.map { NSPoint(x: $0.visibleFrame.midX, y: $0.visibleFrame.midY) } ?? NSEvent.mouseLocation
        RadialOverlayWindow.shared.show(
            at: pt,
            for: valid,
            mode: .conversions,
            isDragSession: false
        )
    }

    public func applicationWillTerminate(_ notification: Notification) {
        GlobalDragMonitor.shared.stop()
    }
}

