import AppKit

public final class GlobalDragMonitor: @unchecked Sendable {
    public static let shared = GlobalDragMonitor()

    private var globalMonitor: Any?
    private var localMonitor: Any?

    // Debounce: only show overlay if key held for ≥80ms, avoids flicker on quick presses
    private var debounceWork: DispatchWorkItem?

    // Cache pasteboard change count so we don't do a full pasteboard read on every flag event
    private var lastChangeCount: Int = -1
    private var cachedURL: URL?

    public func start() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlags(event.modifierFlags)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlags(event.modifierFlags)
            return event
        }
    }

    private func handleFlags(_ flags: NSEvent.ModifierFlags) {
        let relevant = flags.contains(.shift) || flags.contains(.command) || flags.contains(.control)

        // Key released — cancel any pending show
        if !relevant {
            debounceWork?.cancel()
            debounceWork = nil
            return
        }

        // Already have a debounce queued — don't stack another one
        guard debounceWork == nil else { return }

        let mouseLoc = NSEvent.mouseLocation
        let mode: ModifierMode = flags.contains(.command) ? .tools
                               : flags.contains(.control) ? .actions
                               : .conversions

        let work = DispatchWorkItem { [weak self] in
            self?.debounceWork = nil
            guard let url = self?.fastPasteboardURL() else { return }
            DispatchQueue.main.async {
                RadialOverlayWindow.shared.show(at: mouseLoc, for: url, mode: mode)
            }
        }
        debounceWork = work
        // Fire after 80ms — instant-feeling but ignores accidental modifier taps
        DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + 0.08, execute: work)
    }

    /// Returns URL from drag or general pasteboard, using change-count caching to
    /// avoid expensive pasteboard reads when nothing has changed.
    private func fastPasteboardURL() -> URL? {
        let drag = NSPasteboard(name: .drag)
        let cc   = drag.changeCount
        if cc != lastChangeCount {
            lastChangeCount = cc
            cachedURL = (drag.readObjects(forClasses: [NSURL.self], options: nil) as? [URL])?.first
        }
        if let u = cachedURL { return u }

        // Fallback: general pasteboard (file copied with Cmd+C)
        return (NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: nil) as? [URL])?.first
    }

    public func stop() {
        debounceWork?.cancel()
        debounceWork = nil
        if let gm = globalMonitor { NSEvent.removeMonitor(gm) }
        if let lm = localMonitor  { NSEvent.removeMonitor(lm) }
        globalMonitor = nil
        localMonitor  = nil
    }
}

public enum PasteboardHelper {
    public static func findRecentOrDraggedFileURL() -> URL? {
        let drag = NSPasteboard(name: .drag)
        if let urls = drag.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           let first = urls.first { return first }
        return (NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: nil) as? [URL])?.first
    }
}
