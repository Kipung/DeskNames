import AppKit
import Carbon

enum HotkeyTestInput {
    static func canInjectToApp(expectedPID: pid_t, frontmostPID: pid_t?, mouseDown: Bool) -> Bool {
        !mouseDown && frontmostPID == expectedPID
    }
    static func canInject(expectedPID: pid_t, expectedWindowID: UInt32, frontmostPID: pid_t?, focusedWindowID: UInt32?, mouseDown: Bool) -> Bool {
        canInjectToApp(expectedPID: expectedPID, frontmostPID: frontmostPID, mouseDown: mouseDown) && focusedWindowID == expectedWindowID
    }
    static func terminalRefusal(_ result: String) -> Bool {
        ["No focused ordinary window", "Close the focused window", "Restore the minimized window", "The focused app did not answer", "Could not safely identify", "This window does not expose", "Focus an application document"].contains { result.hasPrefix($0) }
    }
    static func event(key: UInt16, down: Bool, modifiers: CGEventFlags) -> CGEvent {
        let event = CGEvent(keyboardEventSource: CGEventSource(stateID: .privateState), virtualKey: key, keyDown: down)!
        let ordinaryModifiers: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand, .maskShift]
        event.flags.subtract(ordinaryModifiers)
        event.flags.formUnion(modifiers)
        if [UInt16(55), 56, 58, 59].contains(key) { event.type = .flagsChanged }
        event.setIntegerValueField(.keyboardEventAutorepeat, value: 0)
        return event
    }
}

func runHotkeyInputTests() {
    precondition(HotkeyTestInput.canInjectToApp(expectedPID: 41, frontmostPID: 41, mouseDown: false))
    precondition(!HotkeyTestInput.canInjectToApp(expectedPID: 41, frontmostPID: 42, mouseDown: false))
    precondition(!HotkeyTestInput.canInjectToApp(expectedPID: 41, frontmostPID: nil, mouseDown: false))
    precondition(!HotkeyTestInput.canInjectToApp(expectedPID: 41, frontmostPID: 41, mouseDown: true))
    let inputCases: [(pid_t?, UInt32?, Bool, Bool)] = [
        (41, 101, false, true),
        (42, 101, false, false),
        (nil, 101, false, false),
        (41, 102, false, false),
        (41, nil, false, false),
        (41, 101, true, false)
    ]
    for (frontmost, focused, mouseDown, expected) in inputCases {
        precondition(HotkeyTestInput.canInject(expectedPID: 41, expectedWindowID: 101,
            frontmostPID: frontmost, focusedWindowID: focused, mouseDown: mouseDown) == expected,
            "Fixture input requires its exact focused window and a released mouse")
    }
    for key: UInt16 in [122,120,99,118,123,124,125,126] {
        for down in [false, true] {
            let event = HotkeyTestInput.event(key: key, down: down, modifiers: [.maskControl, .maskAlternate])
            precondition(event.flags.contains(.maskSecondaryFn), "Function and arrow keys must retain their intrinsic function flag for Carbon delivery")
            if (123...126).contains(key) { precondition(event.flags.contains(.maskNumericPad)) }
            precondition(event.flags.contains([.maskControl, .maskAlternate]))
        }
    }
    for key: UInt16 in [36,51,53,55,56,58,59] {
        let event = HotkeyTestInput.event(key: key, down: true, modifiers: [.maskControl, .maskAlternate])
        precondition(!event.flags.contains(.maskSecondaryFn) && !event.flags.contains(.maskNumericPad), "A preceding function or arrow key must not contaminate ordinary keys or modifier transitions")
    }
    for pending in ["Received.", "Working…", "Finding the focused window…", "Moved Finder to pane 1.", "Operation cancelled."] {
        precondition(!HotkeyTestInput.terminalRefusal(pending))
    }
    precondition(HotkeyTestInput.terminalRefusal("No focused ordinary window is available on this desktop. The app may be unresponsive."))
    let release = HotkeyTestInput.event(key: 59, down: false, modifiers: [])
    precondition(release.type == .flagsChanged && !release.flags.contains(.maskControl))
    print("PASS: synthetic hotkeys preserve intrinsic function/keypad flags and release modifier state with flagsChanged")
    print("PASS: fixture input refuses foreground changes, same-app window changes, missing focus, and held mouse input")
}

final class HotkeySoakDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply { .terminateCancel }
}

final class HotkeyFixtureDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        window = NSWindow(contentRect: NSRect(x: 300, y: 300, width: 640, height: 480), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "DeskNames disposable hotkey fixture"
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        let menu = NSMenu()
        let item = NSMenuItem(title: "Fixture", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let dialog = NSMenuItem(title: "Open test dialog", action: #selector(showDialog), keyEquivalent: "o")
        dialog.target = self
        submenu.addItem(dialog); item.submenu = submenu; menu.addItem(item)
        NSApp.mainMenu = menu
    }
    @objc func showDialog() {
        let alert = NSAlert()
        alert.messageText = "Disposable hotkey test dialog"
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window)
    }
}

@MainActor final class HotkeySoakTest {
    struct Observation: Codable {
        var scenario: String
        var result: String
        var reason: String
        var actionID: UInt32?
        var sequence: UInt64?
        var latency: Double?
        var target: SavedRect?
        var actual: SavedRect?
        var bundle: String?
    }
    struct Report: Codable {
        var trusted: Bool
        var operatingSystem: String
        var seed: UInt64
        var injectedPresses: Int
        var soakPresses: Int
        var storage: String
        var observations: [Observation]
        var cleanup: [String]
    }
    struct Fixture {
        let app: NSRunningApplication
        let window: LiveWindow
        let original: CGRect
        let close: Bool
    }
    struct Recovery: Codable {
        struct Window: Codable {
            let id: UInt32
            let pid: pid_t
            let bundle: String
            let original: SavedRect
            let close: Bool
        }
        let helperPID: pid_t
        let targetPID: pid_t?
        let textPID: pid_t?
        let hungPID: pid_t?
        var externalPID: pid_t?
        let hiddenPIDs: [pid_t]
        let storage: String
        let windows: [Window]
    }
    let directory: URL
    let journal: URL
    let native: NativeWindows
    let initialSpaces = Set(SpaceReader().read().filter(\.isCurrent).map(\.spaceID))
    var targetApp: NSRunningApplication?
    var textApp: NSRunningApplication?
    var hungApp: NSRunningApplication?
    var externalApp: NSRunningApplication?
    var hiddenApps: [NSRunningApplication] = []
    var stoppedPID: pid_t?
    var fixtures: [Fixture] = []
    var observations: [Observation] = []
    var cleanupResults: [String] = []
    var pressCount = 0
    var soakCount = 0
    var randomState: UInt64 = 0xD35C_2026_1115
    let seed: UInt64 = 0xD35C_2026_1115
    var support: URL { directory.appendingPathComponent("Application Support/DeskNames") }

    init(directory: URL, journal: URL? = nil) {
        self.directory = directory
        self.journal = journal ?? directory.appendingPathComponent("recovery.json")
        native = NativeWindows(diagnosticsDirectory: directory.appendingPathComponent("helper-diagnostics"))
    }
    func saveRecovery() throws {
        let recovery = Recovery(helperPID: getpid(), targetPID: targetApp?.processIdentifier, textPID: textApp?.processIdentifier, hungPID: hungApp?.processIdentifier, externalPID: externalApp?.processIdentifier, hiddenPIDs: hiddenApps.map(\.processIdentifier),
            storage: directory.path, windows: fixtures.map { Recovery.Window(id: $0.window.id, pid: $0.window.pid,
                bundle: $0.window.bundleID, original: SavedRect($0.original), close: $0.close) })
        try FileManager.default.createDirectory(at: journal.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(recovery).write(to: journal, options: .atomic)
    }
    func read(_ name: String) -> [String: Any] {
        guard let data = try? Data(contentsOf: support.appendingPathComponent(name)),
              let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return value
    }
    var sequence: UInt64 { (read("shortcut-result.json")["sequence"] as? NSNumber)?.uint64Value ?? 0 }
    func wait(_ timeout: Double, until predicate: () -> Bool) async -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        repeat {
            if predicate() { return true }
            await NativeWindows.pause(0.01)
        } while ProcessInfo.processInfo.systemUptime < deadline
        return predicate()
    }
    func checkSpace() throws {
        guard Set(SpaceReader().read().filter(\.isCurrent).map(\.spaceID)) == initialSpaces else {
            throw WindowIssue("Current desktop changed; refusing further input or automatic desktop navigation.")
        }
    }
    func note(_ scenario: String, _ passed: Bool, _ reason: String) {
        observations.append(Observation(scenario: scenario, result: passed ? "PASS" : "FAIL", reason: reason))
        print("\(passed ? "PASS" : "FAIL"): \(scenario): \(reason)")
        fflush(stdout)
    }
    func launch(_ url: URL, arguments: [String] = []) async throws -> NSRunningApplication {
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        config.activates = false
        config.arguments = arguments
        return try await withCheckedThrowingContinuation { continuation in
            NSWorkspace.shared.openApplication(at: url, configuration: config) { app, error in
                if let app { continuation.resume(returning: app) }
                else { continuation.resume(throwing: error ?? WindowIssue("Application launch failed.")) }
            }
        }
    }
    func process(_ executable: String, _ arguments: [String], timeout: Double = 12) async throws -> Int32 {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = arguments
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try task.run()
        let completed = await wait(timeout) { !task.isRunning }
        if !completed { task.terminate(); throw WindowIssue("Timed out: \(executable)") }
        return task.terminationStatus
    }
    func flags(_ modifiers: UInt32) -> CGEventFlags {
        var flags: CGEventFlags = []
        for (carbon, cg) in [(controlKey, CGEventFlags.maskControl), (optionKey, .maskAlternate), (cmdKey, .maskCommand), (shiftKey, .maskShift)] {
            if modifiers & UInt32(carbon) != 0 { flags.insert(cg) }
        }
        return flags
    }
    func key(_ code: UInt16, down: Bool, flags: CGEventFlags) {
        let event = HotkeyTestInput.event(key: code, down: down, modifiers: flags)
        event.post(tap: .cghidEventTap)
    }
    func modifiers(_ value: UInt32, down: Bool) async {
        let keys: [(UInt32, UInt16, CGEventFlags)] = [(UInt32(controlKey), 59, .maskControl), (UInt32(optionKey), 58, .maskAlternate), (UInt32(shiftKey), 56, .maskShift), (UInt32(cmdKey), 55, .maskCommand)]
        var current: CGEventFlags = down ? [] : flags(value)
        for (carbon, code, flag) in down ? keys : keys.reversed() {
            guard value & carbon != 0 else { continue }
            if down { current.insert(flag) } else { current.remove(flag) }
            key(code, down: down, flags: current)
        }
        await NativeWindows.pause(0.005)
    }
    func tap(_ code: UInt16, flags: CGEventFlags = []) async {
        key(code, down: true, flags: flags)
        await NativeWindows.pause(0.005)
        key(code, down: false, flags: flags)
    }
    func press(_ id: UInt32, expectedPID: pid_t) async throws {
        guard let binding = ShortcutDefaults.bindings[id] else { throw WindowIssue("No default shortcut for action \(id).") }
        try await plain(UInt16(binding.key), expectedPID: expectedPID, modifiers: binding.modifiers)
        pressCount += 1
    }
    func plain(_ code: UInt16, expectedPID: pid_t, modifiers value: UInt32 = 0) async throws {
        try requireAppInput(expectedPID)
        do {
            await modifiers(value, down: true)
            try requireAppInput(expectedPID)
            await tap(code, flags: flags(value))
            await modifiers(value, down: false)
        } catch {
            await modifiers(value, down: false)
            throw error
        }
    }
    func windowID(_ element: AXUIElement) -> UInt32? {
        typealias GetID = @convention(c) (AXUIElement, UnsafeMutablePointer<UInt32>) -> Int32
        guard let symbol = dlsym(dlopen(nil, RTLD_NOW), "_AXUIElementGetWindow") else { return nil }
        var id: UInt32 = 0
        return unsafeBitCast(symbol, to: GetID.self)(element, &id) == 0 ? id : nil
    }
    func focusedID(_ app: NSRunningApplication) -> UInt32? {
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.15)
        guard let value = axValue(element, kAXFocusedWindowAttribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return windowID(unsafeBitCast(value, to: AXUIElement.self))
    }
    func click(_ point: CGPoint) async throws {
        for type: CGEventType in [.leftMouseDown, .leftMouseUp] {
            let event = CGEvent(mouseEventSource: CGEventSource(stateID: .privateState), mouseType: type, mouseCursorPosition: point, mouseButton: .left)
            event?.flags = []
            event?.post(tap: .cghidEventTap)
            await NativeWindows.pause(0.01)
        }
        guard await wait(0.25, until: { !CGEventSource.buttonState(.combinedSessionState, button: .left) }) else {
            throw WindowIssue("Posted mouse-up was not acknowledged; no further keys sent.")
        }
    }
    func activate(_ app: NSRunningApplication) async throws {
        try checkSpace()
        let fixture = fixtures.first { $0.window.pid == app.processIdentifier }
        let visible = ExternalPlacementTest.serverWindows().filter { $0.pid == app.processIdentifier && $0.layer == 0 }
        if let fixture {
            guard visible.contains(where: { $0.id == fixture.window.id }) else { throw WindowIssue("Fixture is not on screen; refusing activation that could change desktop.") }
            if case .accessibility(let element) = fixture.window.target {
                AXUIElementPerformAction(element, kAXRaiseAction as CFString)
                AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
            }
        } else {
            let root = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(root, 0.2)
            if let value = axValue(root, kAXFocusedWindowAttribute) ?? axValue(root, kAXMainWindowAttribute), CFGetTypeID(value) == AXUIElementGetTypeID() {
                guard let id = windowID(unsafeBitCast(value, to: AXUIElement.self)), visible.contains(where: { $0.id == id }) else { throw WindowIssue("Activation window is off screen; no desktop change attempted.") }
            } else {
                var value: CFTypeRef?
                let error = AXUIElementCopyAttributeValue(root, kAXWindowsAttribute as CFString, &value)
                let empty = error == .noValue || (error == .success && (value as? [AXUIElement])?.isEmpty == true)
                guard empty else { throw WindowIssue("Cannot establish an on-screen activation window for \(app.bundleIdentifier ?? "unknown"); AXWindows error \(error.rawValue).") }
            }
        }
        guard app.activate(options: []) else { throw WindowIssue("Could not activate fixture application.") }
        guard await wait(2, until: { NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier }) else { throw WindowIssue("Fixture activation timed out.") }
        await NativeWindows.pause(0.15)
        if let fixture, case .accessibility(let element) = fixture.window.target {
            AXUIElementPerformAction(element, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
            AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            guard await wait(2, until: {
                NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier &&
                self.focusedID(app) == fixture.window.id &&
                ExternalPlacementTest.serverWindows().first(where: { $0.layer == 0 && $0.frame.width > 80 && $0.frame.height > 50 })?.id == fixture.window.id
            }) else { throw WindowIssue("Exact fixture did not become the frontmost focused window.") }
        }
        await NativeWindows.pause(0.1)
        try checkSpace()
    }
    func capture(_ app: NSRunningApplication, close: Bool, excluding existingIDs: Set<UInt32> = []) async throws -> Fixture {
        var reason = ""
        var candidate: LiveWindow?
        for _ in 0..<30 {
            candidate = await native.focusedWindowForOperation(onFailure: { reason = $0 })
            if candidate?.pid == app.processIdentifier { break }
            await NativeWindows.pause(0.1)
        }
        guard let window = candidate, window.pid == app.processIdentifier,
              let original = native.currentFrame(window) else { throw WindowIssue("Fixture discovery: \(reason)") }
        guard !existingIDs.contains(window.id) else { throw WindowIssue("No new fixture window was created; refusing ownership of an existing window.") }
        let fixture = Fixture(app: app, window: window, original: original, close: close)
        fixtures.append(fixture)
        try saveRecovery()
        return fixture
    }
    func target(_ id: UInt32, fixture: Fixture) -> CGRect {
        let screen = screenFor(fixture.original)!
        let area = screenArea(screen)
        if (320...323).contains(id) {
            return PaneGeometry(area: area, configuration: PaneConfiguration(preset: .fourColumns, gap: 0), pixelScale: screen.backingScaleFactor).cells[Int(id - 320)]
        }
        if id == WindowAction.restore.id { return fixture.original }
        return WindowAction.allCases.first { $0.id == id }!.frame(in: area, current: fixture.original)!
    }
    func matches(_ actual: CGRect?, _ target: CGRect) -> Bool {
        guard let actual else { return false }
        return abs(actual.minX-target.minX) <= 1 && abs(actual.minY-target.minY) <= 1 && abs(actual.width-target.width) <= 1 && abs(actual.height-target.height) <= 1
    }
    func successful(_ result: String, id: UInt32) -> Bool {
        if (320...323).contains(id) { return result.hasPrefix("Moved ") && result.contains(" to pane") }
        return WindowAction.allCases.first { $0.id == id }.map { result.hasPrefix($0.name + ":") } ?? false
    }
    func requireAppInput(_ expectedPID: pid_t) throws {
        try checkSpace()
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let mouseDown = CGEventSource.buttonState(.combinedSessionState, button: .left)
        guard HotkeyTestInput.canInjectToApp(expectedPID: expectedPID, frontmostPID: frontmost, mouseDown: mouseDown) else {
            throw WindowIssue("App input interrupted: expected PID \(expectedPID); frontmost PID \(frontmost.map(String.init) ?? "none"), left mouse held \(mouseDown). No further keys sent.")
        }
    }
    func requireFixtureInput(_ fixture: Fixture) throws {
        try checkSpace()
        let focused = focusedID(fixture.app)
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let mouseDown = CGEventSource.buttonState(.combinedSessionState, button: .left)
        guard HotkeyTestInput.canInject(expectedPID: fixture.window.pid, expectedWindowID: fixture.window.id,
                                       frontmostPID: frontmost, focusedWindowID: focused, mouseDown: mouseDown) else {
            throw WindowIssue("Fixture input interrupted: expected PID \(fixture.window.pid), window \(fixture.window.id); frontmost PID \(frontmost.map(String.init) ?? "none"), focused window \(focused.map(String.init) ?? "none"), left mouse held \(mouseDown). No further placement keys sent.")
        }
    }
    func pressFixture(_ id: UInt32, fixture: Fixture, release: Bool = true, hold: Bool = true) async throws {
        guard let binding = ShortcutDefaults.bindings[id] else { throw WindowIssue("No default shortcut for action \(id).") }
        try requireFixtureInput(fixture)
        do {
            if hold { await modifiers(binding.modifiers, down: true) }
            try requireFixtureInput(fixture)
            await tap(UInt16(binding.key), flags: flags(binding.modifiers))
            pressCount += 1
            if release { await modifiers(binding.modifiers, down: false) }
            try requireFixtureInput(fixture)
        } catch {
            await modifiers(binding.modifiers, down: false)
            throw error
        }
    }
    @discardableResult func probe(_ scenario: String, id: UInt32, fixture: Fixture, target expected: CGRect? = nil,
                                  timeout: Double = 1.5, input: (() async throws -> Void)? = nil) async throws -> Bool {
        try requireFixtureInput(fixture)
        let expected = expected ?? target(id, fixture: fixture)
        let before = sequence
        let start = ProcessInfo.processInfo.systemUptime
        if let input { try await input() } else { try await pressFixture(id, fixture: fixture) }
        let passed = await wait(max(0, timeout - (ProcessInfo.processInfo.systemUptime-start))) {
            let diagnostic = self.read("shortcut-result.json")
            let result = diagnostic["result"] as? String ?? ""
            return self.sequence > before && diagnostic["actionID"] as? UInt32 == id &&
                self.successful(result, id: id) &&
                self.matches(self.native.currentFrame(fixture.window), expected) &&
                self.read("hotkey-status.json")["busy"] as? Bool == false
        }
        try requireFixtureInput(fixture)
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        let result = read("shortcut-result.json")["result"] as? String ?? "No diagnostic"
        observations.append(Observation(scenario: scenario, result: passed ? "PASS" : "FAIL", reason: result, actionID: id,
            sequence: sequence, latency: elapsed, target: SavedRect(expected), actual: native.currentFrame(fixture.window).map(SavedRect.init), bundle: fixture.window.bundleID))
        print("\(passed ? "PASS" : "FAIL"): \(scenario) \(String(format: "%.3f", elapsed))s sequence=\(sequence) \(result)")
        fflush(stdout)
        return passed
    }
    func refusal(_ scenario: String, expectedPID: pid_t, id: UInt32 = 320, timeout: Double = 2) async throws {
        try requireAppInput(expectedPID)
        let originalBounds = fixtures.map { native.currentFrame($0.window) }
        let before = sequence
        let start = ProcessInfo.processInfo.systemUptime
        try await press(id, expectedPID: expectedPID)
        let passed = await wait(max(0, timeout - (ProcessInfo.processInfo.systemUptime-start))) {
            let diagnostic = self.read("shortcut-result.json")
            let result = diagnostic["result"] as? String ?? ""
            return self.sequence > before && diagnostic["actionID"] as? UInt32 == id &&
                diagnostic["busy"] as? Bool == false &&
                NSWorkspace.shared.frontmostApplication?.processIdentifier == expectedPID &&
                HotkeyTestInput.terminalRefusal(result)
        }
        try requireAppInput(expectedPID)
        let unchanged = zip(fixtures, originalBounds).allSatisfy { fixture, original in
            let actual = native.currentFrame(fixture.window)
            if let original { return matches(actual, original) }
            return actual == nil
        }
        observations.append(Observation(scenario: scenario, result: passed && unchanged ? "PASS" : "FAIL",
            reason: (read("shortcut-result.json")["result"] as? String ?? "No diagnostic") + " Bounds unchanged: \(unchanged).", actionID: id,
            sequence: sequence, latency: ProcessInfo.processInfo.systemUptime-start,
            bundle: NSRunningApplication(processIdentifier: expectedPID)?.bundleIdentifier))
    }
    func axWindows(_ app: NSRunningApplication) -> [AXUIElement] {
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 1)
        return axValue(element, kAXWindowsAttribute) as? [AXUIElement] ?? []
    }
    func allWindowIDs(_ pid: pid_t) -> Set<UInt32> {
        let rows = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
        return Set(rows.filter { $0[kCGWindowOwnerPID as String] as? pid_t == pid }.compactMap { $0[kCGWindowNumber as String] as? UInt32 })
    }
    func findAX(_ root: AXUIElement, matching predicate: (AXUIElement) -> Bool) -> AXUIElement? {
        var queue = [root], count = 0
        while !queue.isEmpty && count < 1600 {
            let value = queue.removeFirst(); count += 1
            AXUIElementSetMessagingTimeout(value, 0.1)
            if predicate(value) { return value }
            queue += axValue(value, kAXChildrenAttribute) as? [AXUIElement] ?? []
        }
        return nil
    }
    func button(_ label: String, app: NSRunningApplication) async -> Bool {
        var found: AXUIElement?
        for _ in 0..<20 {
            found = findAX(AXUIElementCreateApplication(app.processIdentifier)) { value in
                guard axValue(value, kAXRoleAttribute) as? String == kAXButtonRole else { return false }
                return [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute].contains { axValue(value, $0) as? String == label }
            }
            if found != nil { break }
            await NativeWindows.pause(0.1)
        }
        guard let found else {
            var labels: [String] = []
            _ = findAX(AXUIElementCreateApplication(app.processIdentifier)) { value in
                let role = axValue(value, kAXRoleAttribute) as? String ?? "?"
                if role == kAXButtonRole { labels.append([kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute].compactMap { axValue(value, $0) as? String }.joined(separator: "/")) }
                return false
            }
            note("button-discovery", false, "Missing \(label); available buttons \(labels)")
            return false
        }
        AXUIElementSetMessagingTimeout(found, 2)
        let error = AXUIElementPerformAction(found, kAXPressAction as CFString)
        if error != .success { note("button-press", false, "\(label): AX error \(error.rawValue)") }
        return error == .success
    }
    func closeWindow(_ window: AXUIElement) {
        AXUIElementSetMessagingTimeout(window, 2)
        if let value = axValue(window, kAXCloseButtonAttribute), CFGetTypeID(value) == AXUIElementGetTypeID() {
            let button = unsafeBitCast(value, to: AXUIElement.self)
            AXUIElementSetMessagingTimeout(button, 2)
            let error = AXUIElementPerformAction(button, kAXPressAction as CFString)
            if error != .success { print("CLOSE AX error \(error.rawValue) window \(windowID(window) ?? 0)"); fflush(stdout) }
        }
    }
    func sheets(_ window: AXUIElement) -> [AXUIElement] {
        (axValue(window, kAXChildrenAttribute) as? [AXUIElement] ?? []).filter { axValue($0, kAXRoleAttribute) as? String == kAXSheetRole }
    }
    func sheetButton(_ window: AXUIElement, identifier: String) -> Bool {
        let sheets = sheets(window)
        for sheet in sheets {
            if let button = findAX(sheet, matching: { axValue($0, "AXIdentifier") as? String == identifier }) {
                return AXUIElementPerformAction(button, kAXPressAction as CFString) == .success
            }
        }
        return false
    }
    func run() async throws {
        try saveRecovery()
        guard AXIsProcessTrusted() else { throw WindowIssue("Accessibility trust is required for real key injection.") }
        guard !IsSecureEventInputEnabled() else { throw WindowIssue("Secure Input is enabled; macOS can block synthetic/global key delivery.") }
        let storage = try RuntimeStorage(directory: directory)
        storage.defaults.set("complete", forKey: "onboarding.v1")
        storage.defaults.set(true, forKey: "paneDiagnosticsEnabled")
        let shortcuts = ShortcutSettings(defaults: storage.defaults)
        shortcuts.enableSuggestions()
        let panes = PanePreferences(defaults: storage.defaults)
        for desktop in SpaceReader().read() where desktop.isCurrent && !desktop.isFullScreen {
            panes.set(PaneConfiguration(preset: .fourColumns, gap: 0), for: desktop.id)
        }
        storage.defaults.synchronize()
        let existing = NSRunningApplication.runningApplications(withBundleIdentifier: "local.desknames.app").filter { $0.processIdentifier != getpid() }
        if !existing.isEmpty {
            _ = try await process("/usr/bin/osascript", ["-e", "tell application id \"local.desknames.app\" to quit"])
            for app in existing where !app.isTerminated { app.terminate() }
        }
        guard await wait(5, until: { existing.allSatisfy(\.isTerminated) }) else { throw WindowIssue("Installed DeskNames did not quit; refusing duplicate hotkey registration.") }
        targetApp = try await launch(Bundle.main.bundleURL, arguments: ["--storage", directory.path])
        try saveRecovery()
        guard await wait(10, until: { self.read("hotkey-status.json")["registeredCount"] as? Int == ShortcutDefaults.bindings.count }) else {
            throw WindowIssue("Normal instance did not register all default shortcuts: \(read("hotkey-status.json"))")
        }
        let textApp: NSRunningApplication
        if let existing = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.TextEdit").first {
            textApp = existing
        } else {
            textApp = try await launch(URL(fileURLWithPath: "/System/Applications/TextEdit.app"))
            self.textApp = textApp
        }
        try saveRecovery()
        let textBefore = allWindowIDs(textApp.processIdentifier)
        try await activate(textApp)
        try await plain(53, expectedPID: textApp.processIdentifier)
        try await plain(45, expectedPID: textApp.processIdentifier, modifiers: UInt32(cmdKey))
        await NativeWindows.pause(0.6)
        let text = try await capture(textApp, close: true, excluding: textBefore)
        guard let finderApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first else { throw WindowIssue("Finder is unavailable.") }
        let finderBefore = allWindowIDs(finderApp.processIdentifier)
        try await activate(finderApp)
        try await plain(45, expectedPID: finderApp.processIdentifier, modifiers: UInt32(cmdKey))
        await NativeWindows.pause(0.6)
        let finder = try await capture(finderApp, close: true, excluding: finderBefore)
        for bundle in ["md.obsidian", "com.microsoft.VSCode", "com.apple.Safari"] {
            guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first,
                  ExternalPlacementTest.serverWindows().contains(where: { $0.pid == app.processIdentifier && $0.layer == 0 && $0.frame.width > 80 }) else { continue }
            try await activate(app)
            _ = try await capture(app, close: false)
            break
        }
        guard fixtures.count == 3 else { throw WindowIssue("Three-app soak needs an on-screen Obsidian, VS Code, or Safari window.") }
        for fixture in fixtures {
            try await activate(fixture.app)
            for id: UInt32 in [320,321,322,323,200,201,202,203,211,213] {
                _ = try await probe("placement", id: id, fixture: fixture)
            }
            for repetition in 0..<(CommandLine.arguments.contains("--chord-stress") ? 20 : 1) {
                let stress = CommandLine.arguments.contains("--chord-stress")
                let interval = stress ? Double(20 + repetition * 37 % 81)/1000 : 0.04
                if stress { await NativeWindows.pause(Double(repetition * 53 % 191)/1000) }
                let cells = PaneGeometry(area: screenArea(screenFor(fixture.original)!), configuration: PaneConfiguration(preset: .fourColumns, gap: 0)).cells
                _ = try await probe("chord-3-4", id: 323, fixture: fixture, target: cells[2].union(cells[3])) {
                    try await self.pressFixture(322, fixture: fixture, release: false)
                    await NativeWindows.pause(interval)
                    try await self.pressFixture(323, fixture: fixture, hold: false)
                }
                _ = try await probe("chord-release-2", id: 321, fixture: fixture)
                _ = try await probe("chord-4-2", id: 321, fixture: fixture, target: cells[1].union(cells[2]).union(cells[3])) {
                    try await self.pressFixture(323, fixture: fixture, release: false)
                    await NativeWindows.pause(interval)
                    try await self.pressFixture(321, fixture: fixture, hold: false)
                }
            }
        }
        let soakActions: [UInt32] = [320,321,322,323,200,201,202,203,211]
        for block in 0..<(CommandLine.arguments.contains("--quick") ? 0 : 12) {
            var requests: [(UInt64, UInt32)] = []
            let firstSequence = sequence + 1
            let fixture = fixtures[block % fixtures.count]
            try await activate(fixture.app)
            for _ in 0..<25 {
                randomState = randomState &* 6364136223846793005 &+ 1442695040888963407
                let id = soakActions[Int((randomState >> 32) % UInt64(soakActions.count))]
                let before = sequence
                let start = ProcessInfo.processInfo.systemUptime
                requests.append((firstSequence + UInt64(requests.count), id))
                try await pressFixture(id, fixture: fixture); soakCount += 1
                randomState = randomState &* 6364136223846793005 &+ 1442695040888963407
                await NativeWindows.pause(Double(20 + (randomState >> 32) % 381)/1000)
                try requireFixtureInput(fixture)
                let diagnostic = read("shortcut-result.json")
                let delivered = sequence > before && diagnostic["actionID"] as? UInt32 == id
                let busy = read("hotkey-status.json")["busy"] as? Bool ?? true
                let expected = target(id, fixture: fixture)
                let actual = native.currentFrame(fixture.window)
                let result = diagnostic["result"] as? String ?? "No diagnostic"
                let terminal = successful(result, id: id)
                let pending = result == "Received." || result == "Working…" || result.contains("Finding")
                let correct = terminal ? matches(actual, expected) : pending
                observations.append(Observation(scenario: "soak-press", result: !delivered ? "IN_FLIGHT" : (correct ? (busy || !terminal ? "IN_FLIGHT" : "PASS") : "FAIL"),
                    reason: result, actionID: id, sequence: sequence,
                    latency: delivered && terminal ? (diagnostic["updatedUptime"] as? Double).map { $0-start } : nil,
                    target: SavedRect(expected), actual: actual.map(SavedRect.init), bundle: fixture.window.bundleID))
            }
            _ = try await probe("soak-probe-\(soakCount)", id: UInt32(320 + block % 4), fixture: fixture)
            let events = (try? String(contentsOf: support.appendingPathComponent("hotkey-events.jsonl"), encoding: .utf8))?.split(separator: "\n").compactMap { line -> [String: Any]? in
                try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
            } ?? []
            let received = events.filter { $0["result"] as? String == "Received." }
            let complete = requests.allSatisfy { expected in received.contains { ($0["sequence"] as? NSNumber)?.uint64Value == expected.0 && $0["actionID"] as? UInt32 == expected.1 } }
            note("soak-delivery-\(soakCount)", complete, "25 requested keys matched sequence and action in Carbon delivery history")
            try checkSpace()
        }
        note("soak-idle", await wait(2) { self.read("hotkey-status.json")["busy"] as? Bool == false }, "\(soakCount) randomized presses; final operation drained")
        if EnableSecureEventInput() == noErr {
            let visible = await wait(2) { self.read("hotkey-status.json")["cause"] as? String == "secure-input" }
            DisableSecureEventInput()
            note("secure-input-status", visible, "Real secure input is reported without a delivered shortcut")
            note("secure-input-clear", await wait(2) { self.read("hotkey-status.json")["cause"] as? String == "ready" }, "Availability returns after secure input is released")
        }
        try await panelTests(text)
        hungApp = try await launch(Bundle.main.bundleURL, arguments: ["--hotkey-soak-fixture"])
        try saveRecovery()
        guard let hungApp else { throw WindowIssue("Disposable hang fixture did not launch.") }
        guard await wait(5, until: { !self.axWindows(hungApp).isEmpty }) else { throw WindowIssue("Disposable fixture AX server did not become ready.") }
        try await activate(hungApp)
        let hung = try await capture(hungApp, close: true)
        stoppedPID = hungApp.processIdentifier
        guard kill(hungApp.processIdentifier, SIGSTOP) == 0 else { throw WindowIssue("Could not suspend disposable fixture.") }
        try await refusal("hung-app", expectedPID: hungApp.processIdentifier)
        try await activate(finderApp)
        _ = try await probe("hung-other-app", id: 322, fixture: finder)
        kill(hungApp.processIdentifier, SIGCONT); stoppedPID = nil
        try await activate(hungApp)
        _ = try await probe("hung-recovery", id: 323, fixture: hung)
        try await edgeTests(text, finder: finder, minimized: hung)
        if !CommandLine.arguments.contains("--quick") {
            let externalReport = directory.appendingPathComponent("external-placement.json")
            externalApp = try await launch(Bundle.main.bundleURL, arguments: ["--storage", directory.appendingPathComponent("external-storage").path, "--external-placement-test", "md.obsidian,com.apple.TextEdit,com.apple.finder", "--report", externalReport.path])
            try saveRecovery()
            let completed = await wait(90) { self.externalApp?.isTerminated == true }
            guard completed else { externalApp?.forceTerminate(); throw WindowIssue("External placement helper timed out.") }
            let data = try Data(contentsOf: externalReport)
            let report = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let apps = report?["applications"] as? [[String: Any]] ?? []
            let steps = apps.flatMap { $0["steps"] as? [[String: Any]] ?? [] }
            note("external-placement", completed && apps.count == 3 && steps.count == 45 && steps.allSatisfy { $0["result"] as? String == "PASS" }, "\(steps.filter { $0["result"] as? String == "PASS" }.count)/45 steps; report \(externalReport.path)")
        }
        observations.append(Observation(scenario: "display-sleep-wake", result: "SKIP", reason: "Display sleep was not attempted because unattended wake may require a password; verify the lock policy separately before running this scenario."))
        try checkSpace()
    }
    func panelTests(_ fixture: Fixture) async throws {
        guard let app = targetApp else { return }
        for mode in ["escape", "toggle", "other-app"] {
            try await activate(fixture.app)
            let before = sequence
            try await press(100, expectedPID: fixture.app.processIdentifier)
            let opened = await wait(2) { self.sequence > before && self.read("shortcut-result.json")["result"] as? String == "Control panel opened." }
            let key = await wait(2) { NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier && self.focusedID(app) != nil }
            note("panel-open-\(mode)", opened && key, "Carbon panel shortcut and focused panel")
            await NativeWindows.pause(0.1)
            if mode == "escape" { try await plain(53, expectedPID: app.processIdentifier) }
            else if mode == "toggle" { try await press(100, expectedPID: app.processIdentifier) }
            else {
                try requireAppInput(app.processIdentifier)
                let frame = native.currentFrame(fixture.window)!
                let point = CGPoint(x: frame.midX, y: frame.minY+12)
                try await click(point)
            }
            let focused = await wait(1) { NSWorkspace.shared.frontmostApplication?.processIdentifier == fixture.app.processIdentifier }
            let hidden = !ExternalPlacementTest.serverWindows().contains { $0.pid == app.processIdentifier && $0.frame.width > 300 && $0.frame.height > 300 }
            note("panel-\(mode)-closed", focused && hidden, "Panel hidden and fixture focused before recovery press")
            _ = try await probe("panel-\(mode)-recovery", id: 320, fixture: fixture)
        }
        for recording in [false, true] {
            try await activate(fixture.app)
            let before = sequence
            try await press(100, expectedPID: fixture.app.processIdentifier)
            let shown = await wait(2) { self.sequence > before && self.read("shortcut-result.json")["result"] as? String == "Control panel opened." }
            note("settings-panel-open", shown, self.read("shortcut-result.json")["result"] as? String ?? "No diagnostic")
            _ = await wait(2) { NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier && self.focusedID(app) != nil }
            await NativeWindows.pause(0.15)
            let opened = await button("Settings", app: app)
            note(recording ? "recorder-settings-open" : "settings-open", opened, "AX press on actual Settings button")
            _ = await wait(2) { NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier && self.focusedID(app) != nil }
            await NativeWindows.pause(0.3)
            if recording {
                let tab = await button("Keyboard shortcuts", app: app)
                let record = tab ? await button("DeskNames control panel shortcut", app: app) : false
                let entered = await wait(2) { self.read("hotkey-status.json")["recordingAction"] as? UInt32 == 100 }
                note("recorder-begin", record && entered, "tab=\(tab) button=\(record) entered=\(entered)")
                try await plain(53, expectedPID: app.processIdentifier)
                let restored = await wait(2) { self.read("hotkey-status.json")["registeredCount"] as? Int == ShortcutDefaults.bindings.count }
                note("recorder-cancel", entered && restored, "Escape restores every registration")
            }
            for window in axWindows(app) { closeWindow(window) }
            note(recording ? "recorder-settings-closed" : "settings-closed", await wait(3) {
                !ExternalPlacementTest.serverWindows().contains { $0.pid == app.processIdentifier && $0.frame.width > 300 && $0.frame.height > 300 }
            }, "Remaining target windows \(ExternalPlacementTest.serverWindows().filter { $0.pid == app.processIdentifier })")
            try await activate(fixture.app)
            _ = try await probe(recording ? "recorder-recovery" : "settings-recovery", id: 321, fixture: fixture)
        }
    }
    func edgeTests(_ text: Fixture, finder: Fixture, minimized: Fixture) async throws {
        try await activate(minimized.app)
        guard case .accessibility(let fixtureWindow) = minimized.window.target else { throw WindowIssue("Native fixture AX window unavailable.") }
        try await plain(31, expectedPID: minimized.app.processIdentifier, modifiers: UInt32(cmdKey))
        let dialog = await wait(3) { !self.sheets(fixtureWindow).isEmpty }
        note("dialog-precondition", dialog, "Owned native document has an attached modal sheet")
        if dialog { try await refusal("dialog-frontmost", expectedPID: minimized.app.processIdentifier) }
        if let sheet = sheets(fixtureWindow).first,
           let cancel = findAX(sheet, matching: { axValue($0, kAXRoleAttribute) as? String == kAXButtonRole }) {
            AXUIElementPerformAction(cancel, kAXPressAction as CFString)
        }
        _ = await wait(2) { self.sheets(fixtureWindow).isEmpty }
        try await activate(minimized.app)
        _ = try await probe("dialog-recovery", id: 322, fixture: minimized)
        let minimizeError = AXUIElementSetAttributeValue(fixtureWindow, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
        let didMinimize = await wait(3) { axValue(fixtureWindow, kAXMinimizedAttribute) as? Bool == true }
        note("minimized-precondition", didMinimize && NSWorkspace.shared.frontmostApplication?.processIdentifier == minimized.app.processIdentifier, "AX minimize result \(minimizeError.rawValue); exact owned fixture")
        if didMinimize { try await refusal("minimized-window", expectedPID: minimized.app.processIdentifier) }
        let restoreError = AXUIElementSetAttributeValue(fixtureWindow, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        let visible = await wait(3) { ExternalPlacementTest.serverWindows().contains { $0.id == minimized.window.id } && axValue(fixtureWindow, kAXMinimizedAttribute) as? Bool == false }
        note("deminimized-precondition", visible, "AX restore result \(restoreError.rawValue)")
        if visible {
            try await activate(minimized.app)
            _ = try await probe("minimized-recovery", id: 323, fixture: minimized)
        }
        try await activate(finder.app)
        hiddenApps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && !$0.isHidden && $0.processIdentifier != finder.app.processIdentifier }
        try saveRecovery()
        for app in hiddenApps { app.hide() }
        await NativeWindows.pause(0.2)
        var minimizedFinder: [AXUIElement] = []
        let visibleFinder = Set(ExternalPlacementTest.serverWindows().filter { $0.pid == finder.app.processIdentifier && $0.layer == 0 }.map(\.id))
        for window in axWindows(finder.app) {
            guard let id = windowID(window), visibleFinder.contains(id), axValue(window, kAXSubroleAttribute) as? String == kAXStandardWindowSubrole,
                  let frame = ExternalPlacementTest.serverWindows().first(where: { $0.id == id })?.frame else { continue }
            if !fixtures.contains(where: { $0.window.id == id }) {
                let live = LiveWindow(id: id, target: .accessibility(window), pid: finder.app.processIdentifier, bundleID: "com.apple.finder", appName: "Finder", title: "", frame: frame, spaceIDs: native.spaces(for: id), minimized: false)
                fixtures.append(Fixture(app: finder.app, window: live, original: frame, close: false))
                try saveRecovery()
            }
            if AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanTrue) == .success { minimizedFinder.append(window) }
        }
        _ = await wait(3) { minimizedFinder.allSatisfy { axValue($0, kAXMinimizedAttribute) as? Bool == true } }
        let area = screenArea(screenFor(finder.original)!)
        let covers = ExternalPlacementTest.serverWindows().filter {
            $0.layer == 0 && NSRunningApplication(processIdentifier: $0.pid)?.activationPolicy == .regular
        }
        let points = stride(from: area.minY+10, to: area.maxY-10, by: 100).flatMap { y in
            stride(from: area.minX+10, to: area.maxX-10, by: 100).map { CGPoint(x: $0, y: y) }
        }
        if let point = points.first(where: { point in !covers.contains { $0.frame.contains(point) } }) {
            try await click(point)
            await NativeWindows.pause(0.3)
            let desktopFocus = axValue(AXUIElementCreateApplication(finder.app.processIdentifier), kAXFocusedWindowAttribute)
            let focusedID = self.focusedID(finder.app)
            let visibleFocus = ExternalPlacementTest.serverWindows().contains { $0.pid == finder.app.processIdentifier && $0.id == focusedID && $0.layer == 0 }
            let isDesktop = !visibleFocus && NSWorkspace.shared.frontmostApplication?.processIdentifier == finder.app.processIdentifier
            note("finder-desktop-precondition", isDesktop, "Finder is frontmost; no visible focused browser window. AX focus absent: \(desktopFocus == nil), visible: \(visibleFocus)")
            if isDesktop { try await refusal("finder-desktop", expectedPID: finder.app.processIdentifier) }
        } else {
            note("finder-desktop", false, "No uncovered desktop point after minimizing current-desktop Finder windows: \(covers)")
        }
        for window in minimizedFinder { AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse) }
        for app in hiddenApps { app.unhide() }
        hiddenApps = []
        _ = await wait(3) { minimizedFinder.allSatisfy { axValue($0, kAXMinimizedAttribute) as? Bool == false } }
        try saveRecovery()
        try await activate(text.app)
        _ = try await probe("no-focus-recovery", id: 320, fixture: text)
    }
    func cleanup() async {
        await modifiers(UInt32(controlKey|optionKey|cmdKey|shiftKey), down: false)
        for app in hiddenApps { app.unhide() }
        hiddenApps = []
        if let stoppedPID { kill(stoppedPID, SIGCONT); self.stoppedPID = nil }
        if let externalApp, !externalApp.isTerminated { externalApp.forceTerminate(); _ = await wait(2) { externalApp.isTerminated } }
        if let targetApp { targetApp.terminate(); _ = await wait(4) { targetApp.isTerminated }; if !targetApp.isTerminated { targetApp.forceTerminate() } }
        if let targetApp { note("cleanup-tested-app", await wait(2) { targetApp.isTerminated }, "Tested instance stopped before installed app relaunch") }
        for fixture in fixtures.reversed() {
            if case .accessibility(let element) = fixture.window.target {
                AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
                _ = await wait(3) { axValue(element, kAXMinimizedAttribute) as? Bool != true }
            }
            if fixture.close, case .accessibility(let element) = fixture.window.target {
                _ = sheetButton(element, identifier: "CancelButton")
                await NativeWindows.pause(0.1)
            }
            do {
                try await native.setFrame(fixture.original, window: fixture.window)
                let restored = native.verifyFrame(fixture.original, window: fixture.window)
                cleanupResults.append("Restore \(fixture.window.bundleID): \(restored)")
                note("cleanup-restore", restored, fixture.window.bundleID)
            } catch { note("cleanup-restore", false, "\(fixture.window.bundleID): \(error.localizedDescription)") }
            if fixture.close, case .accessibility(let element) = fixture.window.target {
                closeWindow(element)
                await NativeWindows.pause(0.15)
                _ = sheetButton(element, identifier: "DontSaveButton")
                let closed = await wait(2) { self.native.currentFrame(fixture.window) == nil }
                note("cleanup-close", closed, "Fixture \(fixture.window.id)")
            }
        }
        if let textApp {
            textApp.terminate()
            note("cleanup-textedit", await wait(3) { textApp.isTerminated }, "Only the launched disposable TextEdit process")
        }
        if let hungApp {
            hungApp.terminate()
            note("cleanup-hang-fixture", await wait(3) { hungApp.isTerminated }, "Only the launched disposable fixture process")
        }
        _ = try? await process("/usr/bin/open", ["/Applications/DeskNames.app"])
        let restored = await wait(8) {
            NSRunningApplication.runningApplications(withBundleIdentifier: "local.desknames.app").contains {
                $0.bundleURL?.path == "/Applications/DeskNames.app" && !$0.isTerminated
            }
        }
        cleanupResults.append("Installed DeskNames running: \(restored)")
        note("cleanup-installed-app", restored, "Relaunched unchanged /Applications/DeskNames.app")
    }
}

@MainActor func runHotkeySoakTest(arguments: [String]) async -> Bool {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("desknames-hotkey-\(UUID().uuidString)")
    let journal = arguments.firstIndex(of: "--journal").flatMap { arguments.indices.contains($0+1) ? URL(fileURLWithPath: arguments[$0+1]) : nil }
    let test = HotkeySoakTest(directory: directory, journal: journal)
    do { try await test.run() }
    catch { test.note("precondition-or-run", false, error.localizedDescription) }
    await test.cleanup()
    let report = HotkeySoakTest.Report(trusted: AXIsProcessTrusted(), operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
        seed: test.seed, injectedPresses: test.pressCount, soakPresses: test.soakCount, storage: directory.path,
        observations: test.observations, cleanup: test.cleanupResults)
    var path = directory.appendingPathComponent("report.json")
    if let index = arguments.firstIndex(of: "--report"), arguments.indices.contains(index+1) { path = URL(fileURLWithPath: arguments[index+1]) }
    do {
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(to: path, options: .atomic)
        print("REPORT: \(path.path)")
    } catch { print("FAIL: report write: \(error)"); return false }
    return !test.observations.contains { $0.result == "FAIL" }
}

@MainActor func recoverHotkeySoak(at journal: URL) async -> Bool {
    guard let data = try? Data(contentsOf: journal),
          let recovery = try? JSONDecoder().decode(HotkeySoakTest.Recovery.self, from: data) else {
        print("FAIL: recovery journal missing or unreadable")
        return false
    }
    let test = HotkeySoakTest(directory: URL(fileURLWithPath: recovery.storage), journal: journal)
    test.hiddenApps = recovery.hiddenPIDs.compactMap(NSRunningApplication.init(processIdentifier:))
    if let pid = recovery.hungPID, let app = NSRunningApplication(processIdentifier: pid), app.bundleURL == Bundle.main.bundleURL {
        kill(pid, SIGCONT)
        test.hungApp = app
    }
    if let pid = recovery.externalPID, let app = NSRunningApplication(processIdentifier: pid), app.bundleURL == Bundle.main.bundleURL { test.externalApp = app }
    if let pid = recovery.targetPID, let app = NSRunningApplication(processIdentifier: pid), app.bundleURL == Bundle.main.bundleURL {
        test.targetApp = app
    }
    if let pid = recovery.textPID, let app = NSRunningApplication(processIdentifier: pid), app.bundleIdentifier == "com.apple.TextEdit" {
        kill(pid, SIGCONT)
        test.textApp = app
    }
    typealias WindowID = @convention(c) (AXUIElement, UnsafeMutablePointer<UInt32>) -> Int32
    if let symbol = dlsym(dlopen(nil, RTLD_NOW), "_AXUIElementGetWindow") {
        let getID = unsafeBitCast(symbol, to: WindowID.self)
        for saved in recovery.windows {
            guard let app = NSRunningApplication(processIdentifier: saved.pid), app.bundleIdentifier == saved.bundle else {
                if !saved.close { test.note("recovery-window", false, "Original application no longer running: \(saved.bundle)") }; continue
            }
            let element = test.axWindows(app).first { window in
                var id: UInt32 = 0
                return getID(window, &id) == 0 && id == saved.id
            }
            if saved.close, let element { AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanFalse) }
            guard let element else {
                if saved.close { continue }
                test.note("recovery-window", false, "Original window unavailable: \(saved.id)"); continue
            }
            let window = LiveWindow(id: saved.id, target: .accessibility(element), pid: saved.pid, bundleID: saved.bundle,
                appName: app.localizedName ?? saved.bundle, title: "", frame: saved.original.cg,
                spaceIDs: test.native.spaces(for: saved.id), minimized: false)
            test.fixtures.append(HotkeySoakTest.Fixture(app: app, window: window, original: saved.original.cg, close: saved.close))
        }
    } else { test.note("recovery-window", false, "Window identity API unavailable") }
    await test.cleanup()
    return !test.observations.contains { $0.result == "FAIL" }
}
