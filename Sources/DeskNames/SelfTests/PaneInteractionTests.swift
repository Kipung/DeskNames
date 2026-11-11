import AppKit

@MainActor func runPaneInteractionTests() throws {
    // Divider handles hide behind windows that cover them, but not behind their own panes or windows further back.
    let handle = CGRect(x: 954, y: 500, width: 12, height: 80)
    let left = (id: UInt32(1), frame: CGRect(x: 0, y: 40, width: 960, height: 1040))
    let right = (id: UInt32(2), frame: CGRect(x: 960, y: 40, width: 960, height: 1040))
    let cover = (id: UInt32(3), frame: CGRect(x: 200, y: 60, width: 1500, height: 1000))
    let elsewhere = (id: UInt32(4), frame: CGRect(x: 0, y: 40, width: 300, height: 300))
    precondition(!PaneHandleCover.hidden(handle, panes: [1, 2], frontToBack: [left, right]))
    precondition(PaneHandleCover.hidden(handle, panes: [1, 2], frontToBack: [cover, left, right]), "A window in front of both panes hides the handle")
    precondition(PaneHandleCover.hidden(handle, panes: [1, 2], frontToBack: [left, cover, right]), "A window in front of one pane still hides the handle")
    precondition(!PaneHandleCover.hidden(handle, panes: [1, 2], frontToBack: [left, right, cover]), "Windows behind both panes do not matter")
    precondition(!PaneHandleCover.hidden(handle, panes: [1, 2], frontToBack: [elsewhere, left, right]), "Windows away from the handle do not matter")
    let area = CGRect(x: -1920, y: 40, width: 1920, height: 1040)
    let config = PaneConfiguration(preset: .fourColumns, gap: 12)
    let geometry = PaneGeometry(area: area, configuration: config)
    precondition(geometry.cells.count == 4 && Set(geometry.cells.map(\.width)).count == 1)
    let middle = PaneDivider.all(for: .fourColumns)[1]
    let resized = middle.moved(to: area.midX + 100, in: area, configuration: config)
    let cells = PaneGeometry(area: area, configuration: resized).cells
    precondition(cells[0] == geometry.cells[0] && cells[3] == geometry.cells[3])
    precondition(cells[1].width > geometry.cells[1].width && cells[2].width < geometry.cells[2].width)
    precondition(abs(cells[2].minX-cells[1].maxX-config.gap) < 0.001)
    for preset in PanePreset.allCases {
        for divider in PaneDivider.all(for: preset) {
            for coordinate in [-100000.0, -800.0, 100000.0] {
                let changed = divider.moved(to: coordinate, in: area, configuration: PaneConfiguration(preset: preset))
                let grid = PaneGeometry(area: area, configuration: changed)
                precondition(grid.cells.count == preset.regions.count)
                for (i, cell) in grid.cells.enumerated() {
                    precondition(area.contains(cell))
                    for other in grid.cells.dropFirst(i+1) { precondition(!cell.intersects(other)) }
                }
            }
        }
    }
    let legacy = try JSONDecoder().decode(PaneConfiguration.self, from: Data(#"{"preset":"thirds","gap":12}"#.utf8))
    precondition(legacy.splitPositions == nil && legacy.preset == .thirds)
    let decoded = try JSONDecoder().decode(PaneConfiguration.self, from: JSONEncoder().encode(resized))
    precondition(decoded == resized)
    var corrupt = config
    corrupt.splitPositions = ["x1": 0.44, "x2": 0.3]
    precondition(corrupt.sanitized.splitPositions == nil)
    precondition(PaneShortcut.preset(for: PaneShortcut.next, current: .focus) == .halves)
    precondition(PaneShortcut.preset(for: PaneShortcut.previous, current: .halves) == .focus)
    precondition(PaneShortcut.preset(for: 312, current: .halves) == .fourColumns)
    let start = CGRect(x: 10, y: 20, width: 400, height: 300), end = CGRect(x: 600, y: 60, width: 600, height: 800)
    precondition(WindowTransition.frame(from: start, to: end, progress: 0) == start)
    precondition(WindowTransition.frame(from: start, to: end, progress: 1) == end)
    let domain = "local.desknames.paneinteraction.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: domain)!
    defer { defaults.removePersistentDomain(forName: domain) }
    let preferences = PanePreferences(defaults: defaults)
    precondition(!preferences.linkedResizing)
    preferences.setLinkedResizing(true); preferences.set(resized, for: "test")
    precondition(PanePreferences(defaults: defaults).configuration(for: "test") == resized)
    precondition(PanePreferences(defaults: defaults).linkedResizing)
    let shortcuts = ShortcutSettings(defaults: defaults)
    precondition(ShortcutSettings.validation(shortcuts.bindings) == nil)
    let retained = shortcuts.bindings[100]
    for action in PaneShortcut.all { shortcuts.set(nil, for: action.id) }
    let loaded = ShortcutSettings(defaults: defaults)
    precondition(PaneShortcut.all.allSatisfy { loaded.bindings[$0.id] == nil })
    loaded.addPaneSuggestions()
    precondition(loaded.bindings[100] == retained && ShortcutSettings.validation(loaded.bindings) == nil)
    print("PASS: four columns, shared-divider geometry, clamping, legacy settings, saved widths, shortcut cycling, opt-in bindings, transition endpoints")
}

@MainActor func runPaneInteractionSessionTests() async throws {
    guard let screen = NSScreen.screens.first else { throw WindowIssue("A display is required.") }
    let native = NativeWindows(trustCheck: { true }, includeExternal: false)
    let area = screenArea(screen), top = NSScreen.screens.first?.frame.maxY ?? 0
    var fixtures: [NSWindow] = []
    defer { for window in fixtures { window.close() } }
    for i in 0..<4 {
        let window = NSWindow(contentRect: CGRect(x: area.minX+CGFloat(i)*40, y: top-area.maxY+60, width: 300, height: 220), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.title = "DeskNames pane fixture \(i+1)"; window.isReleasedWhenClosed = false
        window.orderFrontRegardless(); fixtures.append(window)
    }
    var windows: [LiveWindow] = []
    for _ in 0..<20 {
        windows = fixtures.compactMap { native.localSnapshot($0) }
        if windows.count == 4 { break }
        await NativeWindows.pause(0.05)
    }
    precondition(windows.count == 4, "WindowServer must publish the four fixture windows")
    let config = PaneConfiguration(preset: .fourColumns, gap: 12)
    let initial = PaneGeometry(area: area, configuration: config)
    try await native.animateFrames(Array(zip(windows, initial.cells)))
    precondition(zip(windows, initial.cells).allSatisfy { native.verifyFrame($0.1, window: $0.0) })
    let changed = PaneDivider.all(for: .fourColumns)[1].moved(to: area.midX+min(80, area.width/20), in: area, configuration: config)
    let resized = PaneGeometry(area: area, configuration: changed)
    try await native.animateFrames(Array(zip(windows, resized.cells)))
    precondition(zip(windows, resized.cells).allSatisfy { native.verifyFrame($0.1, window: $0.0) })
    let task = Task { @MainActor in try await native.animateFrames(Array(zip(windows, initial.cells)), duration: 1) }
    await NativeWindows.pause(0.05); task.cancel()
    do { try await task.value; preconditionFailure("Cancelled transition should throw") } catch is CancellationError { }
    let stopped = windows.map { native.actualFrame($0) }
    await NativeWindows.pause(0.1)
    precondition(windows.map { native.actualFrame($0) } == stopped)
    try await native.animateFrames(Array(zip(windows, initial.cells)))
    let domain = "local.desknames.linked-session.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: domain)!
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("linked-pane-\(UUID().uuidString).json")
    defer { defaults.removePersistentDomain(forName: domain); try? FileManager.default.removeItem(at: file) }
    let store = Store(defaults: defaults)
    guard let desktop = store.desktops.first(where: { $0.isCurrent && $0.display == screenUUID(screen) && !$0.isFullScreen }) else { throw WindowIssue("An ordinary desktop is required.") }
    let workspace = LayoutController(store: store, file: file, native: native)
    workspace.panes.set(config, for: desktop.id); workspace.panes.setLinkedResizing(true)
    let controller = LinkedPaneController(workspace: workspace)
    defer { controller.stop() }
    let linked = await controller.resizeForTesting(dividerID: "x2", to: area.midX + min(80, area.width/20))
    precondition(linked && !workspace.busy, "The native linked-resize transaction must complete and release admission")
    precondition(zip(windows, resized.cells).allSatisfy { native.verifyFrame($0.1, window: $0.0) })
    let previous = workspace.paneConfiguration(for: desktop.id)
    fixtures[1].contentMinSize = NSSize(width: resized.cells[1].width-10, height: 100)
    let constrained = await controller.resizeForTesting(dividerID: "x2", to: area.midX - min(80, area.width/20))
    precondition(!constrained && workspace.paneConfiguration(for: desktop.id) == previous && !workspace.busy)
    precondition(zip(windows, resized.cells).allSatisfy { native.verifyFrame($0.1, window: $0.0) }, "A constrained neighbor must roll back both windows")
    print("PASS: four native windows animate into columns; cancellation has no delayed writes; linked resizing persists geometry, releases admission, and rolls back constrained neighbors")
}
