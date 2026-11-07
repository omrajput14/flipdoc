import AppKit
import SwiftUI

/// Flipped `NSView` container hosting `RadialFanView` that implements `NSDraggingDestination`
/// AND pointer hover/click hit-testing so both Finder Zero-Click drags and normal clicks work seamlessly!
@MainActor
final class OverlayDropContainerView: NSView {
    override var isFlipped: Bool { true }

    var onPetalHoverChanged: ((Int?) -> Void)?
    var onPetalClicked: ((Int) -> Void)?
    var onDragDropCommitted: (([URL]?, Int) -> Void)?
    var onCancelRequested: (() -> Void)?
    var optionCountProvider: (() -> Int)?
    var isDragSessionProvider: (() -> Bool)?

    private var trackingAreaRef: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([
            .fileURL,
            .URL,
            NSPasteboard.PasteboardType("NSFilenamesPboardType")
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingAreaRef {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaRef = area
    }

    // MARK: - Wheel-Center Relative Hit Testing (+Y points down)

    func petalIndex(atViewPoint pt: NSPoint) -> Int? {
        let count = optionCountProvider?() ?? 0
        let dx = pt.x - RadialFanView.wheelCenterX
        let dy = pt.y - RadialFanView.wheelCenterY
        return PetalGeometry.hitTest(dx: dx, dy: dy, count: count)
    }

    // MARK: - NSDraggingDestination (Finder Zero-Click Drag & Drop)

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        updateHover(fromDraggingInfo: sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        updateHover(fromDraggingInfo: sender)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onPetalHoverChanged?(nil)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let winPt = sender.draggingLocation
        let viewPt = convert(winPt, from: nil)
        return petalIndex(atViewPoint: viewPt) != nil
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let winPt = sender.draggingLocation
        let viewPt = convert(winPt, from: nil)
        guard let idx = petalIndex(atViewPoint: viewPt) else {
            onCancelRequested?()
            return false
        }

        let pb = sender.draggingPasteboard
        let urls = (pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL])?
            .filter(\.isFileURL)
        onDragDropCommitted?(urls, idx)
        return true
    }

    private func updateHover(fromDraggingInfo sender: NSDraggingInfo) -> NSDragOperation {
        let winPt = sender.draggingLocation
        let viewPt = convert(winPt, from: nil)
        let idx = petalIndex(atViewPoint: viewPt)
        onPetalHoverChanged?(idx)
        return idx != nil ? .copy : []
    }

    // MARK: - Pointer Hover & Click (Non-Drag / File Picker / DropZone Mode)

    override func mouseMoved(with event: NSEvent) {
        guard isDragSessionProvider?() == false else { return }
        let viewPt = convert(event.locationInWindow, from: nil)
        let idx = petalIndex(atViewPoint: viewPt)
        onPetalHoverChanged?(idx)
    }

    override func mouseExited(with event: NSEvent) {
        guard isDragSessionProvider?() == false else { return }
        onPetalHoverChanged?(nil)
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragSessionProvider?() == false else {
            super.mouseUp(with: event)
            return
        }
        let viewPt = convert(event.locationInWindow, from: nil)
        if let idx = petalIndex(atViewPoint: viewPt) {
            onPetalClicked?(idx)
            return
        }
        // Check if user clicked inside center cancel circle
        let dx = viewPt.x - RadialFanView.wheelCenterX
        let dy = viewPt.y - RadialFanView.wheelCenterY
        if hypot(dx, dy) < PetalGeometry.innerRadius {
            onCancelRequested?()
            return
        }
        super.mouseUp(with: event)
    }
}

@MainActor
public final class RadialOverlayWindow: NSPanel {
    public static let shared = RadialOverlayWindow()

    public private(set) var isDragSession: Bool = false
    private var viewModel = RadialFanViewModel(urls: [], mode: .conversions, isDragSession: false)
    private var dropContainer: OverlayDropContainerView!
    private var hostingView: NSHostingView<RadialFanView>!
    private var clickOutsideMonitor: Any?
    private var localKeyMonitor: Any?
    private var didConsumeSessionDrop: Bool = false

    public init() {
        let rect = NSRect(
            x: 0,
            y: 0,
            width: RadialFanView.canvasWidth,
            height: RadialFanView.canvasHeight
        )
        super.init(
            contentRect: rect,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        self.isOpaque = false
        self.backgroundColor = .clear
        self.level = .popUpMenu
        self.hasShadow = false
        self.ignoresMouseEvents = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        self.isMovableByWindowBackground = false

        setupContentHierarchy()
    }

    private func setupContentHierarchy() {
        let rect = NSRect(x: 0, y: 0, width: RadialFanView.canvasWidth, height: RadialFanView.canvasHeight)
        let container = OverlayDropContainerView(frame: rect)
        container.autoresizingMask = [.width, .height]

        let rootView = RadialFanView(
            viewModel: viewModel,
            onSelect: { [weak self] option in
                self?.commitSelection(option, overrideURLs: nil)
            },
            onClose: { [weak self] in
                self?.hide()
            },
            onModeChange: { [weak self] newMode in
                self?.switchMode(to: newMode)
            }
        )

        let host = NSHostingView(rootView: rootView)
        host.frame = rect
        host.autoresizingMask = [.width, .height]
        container.addSubview(host)

        container.optionCountProvider = { [weak self] in
            self?.viewModel.options.count ?? 0
        }
        container.isDragSessionProvider = { [weak self] in
            self?.isDragSession ?? false
        }
        container.onPetalHoverChanged = { [weak self] idx in
            self?.setHoveredPetal(idx)
        }
        container.onPetalClicked = { [weak self] idx in
            guard let self = self else { return }
            let opts = self.viewModel.options
            guard idx >= 0, idx < opts.count else { return }
            self.commitSelection(opts[idx], overrideURLs: nil)
        }
        container.onDragDropCommitted = { [weak self] droppedURLs, idx in
            guard let self = self, !self.didConsumeSessionDrop else { return }
            let opts = self.viewModel.options
            guard idx >= 0, idx < opts.count else { return }
            self.didConsumeSessionDrop = true
            self.commitSelection(opts[idx], overrideURLs: droppedURLs)
        }
        container.onCancelRequested = { [weak self] in
            self?.hide()
        }

        self.dropContainer = container
        self.hostingView = host
        self.contentView = container
    }

    public override var canBecomeKey: Bool { !isDragSession }
    public override var canBecomeMain: Bool { false }

    public override func cancelOperation(_ sender: Any?) {
        hide()
    }

    /// Shows the radial wheel with its exact geometric donut center anchored at `screenPoint` (clamped safely on screen).
    public func show(
        at screenPoint: NSPoint,
        for fileURLs: [URL],
        mode: ModifierMode,
        isDragSession: Bool = false
    ) {
        guard !fileURLs.isEmpty else { return }
        self.isDragSession = isDragSession
        self.didConsumeSessionDrop = false

        viewModel.urls = fileURLs
        viewModel.currentMode = mode
        viewModel.isDragSession = isDragSession
        viewModel.hoveredIndex = nil
        viewModel.didBloom = false

        positionWheelCenter(at: screenPoint)

        self.orderFrontRegardless()
        if !isDragSession {
            self.makeKey()
            installNonDragMonitors()
        } else {
            removeNonDragMonitors()
        }

        withAnimation(.spring(response: 0.20, dampingFraction: 0.78)) {
            viewModel.didBloom = true
        }
    }

    /// Convenience single-URL overload.
    public func show(at screenPoint: NSPoint, for fileURL: URL, mode: ModifierMode) {
        show(at: screenPoint, for: [fileURL], mode: mode, isDragSession: false)
    }

    public func switchMode(to mode: ModifierMode) {
        guard isVisible, viewModel.currentMode != mode else { return }
        SoundAndHaptics.shared.playPetalTick()
        viewModel.hoveredIndex = nil
        withAnimation(.spring(response: 0.18, dampingFraction: 0.80)) {
            viewModel.currentMode = mode
        }
        if isDragSession {
            updateDragCursorScreenLocation(NSEvent.mouseLocation)
        }
    }

    /// Live 60fps cursor update during an active Finder drag session.
    public func updateDragCursorScreenLocation(_ screenPoint: NSPoint) {
        guard isVisible else { return }
        let windowPt = convertPoint(fromScreen: screenPoint)
        let viewPt = dropContainer.convert(windowPt, from: nil)
        let idx = dropContainer.petalIndex(atViewPoint: viewPt)
        setHoveredPetal(idx)
    }

    /// Fallback called 45ms after mouse release if CoreDrag did not already invoke `performDragOperation`.
    public func handleDragMouseReleasedFallback(at releaseScreenPoint: NSPoint) {
        guard isVisible, isDragSession else { return }
        if didConsumeSessionDrop {
            hide()
            return
        }
        let windowPt = convertPoint(fromScreen: releaseScreenPoint)
        let viewPt = dropContainer.convert(windowPt, from: nil)
        if let idx = dropContainer.petalIndex(atViewPoint: viewPt) {
            let opts = viewModel.options
            if idx >= 0 && idx < opts.count {
                didConsumeSessionDrop = true
                commitSelection(opts[idx], overrideURLs: nil)
                return
            }
        }
        hide()
    }

    private func setHoveredPetal(_ index: Int?) {
        guard viewModel.hoveredIndex != index else { return }
        viewModel.hoveredIndex = index
        if index != nil {
            SoundAndHaptics.shared.playPetalTick()
        }
    }

    private func positionWheelCenter(at screenPoint: NSPoint) {
        // Notice: In flipped view coordinates, wheel center is `(wheelCenterX, wheelCenterY)` from top-left!
        // In AppKit window coordinates (origin at bottom-left), that corresponds to:
        //   centerOffsetX = wheelCenterX
        //   centerOffsetY = canvasHeight - wheelCenterY
        let centerOffsetX = RadialFanView.wheelCenterX
        let centerOffsetY = RadialFanView.canvasHeight - RadialFanView.wheelCenterY

        var origin = NSPoint(
            x: screenPoint.x - centerOffsetX,
            y: screenPoint.y - centerOffsetY
        )

        let targetScreen = NSScreen.screens.first(where: { NSMouseInRect(screenPoint, $0.frame, false) }) ?? NSScreen.main
        if let screen = targetScreen {
            let visible = screen.visibleFrame
            origin.x = max(visible.minX + 6, min(origin.x, visible.maxX - frame.width - 6))
            origin.y = max(visible.minY + 6, min(origin.y, visible.maxY - frame.height - 6))
        }
        self.setFrameOrigin(origin)
    }

    public func hide() {
        removeNonDragMonitors()
        viewModel.hoveredIndex = nil
        viewModel.didBloom = false
        self.orderOut(nil)
    }

    private func commitSelection(_ option: FanOption, overrideURLs: [URL]?) {
        let urls = (overrideURLs?.isEmpty == false) ? overrideURLs! : viewModel.urls
        guard !urls.isEmpty else {
            hide()
            return
        }
        hide()
        ActionDispatcher.shared.execute(option: option, urls: urls)
    }

    // MARK: - Keyboard & Click-Outside Monitors (Non-Drag Mode)

    private func installNonDragMonitors() {
        removeNonDragMonitors()
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self = self, self.isVisible else { return }
                if !self.frame.contains(NSEvent.mouseLocation) {
                    self.hide()
                }
            }
        }

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self = self, self.isVisible else { return event }
            if event.type == .flagsChanged {
                let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                if flags == .shift { self.switchMode(to: .conversions) }
                else if flags == .command { self.switchMode(to: .tools) }
                else if flags == .control { self.switchMode(to: .actions) }
                return event
            }
            let opts = self.viewModel.options
            switch event.keyCode {
            case 53: // Esc
                self.hide()
                return nil
            case 36, 49: // Return / Space
                if let idx = self.viewModel.hoveredIndex, idx < opts.count {
                    self.commitSelection(opts[idx], overrideURLs: nil)
                    return nil
                }
            case 124, 125: // Right / Down
                if !opts.isEmpty {
                    let next = ((self.viewModel.hoveredIndex ?? -1) + 1) % opts.count
                    self.setHoveredPetal(next)
                    return nil
                }
            case 123, 126: // Left / Up
                if !opts.isEmpty {
                    let prev = ((self.viewModel.hoveredIndex ?? 0) - 1 + opts.count) % opts.count
                    self.setHoveredPetal(prev)
                    return nil
                }
            default:
                break
            }
            return event
        }
    }

    private func removeNonDragMonitors() {
        if let m = clickOutsideMonitor {
            NSEvent.removeMonitor(m)
            clickOutsideMonitor = nil
        }
        if let k = localKeyMonitor {
            NSEvent.removeMonitor(k)
            localKeyMonitor = nil
        }
    }
}

