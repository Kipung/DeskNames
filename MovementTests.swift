import AppKit

@MainActor func runMovementTests() {
    let areas = [CGRect(x: -1920, y: 25, width: 1920, height: 1055), CGRect(x: 0, y: 30, width: 5120, height: 1375),
                 CGRect(x: 1600, y: -900, width: 1512, height: 945), CGRect(x: 0, y: 0, width: 1080, height: 1920)]
    for area in areas {
        for scale in [1.0, 2.0] {
            for action in WindowAction.allCases {
                guard let partition = action.partition else { continue }
                for gap in [0.0, 12.0, 32.0] {
                    let config = PaneConfiguration(preset: partition.preset, gap: gap)
                    let panes = PaneGeometry(area: area, configuration: config, pixelScale: scale)
                    let shortcut = action.frame(in: area, current: area, configuration: config, pixelScale: scale)
                    precondition(shortcut == panes.cells[partition.index], "Shortcuts and Command-drag must use exactly the same pixels")
                    for rect in panes.cells {
                        for edge in [rect.minX, rect.maxX, rect.minY, rect.maxY] { precondition(abs(edge*scale-(edge*scale).rounded()) < 0.001) }
                    }
                }
            }
        }
    }
    let workArea = CGRect(x: 0, y: 31, width: 5120, height: 1409)
    let frameCases = [
        (CGRect(x: 692, y: 104, width: 603, height: 505), CGRect(x: 0, y: 31, width: 1707, height: 1409)),
        (CGRect(x: 0, y: 31, width: 1707, height: 1409), CGRect(x: 3840, y: 31, width: 1280, height: 1409)),
        (CGRect(x: 0, y: 31, width: 2560, height: 704), CGRect(x: 3840, y: 31, width: 1280, height: 1409))
    ]
    for (start, target) in frameCases {
        var actual = start
        for step in AccessibilityWindowWrite.frameSteps(to: target, from: start) {
            switch step {
            case .size(let size): actual.size = CGSize(width: min(size.width, workArea.maxX-actual.minX), height: min(size.height, workArea.maxY-actual.minY))
            case .position(let point): actual.origin = CGPoint(x: min(point.x, workArea.maxX-actual.width), y: min(point.y, workArea.maxY-actual.height))
            default: preconditionFailure("Unexpected frame operation")
            }
        }
        precondition(actual == target, "Window bounds must not be clipped at the old location before moving")
    }
    let custom = PaneConfiguration(preset: .thirds, gap: 12, splitPositions: ["x1": 0.3, "x2": 0.7])
    let grid = PaneGeometry(area: areas[0], configuration: custom)
    precondition(WindowAction.middleThird.frame(in: areas[0], current: areas[0], configuration: custom) == grid.cells[1])
    for hz in [60.0, 120, 144, 240] {
        let interval = 1/hz
        for elapsed in [0.001, 0.009, 0.045, 0.18] {
            let delay = WindowTransition.delay(now: elapsed, started: 0, interval: interval)
            precondition(delay >= 0 && delay <= interval+0.000001, "Rendering work must not add a whole fixed delay")
        }
    }
    precondition(WindowTransition.shouldFinishDirectly(writeDuration: 0.032, frameInterval: 1.0/144))
    precondition(!WindowTransition.shouldFinishDirectly(writeDuration: 0.004, frameInterval: 1.0/144))
    let small = CGRect(x: 100, y: 100, width: 400, height: 400)
    precondition(WindowTransition.duration(from: small, to: small.offsetBy(dx: 10, dy: 0), in: areas[1]) < WindowTransition.duration(from: small, to: areas[1], in: areas[1]))
    print("PASS: shortcut/drag pixel agreement across landscape, portrait, Retina and translated displays; custom dividers; display-paced deadlines and distance-sensitive duration")
}

@MainActor func runMovementSessionTests() async throws {
    guard let screen = NSScreen.screens.first else { throw WindowIssue("A display is required.") }
    let domain = "local.desknames.movement.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: domain)!
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("movement-\(UUID().uuidString).json")
    defer { defaults.removePersistentDomain(forName: domain); try? FileManager.default.removeItem(at: file) }
    let native = NativeWindows(trustCheck: { true }, includeExternal: false)
    let store = Store(defaults: defaults), workspace: LayoutController
    workspace = LayoutController(store: store, file: file, native: native)
    var ran: [Int] = []
    workspace.run(interruptible: true) { ran.append(0); try await Task.sleep(nanoseconds: 500_000_000); return "old" }
    await NativeWindows.pause(0.02)
    let original = workspace.operationTask
    workspace.run(interruptible: true) { ran.append(1); return "obsolete" }
    workspace.run(interruptible: true) { ran.append(2); return "latest" }
    await original?.value
    await workspace.operationTask?.value
    precondition(ran == [0, 2] && !workspace.busy && workspace.message == "latest", "Only the newest queued placement can run")
    ran = []
    workspace.run(interruptible: true) { ran.append(0); try await Task.sleep(nanoseconds: 500_000_000); return "old" }
    await NativeWindows.pause(0.02)
    workspace.run(interruptible: true) { ran.append(1); return "must not run" }
    workspace.cancel()
    await workspace.operationTask?.value
    precondition(ran == [0] && !workspace.busy, "Explicit cancellation clears pending placements")
    let area = screenArea(screen), top = NSScreen.screens.first?.frame.maxY ?? 0
    let a = NSWindow(contentRect: CGRect(x: area.minX+30, y: top-area.maxY+30, width: 300, height: 250), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    let b = NSWindow(contentRect: CGRect(x: area.minX+380, y: top-area.maxY+30, width: 300, height: 250), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    for w in [a,b] { w.isReleasedWhenClosed = false; w.title = "DeskNames motion fixture"; w.orderFrontRegardless() }
    defer { a.close(); b.close() }
    await NativeWindows.pause(0.15)
    guard let wa = native.localSnapshot(a), let wb = native.localSnapshot(b),
          let desktop = store.desktops.first(where: { $0.isCurrent && !$0.isFullScreen && $0.display == screenUUID(screen) }) else { throw WindowIssue("Fixture windows are unavailable.") }
    workspace.panes.set(PaneConfiguration(preset: .thirds, gap: 12), for: desktop.id)
    try await SmartPaneController(workspace: workspace).verifyUnrelatedClickForTesting()
    try await SmartPaneController(workspace: workspace).verifyOverlayGeometryForTesting()
    try await SmartPaneController(workspace: workspace).verifyLatestDropTargetForTesting(window: wa)
    workspace.refresh(); workspace.selectedWindow = wa.id
    workspace.performWindowAction(.right)
    await NativeWindows.pause(0.04)
    let firstMove = workspace.operationTask
    workspace.performWindowAction(.left)
    await firstMove?.value; await workspace.operationTask?.value
    let left = WindowAction.left.frame(in: area, current: wa.frame, configuration: PaneConfiguration())!
    precondition(native.verifyFrame(left, window: wa) && !workspace.busy)
    precondition(workspace.frameHistory.previous(wa, screen: screen) == wa.frame, "Retargeting must retain the pre-animation restore frame")
    workspace.selectedWindow = wb.id; workspace.performWindowAction(.right); await workspace.operationTask?.value
    workspace.panes.setLinkedResizing(true)
    let linked = LinkedPaneController(workspace: workspace)
    defer { linked.stop() }
    linked.tick()
    let handles = linked.handleWindowNumbersForTesting
    precondition(!handles.isEmpty, "Shortcut halves must have a shared handle even with Three columns selected")
    await NativeWindows.pause(1.05); linked.tick()
    precondition(linked.handleWindowNumbersForTesting == handles, "Idle refresh must reuse divider windows")
    let resized = await linked.resizeForTesting(dividerID: "x1", to: area.midX+min(60, area.width/20))
    precondition(resized && workspace.paneConfiguration(for: desktop.id).preset == .thirds, "Resizing detected neighbors must not replace the chosen guide layout")
    guard let af = native.actualFrame(wa), let bf = native.actualFrame(wb) else { throw WindowIssue("Fixture closed.") }
    precondition(abs(bf.minX-af.maxX-12) <= 1/screen.backingScaleFactor && af.width > left.width)
    print("PASS: latest placement replaces old requests, explicit cancellation clears the queue, interrupted snaps preserve restore history, shortcut neighbors resize together with stable handles")
    print("DISPLAY: \(Int(area.width))×\(Int(area.height)) usable points, scale \(screen.backingScaleFactor), maximum refresh \(screen.maximumFramesPerSecond) Hz")
}
