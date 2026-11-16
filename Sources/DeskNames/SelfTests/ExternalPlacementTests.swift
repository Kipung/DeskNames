import AppKit
import Carbon

@MainActor final class ExternalPlacementTest {
    struct Step: Codable {
        let name: String
        let target: SavedRect?
        let actual: SavedRect?
        let result: String
        let reason: String
        let elapsedSeconds: Double
        let writes: [Write]
        var eligibility = "eligible"
        var refusal: String?
        var attributes: [String: String] = [:]
    }
    struct Write: Codable {
        let windowID: UInt32
        let operation: String
        let error: Int32
    }
    struct ApplicationResult: Codable {
        let bundleID: String
        var windowID: UInt32?
        var original: SavedRect?
        var metadata: [String: String] = [:]
        var finalMetadata: [String: String] = [:]
        var steps: [Step] = []
    }
    struct Report: Codable {
        let trusted: Bool
        let operatingSystem: String
        let storage: String
        var applications: [ApplicationResult]
    }
    let directory: URL
    let domain = "local.desknames.external-test.\(UUID().uuidString)"
    let defaults: UserDefaults
    let native: NativeWindows
    let workspace: LayoutController
    var writes: [Write] = []

    init(directory: URL) {
        self.directory = directory
        defaults = UserDefaults(suiteName: domain)!
        native = NativeWindows(diagnosticsDirectory: directory)
        workspace = LayoutController(store: Store(defaults: defaults), file: directory.appendingPathComponent("layouts.json"), native: native)
        native.observeWrite = { [weak self] id, operation, error in
            self?.writes.append(Write(windowID: id, operation: operation, error: error))
        }
    }

    static func serverWindows() -> [(id: UInt32, pid: pid_t, frame: CGRect, layer: Int)] {
        (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []).compactMap { row in
            guard let id = row[kCGWindowNumber as String] as? UInt32,
                  let pid = row[kCGWindowOwnerPID as String] as? pid_t,
                  let bounds = row[kCGWindowBounds as String] as? [String: Any],
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  (row[kCGWindowAlpha as String] as? Double ?? 1) > 0 else { return nil }
            return (id, pid, frame, row[kCGWindowLayer as String] as? Int ?? 0)
        }
    }

    func metadata(pid: pid_t, id: UInt32) -> [String: String] {
        var result: [String: String] = [:]
        let stack = Self.serverWindows().filter { $0.pid == pid }
        result["WindowServer.order"] = stack.map { "\($0.id):layer=\($0.layer):\($0.frame)" }.joined(separator: "; ")
        result["shortcutIdentity"] = native.frontmostWindowIdentity().map { String($0.id) } ?? "missing"
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.2)
        for name in ["AXFocusedWindow", "AXMainWindow", "AXWindows", "AXEnhancedUserInterface", "AXManualAccessibility"] {
            var value: CFTypeRef?
            let error = AXUIElementCopyAttributeValue(app, name as CFString, &value)
            result[name + ".error"] = String(error.rawValue)
            if let flag = value as? Bool { result[name] = String(flag) }
        }
        typealias GetID = @convention(c)(AXUIElement, UnsafeMutablePointer<UInt32>) -> Int32
        guard let symbol = dlsym(dlopen(nil, RTLD_NOW), "_AXUIElementGetWindow") else { return result }
        let getID = unsafeBitCast(symbol, to: GetID.self)
        for element in axValue(app, kAXWindowsAttribute) as? [AXUIElement] ?? [] {
            var candidate: UInt32 = 0
            AXUIElementSetMessagingTimeout(element, 0.1)
            guard getID(element, &candidate) == 0, candidate == id else { continue }
            let info = NativeWindows.eligibilityMetadata(element, readAttribute: { target, name in
                var value: CFTypeRef?
                let error = AXUIElementCopyAttributeValue(target, name as CFString, &value)
                let key = CFEqual(target, element) ? name : "child." + name
                result[key + ".error"] = String(error.rawValue)
                if [kAXRoleAttribute, kAXSubroleAttribute].contains(name), let text = value as? String { result[key] = text }
                return (error, value)
            })
            result["eligibility"] = info.refusal(for: .operation) ?? "eligible"
            for name in [kAXPositionAttribute, kAXSizeAttribute] {
                var settable = DarwinBoolean(false)
                result[name + ".settableError"] = String(AXUIElementIsAttributeSettable(element, name as CFString, &settable).rawValue)
                result[name + ".settable"] = String(settable.boolValue)
            }
        }
        return result
    }

    func settle() async -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + 20
        while workspace.busy && ProcessInfo.processInfo.systemUptime < deadline { await NativeWindows.pause(0.02) }
        if workspace.busy {
            workspace.cancel()
            await workspace.operationTask?.value
            return false
        }
        return true
    }

    func step(_ name: String, window: LiveWindow, target: CGRect, action: () async -> Void) async -> Step {
        writes = []
        let start = ProcessInfo.processInfo.systemUptime
        await action()
        let completed = await settle()
        await NativeWindows.pause(0.15)
        let actual = native.currentFrame(window)
        var value = Step(name: name, target: SavedRect(target), actual: actual.map(SavedRect.init),
                    result: completed && native.verifyFrame(target, window: window) ? "PASS" : "FAIL",
                    reason: workspace.message, elapsedSeconds: ProcessInfo.processInfo.systemUptime - start, writes: writes)
        value.attributes = metadata(pid: window.pid, id: window.id)
        value.eligibility = value.attributes["eligibility"] ?? "unconfirmed"
        if value.result != "PASS" { value.refusal = completed ? workspace.message : "operation-timeout" }
        return value
    }

    func test(_ bundle: String) async -> ApplicationResult {
        var result = ApplicationResult(bundleID: bundle)
        func refusal(_ reason: String) -> ApplicationResult {
            var step = Step(name: "precondition", target: nil, actual: nil, result: "UNAVAILABLE", reason: reason, elapsedSeconds: 0, writes: [])
            step.eligibility = "unconfirmed"; step.refusal = reason; step.attributes = result.metadata
            result.steps.append(step)
            return result
        }
        var app = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first
        if app == nil {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else { return refusal("Application is not installed.") }
            let config = NSWorkspace.OpenConfiguration()
            config.activates = false
            NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in }
            for _ in 0..<100 {
                app = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first
                if app != nil { break }
                await NativeWindows.pause(0.1)
            }
        }
        guard let app else { return refusal("Application did not launch within ten seconds.") }
        let pid = app.processIdentifier
        var visible = Self.serverWindows().first { $0.pid == pid && $0.layer == 0 && $0.frame.width > 80 && $0.frame.height > 50 }
        for _ in 0..<50 where visible == nil {
            await NativeWindows.pause(0.1)
            visible = Self.serverWindows().first { $0.pid == pid && $0.layer == 0 && $0.frame.width > 80 && $0.frame.height > 50 }
        }
        guard visible != nil else { return refusal("No on-screen window on the current desktop. No desktop switch attempted.") }
        let desktops = Set(workspace.store.reader.read().filter(\.isCurrent).map(\.spaceID))
        let applicationElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(applicationElement, 0.2)
        if let focused = axValue(applicationElement, kAXFocusedWindowAttribute) ?? axValue(applicationElement, kAXMainWindowAttribute),
           CFGetTypeID(focused) == AXUIElementGetTypeID() {
            let element = unsafeBitCast(focused, to: AXUIElement.self)
            typealias GetID = @convention(c)(AXUIElement, UnsafeMutablePointer<UInt32>) -> Int32
            guard let symbol = dlsym(dlopen(nil, RTLD_NOW), "_AXUIElementGetWindow") else { return refusal("Cannot validate activation window identity.") }
            var focusedID: UInt32 = 0
            guard unsafeBitCast(symbol, to: GetID.self)(element, &focusedID) == 0,
                  Self.serverWindows().contains(where: { $0.id == focusedID && $0.pid == pid }) else {
                return refusal("Activation could select an off-screen window; no activation attempted.")
            }
        } else if NSWorkspace.shared.frontmostApplication?.processIdentifier != pid {
            return refusal("Cannot establish an on-screen focused/main window before activation.")
        }
        app.activate(options: [])
        for _ in 0..<40 {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == pid { break }
            await NativeWindows.pause(0.05)
        }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return refusal("Application activation did not complete.") }
        guard Set(workspace.store.reader.read().filter(\.isCurrent).map(\.spaceID)) == desktops else { return refusal("Activation changed the current desktop; no placement attempted.") }
        let start = ProcessInfo.processInfo.systemUptime
        var reason = ""
        guard let window = await native.focusedWindowForOperation(onFailure: { reason = $0 }) else {
            if let visible { result.windowID = visible.id; result.metadata = metadata(pid: pid, id: visible.id) }
            return refusal("Focused discovery refused: \(reason)")
        }
        guard window.pid == pid, let original = native.currentFrame(window), let screen = screenFor(original),
              let desktop = workspace.store.reader.read().first(where: { $0.isCurrent && !$0.isFullScreen && $0.display == screenUUID(screen) }),
              window.spaceIDs.contains(desktop.spaceID) else { return refusal("Focused window is not on the current ordinary desktop.") }
        result.windowID = window.id
        result.original = SavedRect(original)
        result.metadata = metadata(pid: pid, id: window.id)
        result.steps.append(Step(name: "focused-discovery", target: SavedRect(original), actual: SavedRect(original), result: "PASS", reason: "eligible; exact WindowServer identity", elapsedSeconds: ProcessInfo.processInfo.systemUptime - start, writes: []))
        result.steps[result.steps.count - 1].attributes = result.metadata
        workspace.setPaneConfiguration(PaneConfiguration(preset: .fourColumns, gap: 0), for: desktop)
        let geometry = PaneGeometry(area: screenArea(screen), configuration: PaneConfiguration(preset: .fourColumns, gap: 0), pixelScale: screen.backingScaleFactor)
        let modifiers = UInt32(controlKey | optionKey)
        for index in 0..<4 {
            workspace.paneRangeChord.reset()
            result.steps.append(await step("pane-\(index + 1)", window: window, target: geometry.cells[index]) {
                workspace.performPaneShortcut(UInt32(320 + index), modifiers: modifiers)
            })
        }
        for (first, last, settled) in [(2, 3, false), (3, 1, false), (2, 3, true), (3, 1, true)] {
            workspace.paneRangeChord.reset()
            result.steps.append(await step("range-\(first + 1)-\(last + 1)\(settled ? "-settled" : "")", window: window, target: geometry.frame(spanning: min(first, last)...max(first, last))!) {
                workspace.performPaneShortcut(UInt32(320 + first), modifiers: modifiers)
                if settled { _ = await settle() }
                workspace.performPaneShortcut(UInt32(320 + last), modifiers: modifiers)
            })
        }
        workspace.paneRangeChord.reset()
        for action in [WindowAction.left, .right, .maximize] {
            let target = action.frame(in: screenArea(screen), current: original, configuration: PaneConfiguration(preset: .fourColumns, gap: 0), pixelScale: screen.backingScaleFactor)!
            result.steps.append(await step(action.name, window: window, target: target) { workspace.performWindowAction(action, focused: true) })
        }
        let pointStart = ProcessInfo.processInfo.systemUptime
        let frame = native.currentFrame(window) ?? original
        let point = CGPoint(x: frame.midX, y: frame.minY + 12)
        let capture = native.captureWindow(at: point)
        let pointed = if let capture { await native.windowForOperation(capture) } else { nil as LiveWindow? }
        result.steps.append(Step(name: "pointer-discovery", target: SavedRect(frame), actual: pointed.flatMap { native.currentFrame($0) }.map(SavedRect.init), result: pointed?.id == window.id && pointed?.pid == pid ? "PASS" : "FAIL", reason: "Command-drag captureWindow/windowForOperation at title-bar point \(point)", elapsedSeconds: ProcessInfo.processInfo.systemUptime - pointStart, writes: []))
        result.steps[result.steps.count - 1].attributes = metadata(pid: pid, id: window.id)
        if pointed?.id != window.id || pointed?.pid != pid {
            result.steps[result.steps.count - 1].eligibility = "unconfirmed"
            result.steps[result.steps.count - 1].refusal = "pointer-identity-unavailable"
        }
        result.steps.append(await step("restore", window: window, target: original) {
            do { try await native.withImmediateFrames([window]) { try await native.setFrame(original, window: window) }; workspace.message = "Original WindowServer frame restored." }
            catch { workspace.message = error.localizedDescription }
        })
        result.finalMetadata = metadata(pid: pid, id: window.id)
        let modes = ["AXEnhancedUserInterface", "AXManualAccessibility"]
        let unchanged = modes.allSatisfy { result.metadata[$0] == result.finalMetadata[$0] }
        result.steps.append(Step(name: "accessibility-modes", target: SavedRect(original), actual: native.currentFrame(window).map(SavedRect.init), result: unchanged ? "PASS" : "FAIL", reason: unchanged ? "Enhanced UI and Manual Accessibility unchanged." : "Accessibility mode changed during placement.", elapsedSeconds: 0, writes: []))
        result.steps[result.steps.count - 1].attributes = result.finalMetadata
        return result
    }

    func run(_ bundles: [String], reportURL: URL) async throws -> Bool {
        defer { native.observeWrite = nil; defaults.removePersistentDomain(forName: domain) }
        var report = Report(trusted: native.trusted, operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString, storage: directory.path, applications: [])
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        func save() throws { try encoder.encode(report).write(to: reportURL, options: .atomic) }
        guard native.trusted else { try save(); throw WindowIssue("Build copy is not Accessibility trusted. Launch the release-signed app through LaunchServices; do not reset TCC.") }
        for bundle in bundles {
            let result = await test(bundle)
            report.applications.append(result)
            try save()
            for step in result.steps {
                func frame(_ value: SavedRect?) -> String {
                    guard let value else { return "-" }
                    return "\(Int(value.x)),\(Int(value.y)) \(Int(value.width))×\(Int(value.height))"
                }
                let errors = Set(step.writes.map(\.error)).sorted().map(String.init).joined(separator: ",")
                print("\(bundle)\t\(step.name)\t\(step.result)\t\(frame(step.target)) -> \(frame(step.actual))\tAX[\(errors)]\t\(step.eligibility)\t\(String(format: "%.3fs", step.elapsedSeconds))\t\(step.reason)")
            }
            fflush(stdout)
        }
        return report.applications.allSatisfy { $0.steps.allSatisfy { $0.result == "PASS" } }
    }
}

@MainActor func runExternalPlacementTests(arguments: [String]) async throws -> Bool {
    guard let index = arguments.firstIndex(of: "--external-placement-test"), arguments.count > index + 1,
          !arguments[index + 1].hasPrefix("--") else { throw WindowIssue("Expected comma-separated bundle IDs after --external-placement-test.") }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DeskNames-external-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    var reportURL = directory.appendingPathComponent("report.json")
    if let i = arguments.firstIndex(of: "--report") {
        guard arguments.count > i + 1 else { throw WindowIssue("Expected a path after --report.") }
        reportURL = URL(fileURLWithPath: arguments[i + 1])
    }
    print("External placement report: \(reportURL.path)")
    return try await ExternalPlacementTest(directory: directory).run(arguments[index + 1].split(separator: ",").map(String.init), reportURL: reportURL)
}

@MainActor func runExternalDividerTest(arguments: [String]) async throws {
    guard let index = arguments.firstIndex(of: "--external-divider-test"), arguments.count > index + 1 else { throw WindowIssue("Expected three fixture WindowServer IDs.") }
    let ids = arguments[index + 1].split(separator: ",").compactMap { UInt32($0) }
    guard ids.count == 3, Set(ids).count == 3 else { throw WindowIssue("Expected three distinct fixture IDs.") }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DeskNames-divider-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let test = ExternalPlacementTest(directory: directory)
    defer { test.defaults.removePersistentDomain(forName: test.domain) }
    guard test.native.trusted else { throw WindowIssue("Build copy is not Accessibility trusted; no TCC changes attempted.") }
    let census = await test.native.windowsForOperation()
    let windows = ids.compactMap { id in census.first { $0.id == id && $0.bundleID == "com.apple.finder" } }
    guard windows.count == 3, let screen = screenFor(windows[0].frame),
          let desktop = test.workspace.store.desktops.first(where: { $0.isCurrent && !$0.isFullScreen && $0.display == screenUUID(screen) }),
          windows.allSatisfy({ $0.spaceIDs == [desktop.spaceID] }) else { throw WindowIssue("Three Finder fixture windows on the current desktop are required.") }
    let originals = windows.map { test.native.currentFrame($0)! }
    let linked = LinkedPaneController(workspace: test.workspace)
    defer { linked.stop() }
    var observations: [[String: Any]] = []
    var failure: Error?
    func observe(_ name: String) -> [String: Any] {
        let stack = ExternalPlacementTest.serverWindows()
        let handles = linked.handleWindowNumbersForTesting.map(UInt32.init)
        return ["step": name, "windows": stack.enumerated().filter { ids.contains($0.element.id) || handles.contains($0.element.id) }.map { rank, row in
            ["id": row.id, "pid": row.pid, "layer": row.layer, "rank": rank, "isHandle": handles.contains(row.id),
             "frame": [row.frame.minX, row.frame.minY, row.frame.width, row.frame.height]] as [String: Any]
        }]
    }
    do {
        let area = screenArea(screen)
        test.workspace.setPaneConfiguration(PaneConfiguration(preset: .halves, gap: 0), for: desktop)
        test.workspace.panes.setLinkedResizing(true)
        for (window, action) in zip(windows.prefix(2), [WindowAction.left, .right]) {
            test.workspace.windows = windows; test.workspace.selectedWindow = window.id
            test.workspace.performWindowAction(action)
            guard await test.settle(), test.native.verifyFrame(action.frame(in: area, current: window.frame)!, window: window) else { throw WindowIssue("Fixture half placement failed.") }
            _ = await test.native.accessibilityWrite(window, .raise)
        }
        for _ in 0..<100 {
            linked.tick()
            let stack = ExternalPlacementTest.serverWindows()
            if linked.handleWindowNumbersForTesting.contains(where: { number in stack.contains { $0.id == UInt32(number) } }) { break }
            await NativeWindows.pause(0.1)
        }
        let stack = ExternalPlacementTest.serverWindows()
        let handles = Set(linked.handleWindowNumbersForTesting.map(UInt32.init))
        guard let handleRank = stack.firstIndex(where: { handles.contains($0.id) && abs($0.frame.midX - area.midX) < 10 }),
              stack[handleRank].layer == 0,
              let leftRank = stack.firstIndex(where: { $0.id == windows[0].id }),
              let rightRank = stack.firstIndex(where: { $0.id == windows[1].id }), handleRank < min(leftRank, rightRank) else {
            observations.append(observe("missing-or-misordered")); throw WindowIssue("No normal-level divider above both real Finder neighbors.")
        }
        observations.append(observe("visible"))
        let handleID = stack[handleRank].id
        let cover = CGRect(x: area.midX - 400, y: area.midY - 300, width: 800, height: 600)
        try await test.native.animateFrames([(windows[2], cover)])
        _ = await test.native.accessibilityWrite(windows[2], .raise)
        await NativeWindows.pause(0.2)
        linked.tick()
        await NativeWindows.pause(0.1)
        let covered = ExternalPlacementTest.serverWindows()
        observations.append(observe("covered"))
        let currentHandles = Set(linked.handleWindowNumbersForTesting.map(UInt32.init))
        guard test.native.verifyFrame(cover, window: windows[2]), cover.contains(stack[handleRank].frame),
              !covered.contains(where: { currentHandles.contains($0.id) && $0.frame.intersects(stack[handleRank].frame) }),
              let coverRank = covered.firstIndex(where: { $0.id == windows[2].id }),
              let neighborRank = covered.firstIndex(where: { $0.id == windows[0].id }),
              let otherRank = covered.firstIndex(where: { $0.id == windows[1].id }), coverRank < min(neighborRank, otherRank) else {
            throw WindowIssue("Covering the seam did not hide its divider.")
        }
        _ = await test.native.accessibilityWrite(windows[0], .raise)
        _ = await test.native.accessibilityWrite(windows[1], .raise)
        for _ in 0..<30 { linked.tick(); await NativeWindows.pause(0.1) }
        observations.append(observe("uncovered"))
        guard ExternalPlacementTest.serverWindows().contains(where: { $0.id == handleID && $0.layer == 0 }) else { throw WindowIssue("Divider did not return after uncovering the seam.") }
    } catch { failure = error }
    linked.stop()
    var restored = true
    for (window, original) in zip(windows, originals) {
        do { try await test.native.setFrame(original, window: window) } catch { restored = false }
        restored = restored && test.native.verifyFrame(original, window: window)
    }
    let report: [String: Any] = ["trusted": true, "passed": failure == nil && restored, "restored": restored,
                                "reason": failure?.localizedDescription ?? "Normal-level divider appeared, hid under a real cover, and reappeared.", "observations": observations]
    let reportURL: URL
    if let i = arguments.firstIndex(of: "--report"), arguments.count > i + 1 { reportURL = URL(fileURLWithPath: arguments[i + 1]) }
    else { reportURL = directory.appendingPathComponent("report.json") }
    try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: reportURL)
    if let failure { throw failure }
    guard restored else { throw WindowIssue("Divider fixture original-frame restoration failed.") }
    print("PASS: real Finder neighbors, normal-level WindowServer order, covering-window hide and uncover recovery. Report: \(reportURL.path)")
}
