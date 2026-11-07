import AppKit
import CoreGraphics
import Foundation

/// Accessibility-free global drag gesture monitor for macOS Finder and app drags.
/// Uses `CGEventSource` session button/flag/key states + `NSPasteboard(name: .drag).changeCount`
/// so Finder drags work reliably without Accessibility TCC permissions and keyboard shortcuts are never hijacked.
@MainActor
public final class GlobalDragMonitor {
    public static let shared = GlobalDragMonitor()

    private let dragPasteboard = NSPasteboard(name: .drag)
    private var pollTimer: DispatchSourceTimer?
    private var isPollingActively: Bool = false

    private var wasPrimaryButtonDown: Bool = false
    private var wasEscapeDown: Bool = false
    private var pasteboardChangeCountBeforeMouseDown: Int = 0
    private var activeDragChangeCount: Int? = nil
    private var activeDraggedURLs: [URL] = []
    private var previousSingleModifier: ModifierMode? = nil
    private var mouseDownPoint: NSPoint = .zero
    private var hasExceededDragThreshold: Bool = false

    private let idleInterval: TimeInterval = 0.045    // ~22 Hz when idle (negligible CPU)
    private let activeInterval: TimeInterval = 0.016  // ~60 Hz only while primary mouse button is held

    private init() {
        pasteboardChangeCountBeforeMouseDown = dragPasteboard.changeCount
    }

    public func start() {
        guard AppPreferences.shared.dragModifiersEnabled else { return }
        stop()
        pasteboardChangeCountBeforeMouseDown = dragPasteboard.changeCount
        scheduleTimer(active: false)
    }

    public func stop() {
        pollTimer?.cancel()
        pollTimer = nil
        isPollingActively = false
        resetDragState()
    }

    public func setEnabled(_ enabled: Bool) {
        if enabled {
            start()
        } else {
            stop()
        }
    }

    private func scheduleTimer(active: Bool) {
        if pollTimer != nil && isPollingActively == active { return }
        pollTimer?.cancel()
        isPollingActively = active

        let timer = DispatchSource.makeTimerSource(queue: .main)
        let interval = active ? activeInterval : idleInterval
        timer.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(active ? 2 : 10))
        timer.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                self?.pollTick()
            }
        }
        pollTimer = timer
        timer.resume()
    }

    private func resetDragState() {
        wasPrimaryButtonDown = false
        wasEscapeDown = false
        activeDragChangeCount = nil
        activeDraggedURLs = []
        previousSingleModifier = nil
        hasExceededDragThreshold = false
    }

    private func pollTick() {
        let isButtonDown = CGEventSource.buttonState(.combinedSessionState, button: .left)

        // 1. Primary mouse button is UP
        if !isButtonDown {
            if wasPrimaryButtonDown {
                // Mouse button was just released!
                scheduleTimer(active: false)
                resetDragState()
                pasteboardChangeCountBeforeMouseDown = dragPasteboard.changeCount

                // Allow NSDraggingDestination.performDragOperation to fire first; otherwise commit hovered drop or dismiss.
                if RadialOverlayWindow.shared.isVisible && RadialOverlayWindow.shared.isDragSession {
                    let releaseLoc = NSEvent.mouseLocation
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.045) {
                        RadialOverlayWindow.shared.handleDragMouseReleasedFallback(at: releaseLoc)
                    }
                }
            } else {
                pasteboardChangeCountBeforeMouseDown = dragPasteboard.changeCount
            }
            return
        }

        // 2. Primary mouse button just transitioned DOWN
        if !wasPrimaryButtonDown {
            wasPrimaryButtonDown = true
            mouseDownPoint = NSEvent.mouseLocation
            hasExceededDragThreshold = false
            previousSingleModifier = currentSingleModifierMode()
            scheduleTimer(active: true)
        }

        let currentMouse = NSEvent.mouseLocation
        if !hasExceededDragThreshold {
            if hypot(currentMouse.x - mouseDownPoint.x, currentMouse.y - mouseDownPoint.y) >= 5.0 {
                hasExceededDragThreshold = true
            } else {
                return
            }
        }

        // 3. Check Escape key (virtual keyCode 53) to dismiss wheel mid-drag
        let isEscDown = CGEventSource.keyState(.combinedSessionState, key: 53)
        if isEscDown && !wasEscapeDown {
            if RadialOverlayWindow.shared.isVisible {
                RadialOverlayWindow.shared.hide()
            }
        }
        wasEscapeDown = isEscDown

        // 4. Inspect NSPasteboard(name: .drag) ONLY when Finder/source app updates its changeCount
        let currentPBCount = dragPasteboard.changeCount
        if currentPBCount != pasteboardChangeCountBeforeMouseDown && activeDragChangeCount != currentPBCount {
            activeDragChangeCount = currentPBCount
            activeDraggedURLs = readDraggedFileURLs()
        }

        guard !activeDraggedURLs.isEmpty else { return }

        // Keep radial petal highlight synced at 60fps with live cursor position while wheel is visible
        if RadialOverlayWindow.shared.isVisible && RadialOverlayWindow.shared.isDragSession {
            RadialOverlayWindow.shared.updateDragCursorScreenLocation(currentMouse)
        }

        // 5. Check modifier tap/hold (`⇧ Shift` -> conversions, `⌘ Command` -> tools, `⌃ Control` -> actions)
        let modMode = currentSingleModifierMode()
        if let mode = modMode, mode != previousSingleModifier {
            if RadialOverlayWindow.shared.isVisible {
                RadialOverlayWindow.shared.switchMode(to: mode)
            } else {
                RadialOverlayWindow.shared.show(
                    at: currentMouse,
                    for: activeDraggedURLs,
                    mode: mode,
                    isDragSession: true
                )
            }
        }
        previousSingleModifier = modMode
    }

    private func currentSingleModifierMode() -> ModifierMode? {
        let flags = CGEventSource.flagsState(.combinedSessionState)
        let hasShift = flags.contains(.maskShift)
        let hasCmd = flags.contains(.maskCommand)
        let hasCtrl = flags.contains(.maskControl)
        let hasAlt = flags.contains(.maskAlternate)

        // Require an unambiguous single modifier so multi-modifier combos are ignored
        let count = (hasShift ? 1 : 0) + (hasCmd ? 1 : 0) + (hasCtrl ? 1 : 0) + (hasAlt ? 1 : 0)
        guard count == 1 else { return nil }
        if hasShift { return .conversions }
        if hasCmd { return .tools }
        if hasCtrl { return .actions }
        return nil
    }

    private func readDraggedFileURLs() -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        if let urls = dragPasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL],
           !urls.isEmpty {
            return urls.filter { $0.isFileURL }
        }
        // Fallback for legacy NSFilenamesPboardType writers
        let legacyType = NSPasteboard.PasteboardType("NSFilenamesPboardType")
        if let paths = dragPasteboard.propertyList(forType: legacyType) as? [String] {
            return paths.map { URL(fileURLWithPath: $0) }
        }
        return []
    }
}

