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

    var hasInput: Bool { anchor != nil || pending != nil }
    private var traceState: [String: Any] {
        ["generation": generation, "requestSequence": sequence,
         "anchorPane": anchor?.pane as Any? ?? NSNull(), "pendingFirstPane": pending?.firstPane as Any? ?? NSNull(),
         "heldModifiers": (anchor?.modifiers ?? pending?.modifiers) as Any? ?? NSNull(),
         "windowID": (anchor?.context.window.id ?? pending?.windowID) as Any? ?? NSNull()]
    }

    mutating func reset(reason: String = "external") {
        if hasInput { ShortcutTrace.record("reset", traceState.merging(["reason": reason]) { _, new in new }) }
        anchor = nil; pending = nil; generation &+= 1
    }

    mutating func request(_ pane: Int, modifiers: UInt32, pid: Int32?, windowID: UInt32? = nil) -> Request {
        ShortcutTrace.record("request-input", traceState.merging(["pane": pane, "modifiers": modifiers,
            "inputPID": pid as Any? ?? NSNull(), "inputWindowID": windowID as Any? ?? NSNull()]) { _, new in new })
        modifiersChanged(modifiers, source: "request")
        if let previousPID = pending?.pid ?? anchor?.context.window.pid, previousPID != pid { reset(reason: "request-pid") }
        if let oldID = pending?.windowID ?? anchor?.context.window.id, let windowID, oldID != windowID { reset(reason: "request-window") }
        sequence &+= 1
        let request = Request(pane: pane, firstPane: anchor?.pane ?? pending?.firstPane ?? pane,
                              modifiers: modifiers, pid: pid, windowID: windowID, context: anchor?.context ?? pending?.context,
                              generation: generation, sequence: sequence)
        pending = request
        ShortcutTrace.record("request-captured", traceState.merging(["pane": pane, "firstPane": request.firstPane,
            "contextWindowID": request.context?.window.id as Any? ?? NSNull()]) { _, new in new })
        return request
    }

    mutating func resolve(_ request: Request, context: Context) -> ClosedRange<Int>? {
        var resolved = PaneRangeChord()
        if request.pid == context.window.pid && (request.windowID == nil || request.windowID == context.window.id) &&
            (request.context == nil || request.context == context) {
            _ = resolved.press(request.firstPane, modifiers: request.modifiers, context: context)
        }
        let range = resolved.press(request.pane, modifiers: request.modifiers, context: context)
        ShortcutTrace.record("resolve", traceState.merging(["inputSequence": request.sequence, "inputGeneration": request.generation,
            "pane": request.pane, "firstPane": request.firstPane, "inputWindowID": request.windowID as Any? ?? NSNull(),
            "resolvedWindowID": context.window.id, "pidMatches": request.pid == context.window.pid,
            "contextMatches": request.context == nil || request.context == context,
            "range": range.map { Array($0) } as Any? ?? NSNull()]) { _, new in new })
        // Input can end while AX discovery is suspended. Finish the accepted placement without reviving its chord.
        if generation == request.generation && sequence == request.sequence {
            anchor = resolved.anchor
            pending = nil
        }
        return range
    }

    mutating func finish(_ request: Request, succeeded: Bool) {
        ShortcutTrace.record("finish", traceState.merging(["inputSequence": request.sequence,
            "inputGeneration": request.generation, "succeeded": succeeded]) { _, new in new })
        if !succeeded && generation == request.generation && sequence == request.sequence { reset(reason: "request-failed") }
    }

    mutating func focusedApplicationChanged(_ pid: Int32?) {
        if let previousPID = pending?.pid ?? anchor?.context.window.pid, previousPID != pid { reset(reason: "focused-app") }
    }

    mutating func modifiersChanged(_ modifiers: UInt32, source: String = "event") {
        if let held = anchor?.modifiers ?? pending?.modifiers, held != modifiers {
            ShortcutTrace.record("modifier-mismatch", traceState.merging(["source": source, "incomingModifiers": modifiers]) { _, new in new })
            reset(reason: "modifiers-" + source)
        }
    }

    mutating func observe(_ context: Context?) {
        if anchor?.context != context { reset(reason: "observed-context") }
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
        let modifiers = ShortcutBinding.carbonModifiers(NSEvent.modifierFlags)
        if paneRangeChord.hasInput {
            ShortcutTrace.record("poll", ["modifiers": modifiers, "combinedFlags": CGEventSource.flagsState(.combinedSessionState).rawValue,
                "hidFlags": CGEventSource.flagsState(.hidSystemState).rawValue,
                "pid": NSWorkspace.shared.frontmostApplication?.processIdentifier as Any? ?? NSNull()])
        }
        paneRangeChord.modifiersChanged(modifiers, source: "poll")
        paneRangeChord.focusedApplicationChanged(NSWorkspace.shared.frontmostApplication?.processIdentifier)
        guard let anchor = paneRangeChord.anchor else { return }
        let focused = native.frontmostWindowIdentity()
        ShortcutTrace.record("poll-window", ["expectedWindowID": anchor.context.window.id,
            "windowID": focused?.id as Any? ?? NSNull(), "pid": focused?.pid as Any? ?? NSNull()])
        guard let focused, focused.id == anchor.context.window.id,
              focused.pid == anchor.context.window.pid else { paneRangeChord.reset(reason: "poll-window"); return }
        guard let desktop = store.desktops.first(where: { $0.id == anchor.context.desktopID && $0.isCurrent && !$0.isFullScreen }),
              let screen = NSScreen.screens.first(where: { screenUUID($0) == desktop.display }),
              desktop.spaceID == anchor.context.spaceID,
              PaneGeometry(area: screenArea(screen), configuration: paneConfiguration(for: desktop.id),
                           pixelScale: screen.backingScaleFactor) == anchor.context.geometry else {
            paneRangeChord.reset(reason: "poll-desktop-geometry"); return
        }
    }
}
