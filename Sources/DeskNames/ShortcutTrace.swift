import Foundation

enum ShortcutTrace {
    private static let lock = NSLock()
    private static var count = 0

    static func record(_ event: String, _ detail: @autoclosure () -> [String: Any]) {
        guard RuntimeStorage.current.isIsolated else { return }
        lock.lock()
        defer { lock.unlock() }
        guard count < 10_000 else { return }
        count += 1
        var value = detail()
        value["event"] = event
        value["uptime"] = ProcessInfo.processInfo.systemUptime
        value["traceSequence"] = count
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) else { return }
        let url = RuntimeStorage.current.supportDirectory.appendingPathComponent("chord-trace.jsonl")
        if !FileManager.default.fileExists(atPath: url.path) { _ = FileManager.default.createFile(atPath: url.path, contents: nil) }
        guard let file = try? FileHandle(forWritingTo: url) else { return }
        defer { try? file.close() }
        guard (try? file.seekToEnd()) != nil else { return }
        try? file.write(contentsOf: data + Data([0x0A]))
    }
}
