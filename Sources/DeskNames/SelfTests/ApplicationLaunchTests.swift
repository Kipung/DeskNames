import AppKit

@MainActor private final class ApplicationLaunchFixture {
    var deadline: DispatchWorkItem?
    var timeout: TimeInterval?
    var callback: (@Sendable (Error?) -> Void)?
    private var observer: CheckedContinuation<Void, Never>?

    func launch() async throws {
        try await ApplicationLaunch.waitForCompletion(scheduleTimeout: { item, delay in
            self.deadline = item
            self.timeout = delay
        }, submit: { completion in
            self.callback = completion
            self.observer?.resume(); self.observer = nil
        })
    }
    func waitUntilSubmitted() async {
        if callback != nil { return }
        await withCheckedContinuation { observer = $0 }
    }
}

@MainActor func runApplicationLaunchTests() async throws {
    let unstarted = ApplicationLaunchFixture()
    let beforeStart = Task { @MainActor in try await unstarted.launch() }
    beforeStart.cancel()
    do { try await beforeStart.value; preconditionFailure("A cancelled request must not submit an application launch") }
    catch is CancellationError {}
    precondition(unstarted.callback == nil && unstarted.deadline == nil)

    do {
        try await ApplicationLaunch.waitForCompletion(scheduleTimeout: { item, _ in item.perform() }) { _ in
            preconditionFailure("An expired request must not submit an application launch")
        }
        preconditionFailure("An already expired deadline must propagate")
    } catch ApplicationLaunchIssue.timedOut {}

    let missing = ApplicationLaunchFixture()
    let expired = Task { @MainActor in try await missing.launch() }
    await missing.waitUntilSubmitted()
    precondition(missing.timeout == 5)
    missing.deadline?.perform()
    do { try await expired.value; preconditionFailure("A missing application callback must end at its deadline") }
    catch ApplicationLaunchIssue.timedOut {}
    precondition(missing.deadline?.isCancelled == true)
    missing.callback?(nil)
    missing.callback?(WindowIssue("Late failure"))

    let waiting = ApplicationLaunchFixture()
    let cancelled = Task { @MainActor in try await waiting.launch() }
    await waiting.waitUntilSubmitted()
    cancelled.cancel()
    do { try await cancelled.value; preconditionFailure("Cancellation must not wait for an application callback") }
    catch is CancellationError {}
    precondition(waiting.deadline?.isCancelled == true)
    waiting.callback?(nil)
    waiting.deadline?.perform()

    let succeeded = ApplicationLaunchFixture()
    let success = Task { @MainActor in try await succeeded.launch() }
    await succeeded.waitUntilSubmitted()
    succeeded.callback?(nil)
    try await success.value
    precondition(succeeded.deadline?.isCancelled == true)
    succeeded.callback?(WindowIssue("Duplicate callback"))
    succeeded.deadline?.perform()

    let rejected = ApplicationLaunchFixture()
    let failure = Task { @MainActor in try await rejected.launch() }
    await rejected.waitUntilSubmitted()
    rejected.callback?(WindowIssue("Launch refused"))
    do { try await failure.value; preconditionFailure("Launch errors must propagate") }
    catch let error as WindowIssue { precondition(error.message == "Launch refused") }
    precondition(rejected.deadline?.isCancelled == true)

    let domain = "local.desknames.application-launch.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: domain)!
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DeskNames-application-launch-\(UUID().uuidString)")
    defer { defaults.removePersistentDomain(forName: domain); try? FileManager.default.removeItem(at: directory) }
    let native = NativeWindows(trustCheck: { true }, includeExternal: false, diagnosticsDirectory: directory)
    let workspace = LayoutController(store: Store(defaults: defaults), file: directory.appendingPathComponent("layouts.json"), native: native)
    let blocked = ApplicationLaunchFixture()
    workspace.run(refreshWindows: false) {
        try await blocked.launch()
        return "Unexpected"
    }
    let blockedOperation = workspace.operationTask
    await blocked.waitUntilSubmitted()
    precondition(workspace.busy)
    blocked.deadline?.perform()
    await blockedOperation?.value
    precondition(!workspace.busy && workspace.operationTask == nil && workspace.message == ApplicationLaunchIssue.timedOut.localizedDescription,
                 "An application launch timeout must release the layout writer with a diagnostic")
    blocked.callback?(nil)
    workspace.run(refreshWindows: false) { "Shortcut recovered" }
    await workspace.operationTask?.value
    precondition(!workspace.busy && workspace.message == "Shortcut recovered")
    print("PASS: application launch cancellation before/during submission; missing callback deadline; success/error cleanup; late callbacks ignored; subsequent shortcut admission after launch timeout")
}
