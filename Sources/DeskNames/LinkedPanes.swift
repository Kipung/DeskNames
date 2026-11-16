import AppKit

struct PaneOccupancy {
    struct Occupant {
        let window: LiveWindow
        let panes: Set<Int>

        func frame(in geometry: PaneGeometry) -> CGRect? {
            guard let first = panes.min(), panes.allSatisfy(geometry.cells.indices.contains) else { return nil }
            return panes.reduce(geometry.cells[first]) { $0.union(geometry.cells[$1]) }
        }
    }
    struct Link {
        let configuration: PaneConfiguration
        let divider: PaneDivider
        let frame: CGRect
        let occupants: [Occupant]
    }

    static func links(_ windows: [LiveWindow], configurations: [PaneConfiguration], area: CGRect,
                      pixelScale: CGFloat, spaceID: UInt64) -> [Link] {
        var result: [Link] = []
        for config in configurations {
            let geometry = PaneGeometry(area: area, configuration: config, pixelScale: pixelScale)
            let occupants = matching(windows, geometry: geometry, spaceID: spaceID)
            for divider in PaneDivider.all(for: config.preset) {
                let affected = participants(for: divider, occupants: occupants)
                guard !affected.isEmpty, let frame = divider.handle(in: geometry),
                      !result.contains(where: { $0.divider.vertical == divider.vertical && close($0.frame, frame) }) else { continue }
                result.append(Link(configuration: config, divider: divider, frame: frame, occupants: affected))
            }
        }
        return result
    }

    static func matching(_ windows: [LiveWindow], geometry: PaneGeometry, spaceID: UInt64) -> [Occupant] {
        let candidates = windows.filter { !$0.minimized && $0.spaceIDs == [spaceID] }.compactMap { window -> Occupant? in
            var matches = Set<Set<Int>>()
            for start in geometry.cells.indices {
                for end in start..<geometry.cells.count {
                    guard let frame = geometry.frame(spanning: start...end), close(window.frame, frame) else { continue }
                    matches.insert(Set(geometry.cells.indices.filter { frame.contains(geometry.cells[$0]) }))
                }
            }
            guard matches.count == 1, let panes = matches.first else { return nil }
            return Occupant(window: window, panes: panes)
        }
        return candidates.enumerated().compactMap { index, candidate in
            candidates.enumerated().contains { other, occupant in
                index != other && !candidate.panes.isDisjoint(with: occupant.panes)
            } ? nil : candidate
        }
    }

    static func participants(for divider: PaneDivider, occupants: [Occupant]) -> [Occupant] {
        let before = occupants.filter { !$0.panes.isDisjoint(with: divider.before) }
        let after = occupants.filter { !$0.panes.isDisjoint(with: divider.after) }
        guard !before.isEmpty, !after.isEmpty,
              !occupants.contains(where: { !$0.panes.isDisjoint(with: divider.before) && !$0.panes.isDisjoint(with: divider.after) }) else { return [] }
        return before + after
    }
    static func close(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX-b.minX) <= 6 && abs(a.minY-b.minY) <= 6 && abs(a.width-b.width) <= 6 && abs(a.height-b.height) <= 6
    }
}

// Handles are floating panels, so they would draw over any app window. Hide one when another
// window overlaps it in front of any of its panes.
enum PaneHandleCover {
    static func hidden(_ handle: CGRect, panes: Set<UInt32>, frontToBack: [(id: UInt32, frame: CGRect)]) -> Bool {
        var remaining = panes.intersection(frontToBack.map(\.id))
        for window in frontToBack {
            if remaining.remove(window.id) != nil {
                if remaining.isEmpty { return false }
            } else if window.frame.insetBy(dx: 1, dy: 1).intersects(handle) {
                return true
            }
        }
        return false
    }
    static func onScreenWindows() -> [(id: UInt32, frame: CGRect)] {
        let infos = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return infos.compactMap { info in
            guard info[kCGWindowLayer as String] as? Int == 0, let id = info[kCGWindowNumber as String] as? UInt32,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds) else { return nil }
            return (id, frame)
        }
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
        let baseConfiguration: PaneConfiguration
        let pixelScale: CGFloat
        let frameInterval: TimeInterval
        var key: String { desktop.id + "/" + config.preset.rawValue + "/" + divider.id }
        let occupants: [PaneOccupancy.Occupant]
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
    private var detectedConfigurations: [String: [PanePreset: PaneConfiguration]] = [:]
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
        let stack = PaneHandleCover.onScreenWindows()
        seededWindows = true
        let previous = handles
        var next: [Handle] = []
        for desktop in workspace.store.desktops where desktop.isCurrent && !desktop.isFullScreen && !desktop.id.isEmpty {
            guard let screen = NSScreen.screens.first(where: { screenUUID($0) == desktop.display }) else { continue }
            let area = screenArea(screen), active = workspace.paneConfiguration(for: desktop.id)
            let configurations = [active] + PanePreset.allCases.filter { $0 != active.preset }.map {
                detectedConfigurations[desktop.id]?[$0]?.withGap(active.gap) ?? PaneConfiguration(preset: $0, gap: active.gap)
            }
            for link in PaneOccupancy.links(windows, configurations: configurations, area: area,
                                            pixelScale: screen.backingScaleFactor, spaceID: desktop.spaceID) {
                let config = link.configuration, divider = link.divider, frame = link.frame, affected = link.occupants
                guard !PaneHandleCover.hidden(frame, panes: Set(affected.map { $0.window.id }), frontToBack: stack) else { continue }
                let key = desktop.id + "/" + config.preset.rawValue + "/" + divider.id
                let existing = previous.first { $0.key == key }
                let panel = existing?.panel ?? NSPanel(contentRect: cocoaFrame(frame), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                if existing == nil {
                    panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
                    panel.level = .floating; panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
                    panel.collectionBehavior = [.stationary, .ignoresCycle]
                    let view = PaneDividerHandle(vertical: divider.vertical)
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
                }
                if panel.frame != cocoaFrame(frame) { panel.setFrame(cocoaFrame(frame), display: true) }
                next.append(Handle(panel: panel, divider: divider, desktop: desktop, area: area, config: config,
                                   baseConfiguration: active, pixelScale: screen.backingScaleFactor,
                                   frameInterval: 1.0/Double((screen.maximumFramesPerSecond > 0 ? screen.maximumFramesPerSecond : 60)), occupants: affected))
                if !panel.isVisible { panel.orderFrontRegardless() }
            }
        }
        for old in previous where !next.contains(where: { $0.panel === old.panel }) { old.panel.close() }
        handles = next
    }
    var handleWindowNumbersForTesting: [Int] { handles.map { $0.panel.windowNumber } }
    func resizeForTesting(dividerID: String, to coordinate: CGFloat) async -> Bool {
        lastScan = -Double.infinity
        tick()
        guard let handle = handles.first(where: { $0.divider.id == dividerID }) else { return false }
        let target = handle.divider.moved(to: coordinate, in: handle.area, configuration: handle.config)
        begin(handle, target: target)
        await workspace.operationTask?.value
        return workspace.paneConfiguration(for: handle.desktop.id) == target || detectedConfigurations[handle.desktop.id]?[handle.config.preset] == target
    }

    private func cocoaFrame(_ frame: CGRect) -> CGRect {
        CGRect(x: frame.minX, y: (NSScreen.screens.first?.frame.maxY ?? 0)-frame.maxY, width: frame.width, height: frame.height)
    }
    private func environmentMatches(_ session: Session) -> Bool {
        let handle = session.handle
        return workspace.panes.linkedResizing && workspace.native.trusted && !workspace.store.missionControl &&
            !OverlayController.isMissionControlOpen() &&
            workspace.paneConfiguration(for: handle.desktop.id) == handle.baseConfiguration &&
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
        workspace.run(refreshWindows: false) { [self] in
            defer { session = nil; hide(); lastScan = -Double.infinity }
            let entries = handle.occupants
            @MainActor func targets(_ config: PaneConfiguration) throws -> [(LiveWindow, CGRect)] {
                let geometry = PaneGeometry(area: handle.area, configuration: config, pixelScale: handle.pixelScale)
                return try entries.map { occupant in
                    guard let frame = occupant.frame(in: geometry),
                          workspace.native.spaces(for: occupant.window.id) == [handle.desktop.spaceID] else { throw CancellationError() }
                    return (occupant.window, frame)
                }
            }
            return try await workspace.native.withImmediateFrames(entries.map(\.window)) {
                var touched = false
                do {
                    for occupant in entries {
                        let window = occupant.window
                        guard let current = await workspace.native.refreshedForOperation(window),
                              current.spaceIDs == [handle.desktop.spaceID], !current.minimized,
                              PaneOccupancy.close(current.frame, window.frame) else { throw WindowIssue("A neighboring window changed. Try again.") }
                    }
                    var applied = handle.config
                    let started = ProcessInfo.processInfo.systemUptime
                    while true {
                        try Task.checkCancellation()
                        guard next.phase != .cancelled, environmentMatches(next) else { throw CancellationError() }
                        // A missed mouse-up must finish rather than reserve the writer forever.
                        if NSEvent.pressedMouseButtons & 1 == 0 { next.phase = .released }
                        let desired = next.config
                        if desired != applied {
                            let frames = try targets(desired)
                            touched = true
                            try await workspace.native.writeTransitionFrames(frames)
                            applied = desired
                        }
                        if next.phase == .released { break }
                        let delay = WindowTransition.delay(now: ProcessInfo.processInfo.systemUptime, started: started, interval: handle.frameInterval)
                        try await Task.sleep(nanoseconds: UInt64(delay*1_000_000_000))
                    }
                    let frames = try targets(next.config)
                    guard environmentMatches(next), next.phase != .cancelled else { throw CancellationError() }
                    try await workspace.native.animateFrames(frames, duration: 0)
                    for (window, frame) in frames {
                        guard workspace.native.verifyFrame(frame, window: window) else { throw WindowIssue("\(window.appName) needs more room. Neighboring panes were restored.") }
                    }
                    guard environmentMatches(next), next.phase != .cancelled else { throw CancellationError() }
                    if let screen = NSScreen.screens.first(where: { screenUUID($0) == handle.desktop.display }) {
                        for occupant in entries { workspace.frameHistory.remember(occupant.window, frame: occupant.window.frame, screen: screen) }
                    }
                    if handle.config.preset == handle.baseConfiguration.preset {
                        workspace.setPaneConfiguration(next.config, for: handle.desktop)
                    } else {
                        detectedConfigurations[handle.desktop.id, default: [:]][handle.config.preset] = next.config
                    }
                    return "Resized neighboring panes together."
                } catch {
                    if touched {
                        // Finish rollback before releasing the shared writer, even if the caller cancelled.
                        let restored = await Task { @MainActor in
                            var success = true
                            for occupant in entries {
                                let window = occupant.window
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
    }
    private func move(_ point: CGPoint) {
        guard let session, session.phase == .dragging else { return }
        let handle = session.handle
        session.config = handle.divider.moved(to: handle.divider.vertical ? point.x : point.y, in: handle.area, configuration: handle.config)
        let geometry = PaneGeometry(area: handle.area, configuration: session.config, pixelScale: handle.pixelScale)
        if let frame = handle.divider.handle(in: geometry) { handle.panel.setFrame(cocoaFrame(frame), display: true) }
    }
}
