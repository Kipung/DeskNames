import AppKit

@MainActor private final class OperationRecoveryGate {
    private var waiting: CheckedContinuation<Void, Never>?
    private var observer: CheckedContinuation<Void, Never>?
    private var started = false

    func hold() async {
        await withCheckedContinuation { continuation in
            waiting = continuation
            started = true
            observer?.resume(); observer = nil
        }
    }
    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { observer = $0 }
    }
    func release() { waiting?.resume(); waiting = nil }
}

@MainActor func runOperationRecoveryTests() async throws {
    let domain = "local.desknames.operation-recovery.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: domain)!
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DeskNames-operation-recovery-\(UUID().uuidString)")
    defer { defaults.removePersistentDomain(forName: domain); try? FileManager.default.removeItem(at: directory) }
    let store = Store(defaults: defaults)
    let native = NativeWindows(trustCheck: { true }, includeExternal: false, diagnosticsDirectory: directory)
    let workspace = LayoutController(store: store, file: directory.appendingPathComponent("layouts.json"), native: native)
    var ran: [String] = []
    var completions: [String] = []

    workspace.run(refreshWindows: false, completion: { completions.append($0) }) {
        ran.append("cancelled-before-start")
        return "Unexpected"
    }
    let unstarted = workspace.operationTask
    workspace.cancel()
    await unstarted?.value
    precondition(ran.isEmpty && completions == ["Operation cancelled."], "Cancellation before execution must still finish owner cleanup")
    precondition(!workspace.busy && workspace.operationTask == nil)

    workspace.run(refreshWindows: false) { throw WindowIssue("Injected timeout") }
    await workspace.operationTask?.value
    precondition(workspace.message == "Injected timeout" && !workspace.busy && workspace.operationTask == nil,
                 "An AX-like failure must release admission and clear its task")

    let gate = OperationRecoveryGate()
    var shortcutResults: [String] = []
    workspace.shortcutResult = { shortcutResults.append("old: " + $0) }
    workspace.run(interruptible: true, refreshWindows: false) {
        ran.append("old")
        await gate.hold()
        return "Old write drained"
    }
    workspace.shortcutResult = nil
    await gate.waitUntilStarted()
    let original = workspace.operationTask
    workspace.run(refreshWindows: false) { preconditionFailure("A competing noninterruptible operation must be refused") }
    precondition(workspace.message.contains("in progress"))
    workspace.shortcutResult = { shortcutResults.append("replaced: " + $0) }
    workspace.run(interruptible: true, refreshWindows: false) { ran.append("replaced"); return "Unexpected" }
    precondition(workspace.message == "Working…", "An accepted queued shortcut must not inherit another request's refusal")
    workspace.shortcutResult = { shortcutResults.append("latest: " + $0) }
    workspace.run(interruptible: true, refreshWindows: false) { ran.append("latest"); return "Latest placement" }
    workspace.shortcutResult = nil
    precondition(workspace.busy && workspace.canRetargetPlacement, "Cancellation cannot release an unfinished external writer")
    workspace.run(refreshWindows: false) { ran.append("competing"); return "Unexpected" }
    precondition(workspace.message.contains("in progress"))
    gate.release()
    await original?.value
    await workspace.operationTask?.value
    precondition(ran == ["old", "latest"] && workspace.message == "Latest placement")
    precondition(shortcutResults == ["replaced: Placement replaced by a newer request.", "old: Operation cancelled.", "latest: Latest placement"],
                 "Queued placements must preserve their own diagnostic completion")
    precondition(!workspace.busy && workspace.operationTask == nil)
    print("PASS: queued shortcut publishes its own pending result after an unrelated refusal; completion remains request-owned")

    let geometry = PaneGeometry(area: CGRect(x: 0, y: 0, width: 1600, height: 900), configuration: PaneConfiguration(preset: .fourColumns))
    let context = PaneRangeChord.Context(window: .init(id: 10, pid: 20), desktopID: "fixture", spaceID: 1, displayID: "fixture", geometry: geometry)
    let discovery = OperationRecoveryGate()
    var destinations: [ClosedRange<Int>] = []
    let firstPane = workspace.paneRangeChord.request(2, modifiers: 256, pid: 20)
    workspace.run(interruptible: true, refreshWindows: false, completion: { _ in workspace.paneRangeChord.finish(firstPane, succeeded: false) }) {
        await discovery.hold()
        try Task.checkCancellation()
        destinations.append(workspace.paneRangeChord.resolve(firstPane, context: context)!)
        return "First pane"
    }
    await discovery.waitUntilStarted()
    let discovering = workspace.operationTask
    let endpoint = workspace.paneRangeChord.request(3, modifiers: 256, pid: 20)
    workspace.run(interruptible: true, refreshWindows: false) {
        destinations.append(workspace.paneRangeChord.resolve(endpoint, context: context)!)
        return "Spanning panes 3-4"
    }
    discovery.release()
    await discovering?.value
    await workspace.operationTask?.value
    precondition(destinations == [2...3] && !workspace.busy && workspace.paneRangeChord.anchor?.pane == 2,
                 "A second pane during suspended discovery retargets the queued operation without losing its first pane")
    workspace.paneRangeChord.reset()
    print("PASS: range retarget during suspended discovery preserves first pane, drains cancelled work, and releases admission")

    let cancelGate = OperationRecoveryGate()
    workspace.run(interruptible: true, refreshWindows: false) { await cancelGate.hold(); return "Cancelled writer drained" }
    await cancelGate.waitUntilStarted()
    let cancelled = workspace.operationTask
    var discarded = 0
    workspace.run(interruptible: true, refreshWindows: false, completion: { _ in discarded += 1 }) {
        preconditionFailure("Explicit cancellation must discard pending placement")
    }
    workspace.cancel()
    precondition(discarded == 1 && workspace.busy)
    cancelGate.release()
    await cancelled?.value
    precondition(!workspace.busy && workspace.operationTask == nil)

    precondition(workspace.beginUserWindowDrag())
    let fake = LiveWindow(id: 123, target: .accessibility(AXUIElementCreateApplication(getpid())), pid: getpid(),
                          bundleID: "test.window", appName: "Test", title: "", frame: CGRect(x: 0, y: 0, width: 500, height: 400),
                          spaceIDs: [100], minimized: false)
    var drops = 0
    workspace.finishUserWindowDrag(fake, frame: fake.frame, displayID: "absent", desktopID: "absent") { _, success in
        precondition(!success)
        drops += 1
    }
    let drop = workspace.operationTask
    workspace.cancel()
    await drop?.value
    precondition(drops == 1 && !workspace.busy && workspace.operationTask == nil,
                 "An unstarted cancelled drop must clear its owner's placement state exactly once")
    precondition(workspace.beginUserWindowDrag())
    workspace.cancel(); workspace.endUserWindowDrag()
    precondition(!workspace.busy, "Repeated drag cancellation must release admission")

    let automaticGate = OperationRecoveryGate()
    let desktops = (1...2).map { Desktop(id: "fixture-\($0)", spaceID: UInt64($0), display: "fixture-\($0)", position: 0, number: $0,
                                       isCurrent: true, isFullScreen: false) }
    var restored: [String] = []
    workspace.shortcutResult = { _ in preconditionFailure("Automatic restores must not inherit a shortcut result") }
    workspace.runAutomaticRestores(desktops) { desktop in
        restored.append(desktop.id)
        await automaticGate.hold()
        return "Automatic writer drained"
    }
    workspace.shortcutResult = nil
    await automaticGate.waitUntilStarted()
    let automatic = workspace.operationTask
    workspace.cancel()
    precondition(workspace.busy)
    automaticGate.release()
    await automatic?.value
    precondition(restored == [desktops[0].id] && !workspace.busy && workspace.operationTask == nil,
                 "Cancelling automatic restore must stop the desktop batch and release the same writer as manual commands")

    let cancelledRestore = Task { @MainActor in
        try await workspace.restoreLayout(Desktop(id: "fixture", spaceID: 0, display: "fixture", position: 0, number: 1,
                                                 isCurrent: true, isFullScreen: false), automatic: true)
    }
    cancelledRestore.cancel()
    do { _ = try await cancelledRestore.value; preconditionFailure("Cancelled restore must stop before discovery or app launch") }
    catch is CancellationError {}
    workspace.run(refreshWindows: false) { "Recovered" }
    await workspace.operationTask?.value
    precondition(workspace.message == "Recovered" && !workspace.busy && workspace.operationTask == nil)
    workspace.restore()
    precondition(workspace.message == "Save a layout for this desktop before restoring windows.")
    print("PASS: cancelled-before-start cleanup; timeout recovery; writer ownership until drained; newest placement and diagnostic ownership; queued cancellation; cancelled drop completion; drag release; cancelled restore preflight; subsequent command admission")
}
