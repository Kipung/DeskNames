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
    private(set) var anchor: Anchor?

    mutating func reset() { anchor = nil }

    mutating func modifiersChanged(_ modifiers: UInt32) {
        if anchor?.modifiers != modifiers { reset() }
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
        guard paneRangeChord.anchor != nil else { return }
        paneRangeChord.modifiersChanged(ShortcutBinding.carbonModifiers(NSEvent.modifierFlags))
        guard paneRangeChord.anchor != nil else { return }
        guard let window = native.focusedWindow(), let screen = screenFor(window.frame),
              let desktop = native.activeDesktop(reader: store.reader), screenUUID(screen) == desktop.display else {
            paneRangeChord.reset(); return
        }
        paneRangeChord.observe(paneRangeContext(window: window, desktop: desktop, screen: screen))
    }
}
