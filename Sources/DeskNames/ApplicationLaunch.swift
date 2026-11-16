import AppKit

enum ApplicationLaunchIssue: LocalizedError {
    case timedOut

    var errorDescription: String? {
        "Launching an application timed out. Open it yourself, then restore the layout again."
    }
}

private final class ApplicationLaunchCompletion: @unchecked Sendable {
    private enum State {
        case awaitingContinuation
        case waiting(CheckedContinuation<Void, Error>, DispatchWorkItem)
        case submitted(CheckedContinuation<Void, Error>, DispatchWorkItem)
        case finished(Result<Void, Error>)
    }
    private let lock = NSLock()
    private var state = State.awaitingContinuation

    func install(_ continuation: CheckedContinuation<Void, Error>, deadline: DispatchWorkItem) -> Bool {
        lock.lock()
        switch state {
        case .awaitingContinuation:
            state = .waiting(continuation, deadline)
            lock.unlock()
            return true
        case .finished(let result):
            lock.unlock()
            deadline.cancel()
            continuation.resume(with: result)
            return false
        case .waiting, .submitted:
            lock.unlock()
            preconditionFailure("A launch request can await completion only once")
        }
    }

    func beginSubmission() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard case .waiting(let continuation, let deadline) = state else { return false }
        state = .submitted(continuation, deadline)
        return true
    }

    func finish(_ result: Result<Void, Error>) {
        lock.lock()
        let previous = state
        if case .finished = previous { lock.unlock(); return }
        state = .finished(result)
        lock.unlock()
        switch previous {
        case .waiting(let continuation, let deadline), .submitted(let continuation, let deadline):
            deadline.cancel()
            continuation.resume(with: result)
        case .awaitingContinuation, .finished: break
        }
    }
}

enum ApplicationLaunch {
    @MainActor static func waitForCompletion(timeout: TimeInterval = 5,
                                            scheduleTimeout: (DispatchWorkItem, TimeInterval) -> Void = { item, delay in
                                                DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + delay, execute: item)
                                            },
                                            submit: (@escaping @Sendable (Error?) -> Void) -> Void) async throws {
        try Task.checkCancellation()
        let completion = ApplicationLaunchCompletion()
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                let deadline = DispatchWorkItem { [weak completion] in
                    completion?.finish(.failure(ApplicationLaunchIssue.timedOut))
                }
                guard completion.install(continuation, deadline: deadline) else { return }
                scheduleTimeout(deadline, timeout)
                guard completion.beginSubmission() else { return }
                submit { [weak completion] error in
                    completion?.finish(error.map { .failure($0) } ?? .success(()))
                }
            }
        }, onCancel: { completion.finish(.failure(CancellationError())) })
    }
}

@MainActor func launchLayoutApplication(at url: URL) async throws {
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = false
    configuration.promptsUserIfNeeded = false
    // Gatekeeper can still defer its callback despite suppressing optional prompts.
    try await ApplicationLaunch.waitForCompletion { completion in
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { app, error in
            completion(error ?? (app == nil ? WindowIssue("The application could not be opened.") : nil))
        }
    }
}
