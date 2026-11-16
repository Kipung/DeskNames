import AppKit

struct PaneRangeChord {
    struct WindowIdentity: Equatable, Hashable {
        let id: UInt32
        let pid: Int32
    }
    struct Context: Equatable {
        let window: WindowIdentity
        let desktopID: String
        let spaceID: UInt64
        let displayID: String
        let geometry: PaneGeometry
    }
    struct Anchor: Equatable {
        let pane: Int
        let context: Context
        let modifiers: UInt32
    }
    struct Request {
        let pane: Int
        let firstPane: Int
        let modifiers: UInt32
        let pid: Int32?
        let windowID: UInt32?
        let context: Context?
        let generation: UInt64
        let sequence: UInt64
    }
    private(set) var anchor: Anchor?
    private var pending: Request?
    private var generation: UInt64 = 0
    private var sequence: UInt64 = 0

    mutating func reset() { anchor = nil; pending = nil; generation &+= 1 }

    mutating func request(_ pane: Int, modifiers: UInt32, pid: Int32?, windowID: UInt32? = nil) -> Request {
        modifiersChanged(modifiers)
        if let previousPID = pending?.pid ?? anchor?.context.window.pid, previousPID != pid { reset() }
        if let oldID = pending?.windowID ?? anchor?.context.window.id, let windowID, oldID != windowID { reset() }
        sequence &+= 1
        let request = Request(pane: pane, firstPane: anchor?.pane ?? pending?.firstPane ?? pane,
                              modifiers: modifiers, pid: pid, windowID: windowID, context: anchor?.context ?? pending?.context,
                              generation: generation, sequence: sequence)
        pending = request
        return request
    }

    mutating func resolve(_ request: Request, context: Context) -> ClosedRange<Int>? {
        var resolved = PaneRangeChord()
        if request.pid == context.window.pid && (request.windowID == nil || request.windowID == context.window.id) &&
            (request.context == nil || request.context == context) {
            _ = resolved.press(request.firstPane, modifiers: request.modifiers, context: context)
        }
        let range = resolved.press(request.pane, modifiers: request.modifiers, context: context)
        // Input can end while AX discovery is suspended. Finish the accepted placement without reviving its chord.
        if generation == request.generation && sequence == request.sequence {
            anchor = resolved.anchor
            pending = nil
        }
        return range
    }

    mutating func finish(_ request: Request, succeeded: Bool) {
        if !succeeded && generation == request.generation && sequence == request.sequence { reset() }
    }

    mutating func focusedApplicationChanged(_ pid: Int32?) {
        if let previousPID = pending?.pid ?? anchor?.context.window.pid, previousPID != pid { reset() }
    }

    mutating func modifiersChanged(_ modifiers: UInt32) {
        if let held = anchor?.modifiers ?? pending?.modifiers, held != modifiers { reset() }
    }

    mutating func observe(_ context: Context?) {
        if anchor?.context != context { reset() }
    }

    mutating func press(_ pane: Int, modifiers: UInt32, context: Context) -> ClosedRange<Int>? {
        modifiersChanged(modifiers)
        observe(context)
        guard context.geometry.cells.indices.contains(pane) else { reset(); return nil }
        guard modifiers != 0 else { reset(); return pane...pane }
        if anchor == nil { anchor = Anchor(pane: pane, context: context, modifiers: modifiers) }
        let start = anchor?.pane ?? pane
        return min(start, pane)...max(start, pane)
    }
}

extension PaneGeometry {
    func frame(spanning panes: ClosedRange<Int>) -> CGRect? {
        guard cells.indices.contains(panes.lowerBound), cells.indices.contains(panes.upperBound) else { return nil }
        return panes.dropFirst().reduce(cells[panes.lowerBound]) { $0.union(cells[$1]) }
    }
}

extension LayoutController {
    func paneRangeContext(window: LiveWindow, desktop: Desktop, screen: NSScreen) -> PaneRangeChord.Context {
        PaneRangeChord.Context(window: .init(id: window.id, pid: window.pid), desktopID: desktop.id,
                               spaceID: desktop.spaceID, displayID: desktop.display,
                               geometry: PaneGeometry(area: screenArea(screen), configuration: paneConfiguration(for: desktop.id),
                                                      pixelScale: screen.backingScaleFactor))
    }

    func updatePaneRangeChord() {
        paneRangeChord.modifiersChanged(ShortcutBinding.carbonModifiers(NSEvent.modifierFlags))
        paneRangeChord.focusedApplicationChanged(NSWorkspace.shared.frontmostApplication?.processIdentifier)
        guard let anchor = paneRangeChord.anchor else { return }
        guard let focused = native.frontmostWindowIdentity(), focused.id == anchor.context.window.id,
              focused.pid == anchor.context.window.pid else { paneRangeChord.reset(); return }
        guard let desktop = store.desktops.first(where: { $0.id == anchor.context.desktopID && $0.isCurrent && !$0.isFullScreen }),
              let screen = NSScreen.screens.first(where: { screenUUID($0) == desktop.display }),
              desktop.spaceID == anchor.context.spaceID,
              PaneGeometry(area: screenArea(screen), configuration: paneConfiguration(for: desktop.id),
                           pixelScale: screen.backingScaleFactor) == anchor.context.geometry else {
            paneRangeChord.reset(); return
        }
    }
}
