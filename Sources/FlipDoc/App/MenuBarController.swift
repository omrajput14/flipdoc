import AppKit
import SwiftUI

@MainActor
public final class MenuBarController: NSObject {
    private var statusItem: NSStatusItem?
    
    public override init() {
        super.init()
        setupStatusItem()
        // Show floating desktop drop zone on startup
        FloatingDropZoneWindow.shared.orderFrontRegardless()
    }
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem?.button else { return }
        
        button.image = NSImage(systemSymbolName: "doc.badge.gearshape.fill", accessibilityDescription: "FlipDoc")
        button.title = " FlipDoc"
        button.action = #selector(statusItemClicked)
        button.target = self
    }
    
    @objc private func statusItemClicked() {
        let menu = NSMenu()
        
        let headerItem = NSMenuItem(title: "FlipDoc: Drop & Convert", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)
        menu.addItem(NSMenuItem.separator())
        
        let dropZoneItem = NSMenuItem(title: "Toggle Floating Drop Zone", action: #selector(toggleDropZone), keyEquivalent: "d")
        dropZoneItem.target = self
        menu.addItem(dropZoneItem)
        
        let dragModifiersItem = NSMenuItem(title: "Enable Drag Modifiers (⌘/⇧/⌃)", action: #selector(toggleDragModifiers), keyEquivalent: "")
        dragModifiersItem.state = GlobalDragMonitor.shared.isEnabled ? .on : .off
        dragModifiersItem.target = self
        menu.addItem(dragModifiersItem)
        
        let pickerItem = NSMenuItem(title: "Select File to Convert...", action: #selector(openFilePicker), keyEquivalent: "o")
        pickerItem.target = self
        menu.addItem(pickerItem)
        
        let folderItem = NSMenuItem(title: "Open FlipDoc Folder", action: #selector(openFolder), keyEquivalent: "")
        folderItem.target = self
        menu.addItem(folderItem)
        
        menu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "Quit FlipDoc", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }
    
    @objc private func toggleDropZone() {
        FloatingDropZoneWindow.shared.toggleVisibility()
    }
    
    @objc private func toggleDragModifiers(_ sender: NSMenuItem) {
        let newState = !GlobalDragMonitor.shared.isEnabled
        GlobalDragMonitor.shared.isEnabled = newState
        sender.state = newState ? .on : .off
        NotificationHelper.send(
            title: "FlipDoc",
            subtitle: newState ? "Drag modifier keys enabled (only during drag)" : "Drag modifier keys disabled (Drop Zone only)"
        )
    }
    
    @objc private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        
        if panel.runModal() == .OK, let url = panel.url {
            let mouseLoc = NSEvent.mouseLocation
            RadialOverlayWindow.shared.show(at: mouseLoc, for: url, mode: .conversions)
        }
    }
    
    @objc private func openFolder() {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: "/Users/0mrajput/Desktop/flipdoc")
    }
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
