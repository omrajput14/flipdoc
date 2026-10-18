import AppKit

public final class GlobalDragMonitor: @unchecked Sendable {
    public static let shared = GlobalDragMonitor()
    
    private var globalMonitor: Any?
    private var localMonitor: Any?
    
    public func start() {
        // Monitor global modifier key changes
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlags(event.modifierFlags)
        }
        
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlags(event.modifierFlags)
            return event
        }
    }
    
    private func handleFlags(_ flags: NSEvent.ModifierFlags) {
        let mouseLoc = NSEvent.mouseLocation
        
        if flags.contains(.shift) {
            // Check if there is a file on the general pasteboard or currently hovered
            if let draggedURL = PasteboardHelper.findRecentOrDraggedFileURL() {
                RadialOverlayWindow.shared.show(at: mouseLoc, for: draggedURL, mode: .conversions)
            }
        } else if flags.contains(.command) {
            if let draggedURL = PasteboardHelper.findRecentOrDraggedFileURL() {
                RadialOverlayWindow.shared.show(at: mouseLoc, for: draggedURL, mode: .tools)
            }
        } else if flags.contains(.control) {
            if let draggedURL = PasteboardHelper.findRecentOrDraggedFileURL() {
                RadialOverlayWindow.shared.show(at: mouseLoc, for: draggedURL, mode: .actions)
            }
        }
    }
    
    public func stop() {
        if let gm = globalMonitor { NSEvent.removeMonitor(gm) }
        if let lm = localMonitor { NSEvent.removeMonitor(lm) }
        globalMonitor = nil
        localMonitor = nil
    }
}

public enum PasteboardHelper {
    public static func findRecentOrDraggedFileURL() -> URL? {
        let pb = NSPasteboard(name: .drag)
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], let first = urls.first {
            return first
        }
        // Fallback to general pasteboard if user copied or selected a file
        let general = NSPasteboard.general
        if let urls = general.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], let first = urls.first {
            return first
        }
        return nil
    }
}
