import AppKit

func runPaneHandleVisibilityTests() {
    typealias Window = PaneHandleCover.Window
    let handle = CGRect(x: 954, y: 500, width: 12, height: 80)
    let left = Window(id: 1, frame: CGRect(x: 0, y: 40, width: 960, height: 1040))
    let right = Window(id: 2, frame: CGRect(x: 960, y: 40, width: 960, height: 1040))
    let panes = [left.id: left.frame, right.id: right.frame]
    let cover = Window(id: 3, frame: CGRect(x: 200, y: 60, width: 1500, height: 1000))
    let elsewhere = Window(id: 4, frame: CGRect(x: 0, y: 40, width: 300, height: 300))
    let sliver = Window(id: 5, frame: CGRect(x: handle.maxX-0.5, y: handle.minY, width: 100, height: 80))
    let edge = Window(id: 6, frame: CGRect(x: handle.maxX, y: handle.minY, width: 100, height: 80))
    let ownHandle = Window(id: 7, frame: handle)
    let cases: [(String, [Window], UInt32?)] = [
        ("uncovered panes", [left, right], 1),
        ("reordered panes", [right, left], 2),
        ("cover above both panes", [cover, left, right], nil),
        ("cover between panes", [left, cover, right], nil),
        ("cover behind both panes", [left, right, cover], 1),
        ("distant window in front", [elsewhere, left, right], 1),
        ("half-point overlap", [sliver, left, right], nil),
        ("touching edge without overlap", [edge, left, right], 1),
        ("missing back pane", [left], nil),
        ("missing front pane", [right], nil),
        ("no panes on screen", [], nil),
        ("missing pane with unrelated window", [elsewhere, right], nil),
        ("moved pane", [Window(id: 1, frame: left.frame.offsetBy(dx: 20, dy: 0)), right], nil),
        ("resized pane", [left, Window(id: 2, frame: right.frame.insetBy(dx: 20, dy: 0))], nil),
        ("floating cover", [Window(id: 3, frame: handle, layer: 3), left, right], nil),
        ("menu-level cover", [Window(id: 3, frame: handle, layer: 24), left, right], nil),
        ("translucent cover", [Window(id: 3, frame: handle, alpha: 0.1), left, right], nil),
        ("transparent cover", [Window(id: 3, frame: handle, alpha: 0), left, right], 1),
        ("transparent pane", [Window(id: 1, frame: left.frame, alpha: 0), right], nil),
        ("elevated pane", [Window(id: 1, frame: left.frame, layer: 3), right], nil),
        ("another divider does not occlude", [ownHandle, left, right], 1),
        ("ignoring dividers still detects real cover", [ownHandle, cover, left, right], nil)
    ]
    for (name, stack, expected) in cases {
        precondition(PaneHandleCover.anchor(handle, panes: panes, frontToBack: stack, ignoring: [7]) == expected, name)
    }
    precondition(PaneHandleCover.anchor(handle, panes: [:], frontToBack: [left, right]) == nil)
    precondition(PaneHandleCover.anchor(handle, panes: [1: left.frame], frontToBack: [left, right]) == nil)
    precondition(PaneHandleCover.anchor(.zero, panes: panes, frontToBack: [left, right]) == nil)
    for reason in ["Mission Control", "full-screen Space", "inactive desktop"] {
        precondition(PaneHandleCover.anchor(handle, panes: panes, frontToBack: [left, right], available: false) == nil, reason)
    }
    let moved = Window(id: 1, frame: left.frame.offsetBy(dx: 20, dy: 0))
    precondition(PaneHandleCover.anchor(handle, panes: panes, frontToBack: [moved, right], resizing: true) == 1,
                 "Our own resize may change pane frames between observations")
    precondition(PaneHandleCover.anchor(handle, panes: panes, frontToBack: [moved], resizing: true) == nil,
                 "An active resize still requires every pane on screen")
    precondition(PaneHandleCover.anchor(handle, panes: panes, frontToBack: [cover, moved, right], resizing: true) == nil,
                 "An active resize still respects covering windows")
    precondition(PaneHandleCover.anchor(handle, panes: panes, frontToBack: [moved, right], resizing: true, available: false) == nil)
    print("PASS: linked handle ordering, occlusion, missing/moved panes, elevated covers, thin overlaps, environment and active-resize visibility")
}

@MainActor func runPaneHandleVisibilitySessionTests(controller: LinkedPaneController, workspace: LayoutController, fixtures: [NSWindow]) async throws {
    func check(_ condition: Bool, _ message: String) throws {
        guard condition else { throw WindowIssue(message) }
    }
    func panels() -> [NSWindow] {
        controller.handleWindowNumbersForTesting.compactMap { NSApp.window(withWindowNumber: $0) }
    }
    func visibleHandle(at frame: CGRect? = nil) async throws -> NSWindow {
        for _ in 0..<30 {
            controller.tick()
            if let panel = panels().first(where: { $0.isVisible && (frame == nil || $0.frame == frame) }) { return panel }
            await NativeWindows.pause(0.05)
        }
        throw WindowIssue("A visible fixture divider was not restored.")
    }
    let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
    let keyWindow = NSApp.keyWindow
    for window in fixtures { window.animationBehavior = .none }
    var handle = try await visibleHandle()
    let frame = handle.frame
    try check(panels().allSatisfy { $0.level == .normal && $0.animationBehavior == .none && !$0.canBecomeKey && !$0.canBecomeMain },
              "Handles must use nonactivating normal-level panels without visibility animations.")
    let cover = NSPanel(contentRect: frame.insetBy(dx: -10, dy: -10), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    cover.isReleasedWhenClosed = false; cover.animationBehavior = .none
    defer { cover.close() }
    for level in [NSWindow.Level.normal, .floating] {
        cover.level = level
        cover.orderFrontRegardless()
        await NativeWindows.pause(0.02)
        controller.tick()
        try check(!handle.isVisible, "An overlapping fixture must hide the handle before the next discovery scan.")
        cover.orderOut(nil)
        handle = try await visibleHandle(at: frame)
    }
    let original = fixtures.map(\.frame)
    for window in fixtures { window.setFrameOrigin(NSPoint(x: window.frame.minX+20, y: window.frame.minY)) }
    await NativeWindows.pause(0.02)
    controller.tick()
    try check(panels().allSatisfy { !$0.isVisible }, "Moving linked panes must hide stale handles.")
    for (window, frame) in zip(fixtures, original) { window.setFrame(frame, display: true) }
    handle = try await visibleHandle(at: frame)
    for window in fixtures { window.orderOut(nil) }
    await NativeWindows.pause(0.02)
    controller.tick()
    try check(panels().allSatisfy { !$0.isVisible }, "Off-screen panes must hide their handles.")
    for window in fixtures { window.orderFrontRegardless() }
    handle = try await visibleHandle(at: frame)
    let desktops = workspace.store.desktops
    defer { workspace.store.desktops = desktops; workspace.store.missionControl = false }
    workspace.store.desktops = desktops.map {
        Desktop(id: $0.id, spaceID: $0.spaceID, display: $0.display, position: $0.position, number: $0.number, isCurrent: $0.isCurrent, isFullScreen: true)
    }
    controller.tick()
    try check(panels().allSatisfy { !$0.isVisible }, "Full-screen desktop state must suppress handles.")
    workspace.store.desktops = desktops
    handle = try await visibleHandle(at: frame)
    workspace.store.missionControl = true
    controller.tick()
    try check(!handle.isVisible && panels().allSatisfy { !$0.isVisible }, "Mission Control state must suppress handles.")
    try check(NSWorkspace.shared.frontmostApplication?.processIdentifier == frontmost && NSApp.keyWindow === keyWindow,
              "Showing and hiding handles must preserve focus.")
    print("PASS: native fixture covers, immediate visibility refresh, movement, off-screen panes, simulated full-screen/Mission Control state, and unchanged focus")
}
