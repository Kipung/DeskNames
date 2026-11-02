import AppKit

@MainActor func runPaneTests() {
    let areas = [CGRect(x: 0, y: 25, width: 1440, height: 875), CGRect(x: -1920, y: -1055, width: 1920, height: 1055),
                 CGRect(x: 0, y: 25, width: 5120, height: 1375), CGRect(x: 1920, y: 1080, width: 1280, height: 720)]
    for area in areas {
        for preset in PanePreset.allCases {
            for gap in [0.0, 12, 32] {
                let grid = PaneGeometry(area: area, configuration: PaneConfiguration(preset: preset, gap: gap))
                precondition(grid.cells.count == preset.regions.count)
                for (i, cell) in grid.cells.enumerated() {
                    precondition(area.contains(cell) && cell.width > 0 && cell.height > 0)
                    precondition(grid.hit(CGPoint(x: cell.midX, y: cell.midY)) == i)
                    for other in grid.cells.dropFirst(i+1) { precondition(!cell.intersects(other)) }
                }
                if gap > 0 { precondition(grid.hit(area.origin) == nil) }
            }
        }
    }
    let halves = PaneGeometry(area: CGRect(x: -1200, y: 100, width: 1200, height: 800), configuration: PaneConfiguration(preset: .halves, gap: 12))
    precondition(halves.cells[0] == CGRect(x: -1188, y: 112, width: 582, height: 776))
    precondition(halves.cells[1] == CGRect(x: -594, y: 112, width: 582, height: 776))
    precondition(halves.hit(CGPoint(x: -600, y: 500)) == nil, "The gap must not be a drop target")
    precondition(PaneGeometry(area: .zero, configuration: PaneConfiguration()).cells.isEmpty)
    precondition(PaneGeometry(area: CGRect(x: 0, y: 0, width: 4, height: 4), configuration: PaneConfiguration()).cells.isEmpty)
    let wide = PaneGeometry(area: CGRect(x: 0, y: 0, width: 1200, height: 800), configuration: PaneConfiguration(preset: .wideLeft, gap: 0))
    precondition(wide.cells == [CGRect(x: 0, y: 0, width: 800, height: 800), CGRect(x: 800, y: 0, width: 400, height: 400), CGRect(x: 800, y: 400, width: 400, height: 400)])

    var sampleTick = 0
    func sampleTime() -> TimeInterval { sampleTick += 1; return Double(sampleTick)/30 }
    let initial = CGRect(x: 100, y: 100, width: 600, height: 400)
    let start = CGPoint(x: 350, y: 115)
    var selection = PaneMoveEvidence(initialFrame: initial, initialPointer: start, time: sampleTime())
    for _ in 0..<4 { selection.observe(frame: initial, pointer: CGPoint(x: 600, y: 500), time: sampleTime()) }
    precondition(!selection.moved, "Dragging content without moving its window cannot arm snapping")
    var unrelated = PaneMoveEvidence(initialFrame: initial, initialPointer: start, time: sampleTime())
    for _ in 0..<4 { unrelated.observe(frame: initial.offsetBy(dx: 300, dy: 0), pointer: start, time: sampleTime()) }
    precondition(!unrelated.moved, "A programmatic window move without pointer movement cannot arm snapping")
    var move = PaneMoveEvidence(initialFrame: initial, initialPointer: start, time: sampleTime())
    move.observe(frame: initial.offsetBy(dx: 70, dy: 40), pointer: CGPoint(x: 420, y: 155), time: sampleTime())
    precondition(!move.moved, "One observation cannot prove a move")
    move.observe(frame: initial.offsetBy(dx: 70, dy: 40), pointer: CGPoint(x: 420, y: 155), time: sampleTime())
    precondition(!move.moved, "Repeated reads of the same displacement are not two movements")
    move.observe(frame: initial.offsetBy(dx: 100, dy: 80), pointer: CGPoint(x: 450, y: 195), time: sampleTime())
    precondition(move.moved, "A real move works without requiring an AXTitleBar role")
    move.observe(frame: CGRect(x: 200, y: 180, width: 610, height: 400), pointer: CGPoint(x: 450, y: 195), time: sampleTime())
    precondition(!move.moved && move.confirmations == 0, "Resizing clears all prior movement evidence")
    move.observe(frame: initial.offsetBy(dx: 100, dy: 80), pointer: CGPoint(x: 450, y: 195), time: sampleTime())
    precondition(!move.moved, "Another resize must not count as a translation")
    var opposite = PaneMoveEvidence(initialFrame: initial, initialPointer: start, time: sampleTime())
    opposite.observe(frame: initial.offsetBy(dx: 8, dy: 0), pointer: CGPoint(x: 342, y: 115), time: sampleTime())
    opposite.observe(frame: initial.offsetBy(dx: 9, dy: 0), pointer: CGPoint(x: 341, y: 115), time: sampleTime())
    precondition(!opposite.moved, "Small opposite-direction movements cannot qualify")
    var untiling = PaneMoveEvidence(initialFrame: initial, initialPointer: start, time: sampleTime())
    let expanded = CGRect(x: 200, y: 140, width: 1000, height: 700)
    untiling.observe(frame: expanded, pointer: CGPoint(x: 450, y: 155), time: sampleTime())
    precondition(!untiling.moved)
    untiling.observe(frame: expanded.offsetBy(dx: 30, dy: 10), pointer: CGPoint(x: 480, y: 165), time: sampleTime())
    untiling.observe(frame: expanded.offsetBy(dx: 60, dy: 20), pointer: CGPoint(x: 510, y: 175), time: sampleTime())
    precondition(untiling.moved, "A previously tiled window can expand, then prove two translations at its new size")
    var resizing = PaneMoveEvidence(initialFrame: initial, initialPointer: start, time: sampleTime())
    for i in 1...8 {
        let frame = CGRect(x: 100 + i*10, y: 100 + i*10, width: 600 - i*10, height: 400 - i*10)
        let pointer = CGPoint(x: 350 + i*10, y: 115 + i*10)
        resizing.observe(frame: frame, pointer: pointer, time: sampleTime())
        resizing.observe(frame: frame, pointer: pointer, time: sampleTime())
        precondition(!resizing.moved, "A corner resize, including paused or duplicated samples, is not a window move")
    }

    var fast = PaneMoveEvidence(initialFrame: CGRect(x: 12, y: 42, width: 3393, height: 1386),
                                initialPointer: CGPoint(x: 1836.109375, y: 47.7578125), time: 32509.084302083334)
    let recordedDrag: [(Double, Double, Double, Double, Double)] = [
        (32509.126419958335, 12, 42, 1836.109375, 47.7578125),
        (32509.168991500002, 12, 42, 1836.921875, 47.7578125),
        (32509.192252583336, 21, 43, 1892.3125, 58.23046875),
        (32509.241270916667, 91, 54, 1990.95703125, 75.1796875),
        (32509.28622275, 291, 75, 2248.95703125, 120.984375),
        (32509.33108204167, 599, 143, 2553.0078125, 157.47265625),
        (32509.374670125002, 879, 165, 2850.8515625, 166.06640625),
        (32509.418691958334, 1137, 167, 3090.83203125, 166.06640625)
    ]
    for (index, row) in recordedDrag.enumerated() {
        fast.observe(frame: CGRect(x: row.1, y: row.2, width: 3393, height: 1386), pointer: CGPoint(x: row.3, y: row.4), time: row.0)
        if index == 3 { precondition(fast.moved, "The recorded fast Arc drag must show panes despite delayed WindowServer bounds") }
    }
    precondition(fast.moved)
    var stale = PaneMoveEvidence(initialFrame: initial, initialPointer: start, time: 0)
    stale.observe(frame: initial, pointer: CGPoint(x: 470, y: 115), time: 0.03)
    stale.observe(frame: initial.offsetBy(dx: 60, dy: 0), pointer: CGPoint(x: 470, y: 115), time: 0.5)
    stale.observe(frame: initial.offsetBy(dx: 120, dy: 0), pointer: CGPoint(x: 470, y: 115), time: 0.6)
    precondition(!stale.moved, "A later programmatic move cannot reuse an expired pointer trajectory")
    var differentSpeed = PaneMoveEvidence(initialFrame: initial, initialPointer: start, time: 0)
    differentSpeed.observe(frame: initial.offsetBy(dx: 6, dy: 0), pointer: CGPoint(x: 850, y: 115), time: 0.05)
    differentSpeed.observe(frame: initial.offsetBy(dx: 12, dy: 0), pointer: CGPoint(x: 1350, y: 115), time: 0.1)
    precondition(!differentSpeed.moved, "An unrelated slow window nudge cannot match a fast content selection")

    let domain = "local.desknames.panes.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: domain)!
    defer { defaults.removePersistentDomain(forName: domain) }
    let settings = PanePreferences(defaults: defaults)
    settings.set(PaneConfiguration(preset: .wideLeft, gap: 300), for: "stable-desktop-uuid")
    settings.setEnabled(false)
    let loaded = PanePreferences(defaults: defaults)
    precondition(loaded.configuration(for: "stable-desktop-uuid") == PaneConfiguration(preset: .wideLeft, gap: 32))
    precondition(loaded.configuration(for: "another-uuid") == PaneConfiguration() && !loaded.enabled)
    loaded.set(PaneConfiguration(preset: .thirds, gap: .nan), for: "stable-desktop-uuid")
    precondition(loaded.configuration(for: "stable-desktop-uuid").gap == 12)
    defaults.set(Data("invalid".utf8), forKey: "smartPanes.v1")
    precondition(PanePreferences(defaults: defaults).configuration(for: "stable-desktop-uuid") == PaneConfiguration())
    print("PASS: 72 pane layouts across translated screens; non-overlap, hit/gap targets, asymmetric panes, invalid geometry; recorded fast drag with delayed bounds; selection, resize, opposite motion, stale trajectory and unrelated-speed rejection; UUID preference persistence and clamping")
}

@MainActor func runPaneSessionTests() async {
    let editor = NSWindow(contentRect: CGRect(x: -1200, y: 200, width: 1020, height: 820),
                          styleMask: [.titled, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
    editor.isReleasedWhenClosed = false
    defer { editor.close() }
    let top = NSScreen.screens.first?.frame.maxY ?? 0
    let titlebar = CGPoint(x: editor.frame.midX, y: top - editor.frame.maxY + 8)
    let content = editor.convertPoint(toScreen: CGPoint(x: editor.contentLayoutRect.midX, y: editor.contentLayoutRect.midY))
    precondition(NativeWindows.isLocalTitlebarPoint(titlebar, in: editor), "The native title bar can begin an editor drag")
    precondition(!NativeWindows.isLocalTitlebarPoint(CGPoint(x: content.x, y: top - content.y), in: editor),
                 "Clicking editor controls must not reserve window-movement admission")
    precondition(!NativeWindows.isLocalTitlebarPoint(CGPoint(x: editor.frame.minX - 10, y: titlebar.y), in: editor))
    let domain = "local.desknames.panes.session.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: domain)!
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("DeskNames-pane-tests-\(UUID().uuidString).json")
    defer { defaults.removePersistentDomain(forName: domain); try? FileManager.default.removeItem(at: file) }
    let store = Store(defaults: defaults)
    let workspace = LayoutController(store: store, file: file, native: NativeWindows(trustCheck: { true }))
    let denied = LayoutController(store: store, file: file, native: NativeWindows(trustCheck: { false }))
    precondition(!denied.beginUserWindowDrag() && !denied.busy)
    workspace.pending = Task { await NativeWindows.pause(10) }
    precondition(workspace.beginUserWindowDrag() && workspace.busy && workspace.hasUserWindowDrag)
    precondition(workspace.pending?.isCancelled == true, "Starting a user drag cancels a pending automatic restore")
    var executed = 0
    workspace.run { executed += 1; return "Unexpected" }
    await NativeWindows.pause(0.02)
    precondition(executed == 0 && !workspace.beginUserWindowDrag(), "Manual placement cannot overlap a drag")
    let desktop = Desktop(id: "test-stable-uuid", spaceID: 100, display: "Main", position: 0, number: 1, isCurrent: true, isFullScreen: false)
    store.desktops = [desktop]
    workspace.lastActive = []
    workspace.layouts[desktop.id] = DesktopLayout(id: desktop.id, savedAt: Date(), windows: [], autoRestore: true)
    workspace.tick()
    precondition(workspace.hasUserWindowDrag && workspace.pending?.isCancelled == true,
                 "An entered desktop cannot start automatic restore while a user drag owns admission")
    let fake = LiveWindow(id: 123, target: .accessibility(AXUIElementCreateApplication(getpid())), pid: getpid(), bundleID: "test.window", appName: "Test", title: "", frame: CGRect(x: 0, y: 0, width: 500, height: 400), spaceIDs: [100], minimized: false)
    var completions = 0
    workspace.finishUserWindowDrag(fake, frame: fake.frame, displayID: "absent-display", desktopID: desktop.id) { _, success in
        precondition(!success)
        completions += 1
    }
    precondition(workspace.busy && !workspace.hasUserWindowDrag && !workspace.beginUserWindowDrag(),
                 "Drop hands admission directly to placement and rejects a second drag")
    workspace.cancel()
    await workspace.operationTask?.value
    precondition(completions == 1 && !workspace.busy, "Cancel in the initial delay must complete exactly once and release admission")
    workspace.run { executed += 1; return "Subsequent operation completed" }
    await workspace.operationTask?.value
    precondition(executed == 1 && !workspace.busy, "A cancelled drop must not block or cancel the next operation")
    precondition(workspace.beginUserWindowDrag())
    workspace.endUserWindowDrag(); workspace.endUserWindowDrag()
    precondition(!workspace.busy, "Repeated cancellation is harmless")
    print("PASS: native editor title-bar versus controls hit testing; permission refusal; pending/entered-desktop restore suppression; competing write refusal; atomic drop handoff; early cancellation completes once; subsequent operations recover")
}
