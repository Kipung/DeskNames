import AppKit

@MainActor func runAccessibilityRecoveryTests() async {
    let budget = AccessibilityReadBudget(now: 10)
    precondition(budget.permitsRead(now: 10.9, cancelled: false))
    precondition(!budget.permitsRead(now: 11, cancelled: false), "An unresponsive app cannot monopolize window discovery")
    precondition(!budget.permitsRead(now: 10, cancelled: true), "Cancellation stops reading additional window identities")
    let focus = FocusedWindowRequest(pid: 10)
    precondition(focus.accepts(currentPID: 10, trusted: true, cancelled: false))
    precondition(!focus.accepts(currentPID: 11, trusted: true, cancelled: false), "A delayed focus result cannot act on the app left behind")
    precondition(!focus.accepts(currentPID: nil, trusted: true, cancelled: false))
    precondition(!focus.accepts(currentPID: 10, trusted: false, cancelled: false))
    precondition(!focus.accepts(currentPID: 10, trusted: true, cancelled: true))
    var census = AccessibilityCensusStatus()
    for error in [AXError.success, .attributeUnsupported, .noValue, .invalidUIElement] { census.observe(error) }
    precondition(census.complete, "Unsupported optional attributes and closed windows do not make a census incomplete")
    census.observe(.cannotComplete)
    census.observe(.success)
    precondition(!census.complete, "An app or window timeout must prevent a partial census from replacing a saved layout")
    do { _ = try WindowCensus(windows: [], complete: false).forLayout(); preconditionFailure("Partial discovery must refuse layout capture and matching") }
    catch is WindowIssue {} catch { preconditionFailure("Unexpected discovery error") }
    let stale = Desktop(id: "original", spaceID: 1, display: "test", position: 0, number: 1, isCurrent: true, isFullScreen: false)
    let current = Desktop(id: "new", spaceID: 2, display: "test", position: 1, number: 2, isCurrent: true, isFullScreen: false)
    precondition(LayoutController.captureDesktop(stale, in: [stale]) == stale)
    precondition(LayoutController.captureDesktop(stale, in: [current]) == nil, "A desktop change during discovery must preserve the old saved layout")
    let other = Desktop(id: "other", spaceID: 3, display: "second", position: 0, number: 3, isCurrent: true, isFullScreen: false)
    let otherInactive = Desktop(id: "other", spaceID: 3, display: "second", position: 0, number: 3, isCurrent: false, isFullScreen: false)
    precondition(LayoutController.captureDesktopsUnchanged([stale, other], [stale, other]))
    precondition(!LayoutController.captureDesktopsUnchanged([stale, other], [stale, otherInactive]), "A Space change on a second screen invalidates capture even when topology and the requested desktop stay the same")
    let drag = PaneCaptureRequest(desktops: [stale])
    precondition(drag.accepts(desktops: [stale], mouseDown: true, cancelled: false))
    precondition(!drag.accepts(desktops: [stale], mouseDown: false, cancelled: false), "A delayed hit test after mouse-up cannot open a drag session")
    precondition(!drag.accepts(desktops: [stale], mouseDown: true, cancelled: true))
    precondition(!drag.accepts(desktops: [current], mouseDown: true, cancelled: false))
    var pendingEvidence = PaneMoveEvidence(initialFrame: CGRect(x: 10, y: 10, width: 300, height: 200), initialPointer: CGPoint(x: 100, y: 20), time: 10)
    pendingEvidence.observe(frame: CGRect(x: 30, y: 10, width: 300, height: 200), pointer: CGPoint(x: 120, y: 20), time: 10.05)
    pendingEvidence.observe(frame: CGRect(x: 50, y: 10, width: 300, height: 200), pointer: CGPoint(x: 140, y: 20), time: 10.1)
    precondition(pendingEvidence.moved, "Movement gathered during asynchronous AX lookup must be retained when the session is admitted")

    let queue = DispatchQueue(label: "local.desknames.test.accessibility-worker")
    let release = DispatchSemaphore(value: 0)
    var read: Task<Int32, Never>?
    await withCheckedContinuation { (started: CheckedContinuation<Void, Never>) in
        read = Task {
            await AccessibilityWorker.read(on: queue) {
                DispatchQueue.main.async { started.resume() }
                release.wait()
                return AXError.cannotComplete.rawValue
            }
        }
    }
    read?.cancel()
    release.signal()
    let result = await read?.value
    precondition(result == AXError.cannotComplete.rawValue)
    let next = await AccessibilityWorker.read(on: queue) { 42 }
    precondition(next == 42, "A timeout or cancelled reader must not strand the serial queue")
    let cancelled = Task {
        await AccessibilityWorker.cancellableRead(on: queue, cancelledValue: 0) { _ in
            precondition(false, "Cancelled queued discovery must not query a target app")
            return -1
        }
    }
    cancelled.cancel()
    let cancelledValue = await cancelled.value
    precondition(cancelledValue == 0)

    let domain = "local.desknames.ax-recovery.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: domain)!
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DeskNames-ax-recovery-\(UUID().uuidString)")
    defer { defaults.removePersistentDomain(forName: domain); try? FileManager.default.removeItem(at: directory) }
    var allowed = true
    let native = NativeWindows(trustCheck: { allowed }, includeExternal: false, diagnosticsDirectory: directory)
    let workspace = LayoutController(store: Store(defaults: defaults), file: directory.appendingPathComponent("layouts.json"), native: native)
    allowed = false
    precondition(workspace.trusted, "Reproduce trust revocation before the next UI poll")
    workspace.performWindowAction(.left, focused: true)
    precondition(workspace.operationTask == nil && workspace.message.contains("Accessibility"))
    let deniedFocus = await native.focusedWindowForOperation()
    let deniedWindows = await native.windowsForOperation()
    precondition(deniedFocus == nil && deniedWindows.isEmpty)
    allowed = true
    workspace.run(refreshWindows: false) { "Recovered after permission change" }
    await workspace.operationTask?.value
    precondition(!workspace.busy && workspace.message == "Recovered after permission change")
    print("PASS: bounded AX discovery; stale focus and revoked trust refusal; event-loop progress during blocked worker; cancelled read drain and subsequent queue work; runtime permission recovery")
}
