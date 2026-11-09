import AppKit
import Foundation

/// Transparent overlay view added onto `NSStatusBarButton` so dropping files onto the Menu Bar icon summons the radial wheel!
@MainActor
private final class StatusBarDropOverlayView: NSView {
    var onFilesDropped: (([URL], NSPoint) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL, .URL, NSPasteboard.PasteboardType("NSFilenamesPboardType")])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil // Let normal clicks open the status bar menu!
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pb = sender.draggingPasteboard
        guard let urls = (pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL])?.filter(\.isFileURL),
              !urls.isEmpty else {
            return false
        }
        let screenAnchor: NSPoint
        if let win = self.window {
            screenAnchor = NSPoint(x: win.frame.midX, y: win.frame.minY - 190)
        } else {
            screenAnchor = NSEvent.mouseLocation
        }
        onFilesDropped?(urls, screenAnchor)
        return true
    }
}

@MainActor
public final class MenuBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let statusMenu = NSMenu()

    public override init() {
        super.init()
        setupStatusBar()
    }

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
            let image = NSImage(systemSymbolName: "circle.hexagongrid.fill", accessibilityDescription: "MELD")?
                .withSymbolConfiguration(config)
            image?.isTemplate = true
            button.image = image
            button.toolTip = "MELD — Drag any file & tap ⇧ Shift, ⌘ Cmd, or ⌃ Ctrl"

            let dropOverlay = StatusBarDropOverlayView(frame: button.bounds)
            dropOverlay.autoresizingMask = [.width, .height]
            dropOverlay.onFilesDropped = { urls, pt in
                RadialOverlayWindow.shared.show(
                    at: pt,
                    for: urls,
                    mode: .conversions,
                    isDragSession: false
                )
            }
            button.addSubview(dropOverlay)
        }

        statusMenu.delegate = self
        rebuildMenu()
        statusItem.menu = statusMenu
    }

    public func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
    }

    private func rebuildMenu() {
        statusMenu.removeAllItems()
        let prefs = AppPreferences.shared

        let header = NSMenuItem(
            title: prefs.dragModifiersEnabled
                ? "MELD Ready — Drag + ⇧ / ⌘ / ⌃"
                : "MELD Paused (Modifiers Disabled)",
            action: nil,
            keyEquivalent: ""
        )
        header.isEnabled = false
        statusMenu.addItem(header)
        statusMenu.addItem(.separator())

        let studioItem = NSMenuItem(title: "Open MELD Studio…", action: #selector(openStudio), keyEquivalent: "o")
        studioItem.target = self
        statusMenu.addItem(studioItem)

        let convertFilesItem = NSMenuItem(title: "Convert Files…", action: #selector(chooseFilesToConvert), keyEquivalent: "k")
        convertFilesItem.target = self
        statusMenu.addItem(convertFilesItem)

        let floatItem = NSMenuItem(
            title: "Show Float Shelf\(FloatingShelfManager.shared.items.isEmpty ? "" : " (\(FloatingShelfManager.shared.items.count))")",
            action: #selector(openFloatShelf),
            keyEquivalent: "f"
        )
        floatItem.target = self
        statusMenu.addItem(floatItem)

        statusMenu.addItem(.separator())

        let dragToggle = NSMenuItem(title: "Enable Drag Modifiers (⇧ ⌘ ⌃)", action: #selector(toggleDragModifiers), keyEquivalent: "")
        dragToggle.target = self
        dragToggle.state = prefs.dragModifiersEnabled ? .on : .off
        statusMenu.addItem(dragToggle)

        let dropZoneToggle = NSMenuItem(title: "Show Desktop Drop Zone", action: #selector(toggleDropZone), keyEquivalent: "d")
        dropZoneToggle.target = self
        dropZoneToggle.state = prefs.showDesktopDropZone ? .on : .off
        statusMenu.addItem(dropZoneToggle)

        // Recent Conversions Submenu
        let recentsMenu = NSMenu()
        let validRecents = prefs.recentRecords.filter(\.existsOnDisk)
        if validRecents.isEmpty {
            let empty = NSMenuItem(title: "No Recent Conversions", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            recentsMenu.addItem(empty)
        } else {
            for rec in validRecents.prefix(10) {
                let item = NSMenuItem(
                    title: "\(rec.outputName)  —  \(rec.actionSummary)",
                    action: #selector(revealRecentItem(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = rec.outputURL
                recentsMenu.addItem(item)
            }
            recentsMenu.addItem(.separator())
            let clearItem = NSMenuItem(title: "Clear History", action: #selector(clearRecents), keyEquivalent: "")
            clearItem.target = self
            recentsMenu.addItem(clearItem)
        }
        let recentsRoot = NSMenuItem(title: "Recent Conversions", action: nil, keyEquivalent: "")
        recentsRoot.submenu = recentsMenu
        statusMenu.addItem(recentsRoot)

        statusMenu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        statusMenu.addItem(settingsItem)

        let quitItem = NSMenuItem(title: "Quit MELD", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        statusMenu.addItem(quitItem)
    }

    @objc private func openStudio() {
        PlaygroundDashboardWindowController.shared.show()
    }

    @objc private func chooseFilesToConvert() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Open Wheel"
        if panel.runModal() == .OK, !panel.urls.isEmpty {
            let screenPt = NSScreen.main.map { NSPoint(x: $0.visibleFrame.midX, y: $0.visibleFrame.midY) } ?? NSEvent.mouseLocation
            RadialOverlayWindow.shared.show(
                at: screenPt,
                for: panel.urls,
                mode: .conversions,
                isDragSession: false
            )
        }
    }

    @objc private func openFloatShelf() {
        FloatingShelfManager.shared.showWindow()
    }

    @objc private func toggleDragModifiers() {
        AppPreferences.shared.dragModifiersEnabled.toggle()
    }

    @objc private func toggleDropZone() {
        FloatingDropZoneWindow.shared.toggleVisibility()
    }

    @objc private func revealRecentItem(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc private func clearRecents() {
        AppPreferences.shared.clearHistory()
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.show()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}

