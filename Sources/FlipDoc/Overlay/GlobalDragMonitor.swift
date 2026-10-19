import AppKit

public final class GlobalDragMonitor: @unchecked Sendable {
    public static let shared = GlobalDragMonitor()

    private var globalFlagsMonitor: Any?
    private var localFlagsMonitor: Any?
    private var globalMouseDownMonitor: Any?
    private var globalMouseDraggedMonitor: Any?
    private var globalMouseUpMonitor: Any?
    private var localMouseUpMonitor: Any?

    private var isMouseDragging = false
    private var lastMouseDownChangeCount: Int = 0
    private var debounceWork: DispatchWorkItem?

    public var isEnabled: Bool {
        get {
            UserDefaults.standard.object(forKey: "EnableDragModifiers") as? Bool ?? true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "EnableDragModifiers")
            if !newValue {
                stop()
            } else {
                start()
            }
        }
    }

    public func start() {
        guard isEnabled else { return }
        stop()

        lastMouseDownChangeCount = NSPasteboard(name: .drag).changeCount

        // 1. Mouse down: reset dragging flag, snapshot pasteboard change count
        globalMouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            self?.isMouseDragging = false
            self?.lastMouseDownChangeCount = NSPasteboard(name: .drag).changeCount
        }

        // 2. Mouse dragged: marks that an active mouse drag is actually in motion
        globalMouseDraggedMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] _ in
            self?.isMouseDragging = true
        }

        // 3. Mouse up: drag session ended — dismiss overlay if visible
        let handleUp = { [weak self] in
            guard let self = self else { return }
            self.isMouseDragging = false
            self.lastMouseDownChangeCount = NSPasteboard(name: .drag).changeCount
            self.debounceWork?.cancel()
            self.debounceWork = nil
            self.hideOverlayIfShowing()
        }

        globalMouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { _ in
            handleUp()
        }
        localMouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp]) { event in
            handleUp()
            return event
        }

        // 4. Modifier keys monitor
        globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlags(event.modifierFlags)
        }
        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlags(event.modifierFlags)
            return event
        }
    }

    private func hideOverlayIfShowing() {
        DispatchQueue.main.async {
            if RadialOverlayWindow.shared.isVisible {
                RadialOverlayWindow.shared.hide()
            }
        }
    }

    private func handleFlags(_ flags: NSEvent.ModifierFlags) {
        guard isEnabled else { return }

        // CRITICAL CHECK 1: If left mouse button is NOT pressed down, user CANNOT be dragging!
        // This instantly rejects all keyboard typing & shortcuts (Cmd+C, Cmd+V, Shift+A, Cmd+Tab, etc.)
        guard (NSEvent.pressedMouseButtons & 1) != 0 else {
            debounceWork?.cancel()
            debounceWork = nil
            hideOverlayIfShowing()
            return
        }

        // CRITICAL CHECK 2: User must be actively dragging with the mouse
        guard isMouseDragging else { return }

        let relevant = flags.contains(.shift) || flags.contains(.command) || flags.contains(.control)

        // Key released — dismiss overlay immediately!
        if !relevant {
            debounceWork?.cancel()
            debounceWork = nil
            hideOverlayIfShowing()
            return
        }

        // Determine mode
        let mode: ModifierMode = flags.contains(.command) ? .tools
                               : flags.contains(.control) ? .actions
                               : .conversions

        // If overlay is already visible, update its mode dynamically in-place
        DispatchQueue.main.async {
            if RadialOverlayWindow.shared.isVisible {
                RadialOverlayWindow.shared.updateMode(mode)
            }
        }

        // Debounce to avoid flicker on quick accidental taps
        guard debounceWork == nil else { return }

        let mouseLoc = NSEvent.mouseLocation
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.debounceWork = nil

            // Re-verify mouse is still down and dragging
            guard (NSEvent.pressedMouseButtons & 1) != 0,
                  self.isMouseDragging,
                  let url = self.activeDragFileURL() else { return }

            DispatchQueue.main.async {
                RadialOverlayWindow.shared.show(at: mouseLoc, for: url, mode: mode)
            }
        }
        debounceWork = work
        DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + 0.08, execute: work)
    }

    /// Returns the file URL currently being dragged.
    /// ONLY reads from NSPasteboard(name: .drag), NEVER from .general!
    /// Ensures that the pasteboard was actually updated during this mouse drag session.
    private func activeDragFileURL() -> URL? {
        let drag = NSPasteboard(name: .drag)
        // Must have received new items since mouse button went down
        guard drag.changeCount > lastMouseDownChangeCount else { return nil }

        guard let urls = drag.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
              let first = urls.first else {
            return nil
        }
        return first
    }

    public func stop() {
        debounceWork?.cancel()
        debounceWork = nil

        if let m = globalFlagsMonitor { NSEvent.removeMonitor(m) }
        if let m = localFlagsMonitor  { NSEvent.removeMonitor(m) }
        if let m = globalMouseDownMonitor { NSEvent.removeMonitor(m) }
        if let m = globalMouseDraggedMonitor { NSEvent.removeMonitor(m) }
        if let m = globalMouseUpMonitor { NSEvent.removeMonitor(m) }
        if let m = localMouseUpMonitor  { NSEvent.removeMonitor(m) }

        globalFlagsMonitor = nil
        localFlagsMonitor = nil
        globalMouseDownMonitor = nil
        globalMouseDraggedMonitor = nil
        globalMouseUpMonitor = nil
        localMouseUpMonitor = nil
        isMouseDragging = false
    }
}
