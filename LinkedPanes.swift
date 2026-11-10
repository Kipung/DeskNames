import AppKit

struct PaneOccupancy {
    static func matching(_ windows: [LiveWindow], geometry: PaneGeometry, spaceID: UInt64) -> [Int: LiveWindow] {
        var result: [Int: LiveWindow] = [:]
        for (index, cell) in geometry.cells.enumerated() {
            let matches = windows.filter { !$0.minimized && $0.spaceIDs == [spaceID] && close($0.frame, cell) }
            if matches.count == 1 { result[index] = matches[0] }
        }
        return result
    }
    static func close(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX-b.minX) <= 6 && abs(a.minY-b.minY) <= 6 && abs(a.width-b.width) <= 6 && abs(a.height-b.height) <= 6
    }
}

private final class PaneDividerHandle: NSView {
    let vertical: Bool
    var begin: (() -> Void)?
    var move: ((CGPoint) -> Void)?
    var end: (() -> Void)?
    private var hovered = false
    init(vertical: Bool) {
        self.vertical = vertical
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.splitter)
        setAccessibilityLabel("Resize neighboring panes together")
        toolTip = "Drag to resize neighboring panes. Escape cancels."
    }
    required init?(coder: NSCoder) { nil }
    override var acceptsFirstResponder: Bool { false }
    override func resetCursorRects() { addCursorRect(bounds, cursor: vertical ? .resizeLeftRight : .resizeUpDown) }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        (hovered ? NSColor.controlAccentColor : NSColor.secondaryLabelColor.withAlphaComponent(0.55)).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: vertical ? 2 : 8, dy: vertical ? 8 : 2), xRadius: 2, yRadius: 2).fill()
    }
    override func mouseDown(with event: NSEvent) { begin?() }
    override func mouseDragged(with event: NSEvent) {
        guard let point = event.cgEvent?.location else { return }
        move?(point)
    }
    override func mouseUp(with event: NSEvent) { end?() }
}

@MainActor final class LinkedPaneController {
    private struct Handle {
        let panel: NSPanel
        let divider: PaneDivider
        let desktop: Desktop
        let area: CGRect
        let config: PaneConfiguration
        let windows: [Int: LiveWindow]
    }
    private final class Session {
        enum Phase { case dragging, released, cancelled }
        let handle: Handle
        var config: PaneConfiguration
        var phase = Phase.dragging
        init(_ handle: Handle) { self.handle = handle; config = handle.config }
    }
    private let workspace: LayoutController
    private var handles: [Handle] = []
    private var session: Session?
    private var lastScan = -Double.infinity
    private var seededWindows = false
    private var globalMonitor: Any?
    private var localMonitor: Any?

    init(workspace: LayoutController) {
        self.workspace = workspace
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { MainActor.assumeIsolated { self?.session?.phase = .cancelled } }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { MainActor.assumeIsolated { self?.session?.phase = .cancelled } }
            return event
        }
    }
    func stop() {
        session?.phase = .cancelled
        hide()
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil; localMonitor = nil
    }
    private func hide() { for handle in handles { handle.panel.close() }; handles.removeAll() }

    func tick() {
        if let session {
            if !environmentMatches(session) { session.phase = .cancelled }
            return
        }
        if !workspace.panes.linkedResizing { seededWindows = false }
        guard workspace.panes.linkedResizing, workspace.native.trusted, !workspace.busy,
              !workspace.store.missionControl, !OverlayController.isMissionControlOpen() else { hide(); return }
        guard NSEvent.pressedMouseButtons == 0 else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now-lastScan > 1 else { return }
        lastScan = now
        let windows = seededWindows ? workspace.native.trackedPaneWindows() : workspace.native.windows()
        seededWindows = true
        hide()
        for desktop in workspace.store.desktops where desktop.isCurrent && !desktop.isFullScreen && !desktop.id.isEmpty {
            guard let screen = NSScreen.screens.first(where: { screenUUID($0) == desktop.display }) else { continue }
            let area = screenArea(screen), config = workspace.paneConfiguration(for: desktop.id)
            let geometry = PaneGeometry(area: area, configuration: config)
            let occupants = PaneOccupancy.matching(windows, geometry: geometry, spaceID: desktop.spaceID)
            for divider in PaneDivider.all(for: config.preset) {
                let occupiedBefore = divider.before.filter { occupants[$0] != nil }
                let occupiedAfter = divider.after.filter { occupants[$0] != nil }
                guard !occupiedBefore.isEmpty, !occupiedAfter.isEmpty, let frame = divider.handle(in: geometry) else { continue }
                let panel = NSPanel(contentRect: cocoaFrame(frame), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
                panel.level = .floating; panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
                panel.collectionBehavior = [.stationary, .ignoresCycle]
                let view = PaneDividerHandle(vertical: divider.vertical)
                let affected = occupants.filter { divider.before.contains($0.key) || divider.after.contains($0.key) }
                let handle = Handle(panel: panel, divider: divider, desktop: desktop, area: area, config: config, windows: affected)
                view.begin = { [weak self, weak panel] in
                    guard let self, let handle = self.handles.first(where: { $0.panel === panel }) else { return }
                    self.begin(handle)
                }
                view.move = { [weak self] in self?.move($0) }
                view.end = { [weak self] in
                    guard self?.session?.phase == .dragging else { return }
                    self?.session?.phase = .released
                }
                panel.contentView = view
                panel.orderFrontRegardless()
                handles.append(handle)
            }
        }
    }
    func resizeForTesting(dividerID: String, to coordinate: CGFloat) async -> Bool {
        lastScan = -Double.infinity
        tick()
        guard let handle = handles.first(where: { $0.divider.id == dividerID }) else { return false }
        let target = handle.divider.moved(to: coordinate, in: handle.area, configuration: handle.config)
        begin(handle, target: target)
        await workspace.operationTask?.value
        return workspace.paneConfiguration(for: handle.desktop.id) == target
    }

    private func cocoaFrame(_ frame: CGRect) -> CGRect {
        CGRect(x: frame.minX, y: (NSScreen.screens.first?.frame.maxY ?? 0)-frame.maxY, width: frame.width, height: frame.height)
    }
    private func environmentMatches(_ session: Session) -> Bool {
        let handle = session.handle
        return workspace.panes.linkedResizing && workspace.native.trusted && !workspace.store.missionControl &&
            !OverlayController.isMissionControlOpen() &&
            workspace.paneConfiguration(for: handle.desktop.id) == handle.config &&
            NSScreen.screens.contains { screenUUID($0) == handle.desktop.display && screenArea($0) == handle.area } &&
            workspace.store.reader.read().contains { $0.id == handle.desktop.id && $0.spaceID == handle.desktop.spaceID && $0.isCurrent && !$0.isFullScreen }
    }
    private func begin(_ handle: Handle, target: PaneConfiguration? = nil) {
        guard session == nil, !workspace.busy else { return }
        let next = Session(handle)
        if let target { next.config = target; next.phase = .released }
        guard environmentMatches(next) else { hide(); return }
        session = next
        for other in handles where other.panel !== handle.panel { other.panel.orderOut(nil) }
        workspace.run { [self] in
            defer { session = nil; hide(); lastScan = -Double.infinity }
            let entries = handle.windows.sorted { $0.key < $1.key }
            var touched = false
            do {
                for (_, window) in entries {
                    guard let current = await workspace.native.refreshedForOperation(window),
                          current.spaceIDs == [handle.desktop.spaceID], !current.minimized,
                          PaneOccupancy.close(current.frame, window.frame) else { throw WindowIssue("A neighboring window changed. Try again.") }
                }
                var applied = handle.config
                while true {
                    try Task.checkCancellation()
                    guard next.phase != .cancelled, environmentMatches(next) else { throw CancellationError() }
                    // A missed mouse-up must finish rather than reserve the writer forever.
                    if NSEvent.pressedMouseButtons & 1 == 0 { next.phase = .released }
                    let desired = next.config
                    if desired != applied {
                        let frames = PaneGeometry(area: handle.area, configuration: desired).cells
                        for (index, window) in entries {
                            try Task.checkCancellation()
                            guard environmentMatches(next), workspace.native.spaces(for: window.id) == [handle.desktop.spaceID], frames.indices.contains(index) else { throw CancellationError() }
                            touched = true
                            try await workspace.native.writeTransitionFrame(frames[index], window: window)
                        }
                        applied = desired
                    }
                    if next.phase == .released { break }
                    try await Task.sleep(nanoseconds: 16_666_667)
                }
                let frames = PaneGeometry(area: handle.area, configuration: next.config).cells
                for (index, window) in entries {
                    guard environmentMatches(next), next.phase != .cancelled else { throw CancellationError() }
                    try await workspace.native.setFrame(frames[index], window: window)
                    guard workspace.native.verifyFrame(frames[index], window: window) else { throw WindowIssue("\(window.appName) needs more room. Neighboring panes were restored.") }
                }
                guard environmentMatches(next), next.phase != .cancelled else { throw CancellationError() }
                if let screen = NSScreen.screens.first(where: { screenUUID($0) == handle.desktop.display }) {
                    for (_, window) in entries { workspace.frameHistory.remember(window, frame: window.frame, screen: screen) }
                }
                workspace.setPaneConfiguration(next.config, for: handle.desktop)
                return "Resized neighboring panes together."
            } catch {
                if touched {
                    // Finish rollback before releasing the shared writer, even if the caller cancelled.
                    let restored = await Task { @MainActor in
                        var success = true
                        for (_, window) in entries {
                            guard self.workspace.native.identityExists(window),
                                  self.workspace.native.spaces(for: window.id) == [handle.desktop.spaceID],
                                  NSScreen.screens.contains(where: { screenUUID($0) == handle.desktop.display && screenArea($0) == handle.area }) else { success = false; continue }
                            do { try await self.workspace.native.setFrame(window.frame, window: window) }
                            catch { success = false }
                            if !self.workspace.native.verifyFrame(window.frame, window: window) { success = false }
                        }
                        return success
                    }.value
                    if !restored { throw WindowIssue("Resize stopped. Some windows could not return to their original size; the pane layout was not saved.") }
                }
                throw error
            }
        }
    }
    private func move(_ point: CGPoint) {
        guard let session, session.phase == .dragging else { return }
        let handle = session.handle
        session.config = handle.divider.moved(to: handle.divider.vertical ? point.x : point.y, in: handle.area, configuration: handle.config)
        let geometry = PaneGeometry(area: handle.area, configuration: session.config)
        if let frame = handle.divider.handle(in: geometry) { handle.panel.setFrame(cocoaFrame(frame), display: true) }
    }
}
