import AppKit
import Carbon

struct PaneDivider: Identifiable, Equatable {
    let id: String
    let vertical: Bool
    let position: Double
    let lower: Double
    let upper: Double
    let before: [Int]
    let after: [Int]

    static func all(for preset: PanePreset) -> [PaneDivider] {
        let regions = preset.regions
        return [true, false].flatMap { vertical -> [PaneDivider] in
            let positions = Set(regions.flatMap { vertical ? [$0.minX, $0.maxX] : [$0.minY, $0.maxY] }).sorted()
            return positions.indices.dropFirst().dropLast().map { i in
                let position = positions[i]
                return PaneDivider(id: "\(vertical ? "x" : "y")\(i)", vertical: vertical, position: position,
                    lower: positions[i-1], upper: positions[i+1],
                    before: regions.indices.filter { (vertical ? regions[$0].maxX : regions[$0].maxY) == position },
                    after: regions.indices.filter { (vertical ? regions[$0].minX : regions[$0].minY) == position })
            }
        }
    }

    func moved(to coordinate: CGFloat, in area: CGRect, configuration: PaneConfiguration) -> PaneConfiguration {
        let inset = area.insetBy(dx: configuration.gap/2, dy: configuration.gap/2)
        let length = vertical ? inset.width : inset.height
        guard length > 0, coordinate.isFinite else { return configuration }
        let minimum = max(0.05, ((vertical ? 180.0 : 120.0) + configuration.gap)/length)
        let lo = configuration.mapped(lower, vertical: vertical) + minimum
        let hi = configuration.mapped(upper, vertical: vertical) - minimum
        guard lo <= hi else { return configuration }
        let fraction = (coordinate - (vertical ? inset.minX : inset.minY))/length
        var next = configuration
        if next.splitPositions == nil { next.splitPositions = [:] }
        next.splitPositions?[id] = min(hi, max(lo, fraction))
        return next.sanitized
    }

    func handle(in geometry: PaneGeometry) -> CGRect? {
        guard let first = before.first, let second = after.first,
              geometry.cells.indices.contains(first), geometry.cells.indices.contains(second) else { return nil }
        let cells = (before + after).map { geometry.cells[$0] }
        let span = cells.reduce(cells[0]) { $0.union($1) }
        let a = geometry.cells[first], b = geometry.cells[second]
        if vertical { return CGRect(x: (a.maxX + b.minX)/2 - 4, y: span.midY - 30, width: 8, height: 60) }
        return CGRect(x: span.midX - 30, y: (a.maxY + b.minY)/2 - 4, width: 60, height: 8)
    }
}

extension PaneConfiguration {
    func withGap(_ value: Double) -> PaneConfiguration { var next = self; next.gap = value; return next }
    func mapped(_ value: Double, vertical: Bool) -> Double {
        guard let divider = PaneDivider.all(for: preset).first(where: { $0.vertical == vertical && $0.position == value }) else { return value }
        return splitPositions?[divider.id] ?? value
    }
    var regions: [CGRect] {
        guard splitPositions != nil else { return preset.regions }
        return preset.regions.map { region in
            let x = mapped(region.minX, vertical: true), y = mapped(region.minY, vertical: false)
            return CGRect(x: x, y: y, width: mapped(region.maxX, vertical: true) - x,
                          height: mapped(region.maxY, vertical: false) - y)
        }
    }
}

enum PaneShortcut {
    static let next: UInt32 = 300, previous: UInt32 = 301, toggleLinked: UInt32 = 302
    // Explicit IDs keep persisted bindings stable when presets are added or reordered.
    static let presets: [(UInt32, PanePreset, UInt32)] = [
        (310, .halves, 18), (311, .thirds, 19), (312, .fourColumns, 20),
        (313, .quarters, 21), (314, .rows, 23), (315, .wideLeft, 22), (316, .focus, 26)
    ]
    static let all: [ShortcutAction] = [
        ShortcutAction(id: next, name: "Next pane layout", suggested: ShortcutBinding(key: 30, modifiers: UInt32(controlKey | optionKey))),
        ShortcutAction(id: previous, name: "Previous pane layout", suggested: ShortcutBinding(key: 33, modifiers: UInt32(controlKey | optionKey))),
        ShortcutAction(id: toggleLinked, name: "Toggle linked pane resizing", suggested: ShortcutBinding(key: 29, modifiers: UInt32(controlKey | optionKey | cmdKey)))
    ] + zip(UInt32(320)...UInt32(323), [UInt32(122), 120, 99, 118]).map {
        ShortcutAction(id: $0.0, name: "Move window to pane \($0.0 - 319)", suggested: ShortcutBinding(key: $0.1, modifiers: UInt32(controlKey | optionKey)))
    } + presets.map { ShortcutAction(id: $0.0, name: "Pane layout: " + $0.1.name, suggested: ShortcutBinding(key: $0.2, modifiers: UInt32(controlKey | optionKey | cmdKey))) }

    static func preset(for id: UInt32, current: PanePreset) -> PanePreset? {
        if let direct = presets.first(where: { $0.0 == id }) { return direct.1 }
        guard id == next || id == previous, let index = PanePreset.allCases.firstIndex(of: current) else { return nil }
        let count = PanePreset.allCases.count
        return PanePreset.allCases[(index + (id == next ? 1 : count - 1)) % count]
    }
}

extension LayoutController {
    func setPaneConfiguration(_ config: PaneConfiguration, for desktop: Desktop) {
        if let display = ConnectedDisplay.all().first(where: { $0.id == desktop.display }),
           monitorPresets.values[display.profile.model]?.enabled == true {
            monitorPresets.set(display.profile, enabled: true, configuration: config)
        } else { panes.set(config, for: desktop.id) }
    }
    func performPaneShortcut(_ id: UInt32) {
        guard !busy || ((320...323).contains(id) && canRetargetPlacement) else { message = "Finish the window operation before changing pane layouts."; return }
        if id == PaneShortcut.toggleLinked {
            panes.setLinkedResizing(!panes.linkedResizing)
            message = panes.linkedResizing ? "Linked pane resizing on. Drag a handle between snapped windows." : "Linked pane resizing off."
            return
        }
        store.refresh()
        guard let desktop = native.activeDesktop(reader: store.reader), !desktop.id.isEmpty else {
            message = "No ordinary desktop is available for pane layouts."; return
        }
        let config = paneConfiguration(for: desktop.id)
        if (320...323).contains(id) {
            guard let candidate = native.focusedWindow(), let screen = screenFor(candidate.frame),
                  screenUUID(screen) == desktop.display else { message = "Focus a window on this desktop first."; return }
            let geometry = PaneGeometry(area: screenArea(screen), configuration: config, pixelScale: screen.backingScaleFactor)
            let index = Int(id - 320)
            guard geometry.cells.indices.contains(index) else { message = "This layout has only \(geometry.cells.count) panes."; return }
            run(interruptible: true) {
                guard let window = await self.native.refreshedForOperation(candidate), window.spaceIDs == [desktop.spaceID],
                      self.paneConfiguration(for: desktop.id) == config,
                      self.store.reader.read().contains(where: { $0.id == desktop.id && $0.isCurrent }) else {
                    throw WindowIssue("The window or desktop changed. Try again.")
                }
                self.frameHistory.remember(window, frame: window.frame, screen: screen)
                try await self.native.animateFrames([(window, geometry.cells[index])])
                guard self.native.verifyFrame(geometry.cells[index], window: window) else { return "The window needs a larger pane." }
                self.frameHistory.remember(window, frame: window.frame, screen: screen)
                return "Moved \(window.appName) to pane \(index + 1)."
            }
            return
        }
        guard let preset = PaneShortcut.preset(for: id, current: config.preset) else { return }
        setPaneConfiguration(PaneConfiguration(preset: preset, gap: config.gap), for: desktop)
        message = "Pane layout: \(preset.name)."
        previewPanes?(desktop.id)
    }
}

struct WindowTransition {
    static func frame(from start: CGRect, to end: CGRect, progress: Double) -> CGRect {
        let t = min(1, max(0, progress))
        let eased = 1 - pow(1-t, 3)
        func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b-a)*eased }
        return CGRect(x: mix(start.minX, end.minX), y: mix(start.minY, end.minY),
                      width: mix(start.width, end.width), height: mix(start.height, end.height))
    }
    static func duration(from start: CGRect, to end: CGRect, in area: CGRect) -> TimeInterval {
        let distance = max(hypot(end.minX-start.minX, end.minY-start.minY), hypot(end.maxX-start.maxX, end.maxY-start.maxY))
        let fraction = min(1, distance / max(1, hypot(area.width, area.height)))
        return 0.12 + 0.12*sqrt(fraction)
    }
    static func pixelAligned(_ rect: CGRect, scale: CGFloat) -> CGRect {
        func pixel(_ value: CGFloat) -> CGFloat { (value*scale).rounded()/scale }
        let x = pixel(rect.minX), y = pixel(rect.minY)
        return CGRect(x: x, y: y, width: pixel(rect.maxX)-x, height: pixel(rect.maxY)-y)
    }
    static func delay(now: TimeInterval, started: TimeInterval, interval: TimeInterval) -> TimeInterval {
        let next = started + (floor((now-started)/interval)+1)*interval
        return max(0, next-now)
    }
}

extension NativeWindows {
    @MainActor func writeTransitionFrame(_ frame: CGRect, window: LiveWindow) async throws {
        try Task.checkCancellation()
        guard trusted, PaneGeometry.valid(frame) else { throw WindowIssue("The window is no longer available for resizing.") }
        switch window.target {
        case .local(let local):
            guard local.isVisible, local.windowNumber == Int(window.id) else { throw WindowIssue("The window closed while resizing.") }
            let minimum = local.frameRect(forContentRect: CGRect(origin: .zero, size: local.contentMinSize)).size
            guard frame.width >= minimum.width, frame.height >= minimum.height else { throw WindowIssue("The window needs a larger pane.") }
            let top = NSScreen.screens.first?.frame.maxY ?? 0
            local.setFrame(CGRect(x: frame.minX, y: top-frame.maxY, width: frame.width, height: frame.height), display: true)
        case .accessibility:
            let result = await accessibilityWrite(window, .frame(frame), reuseValidatedElement: true)
            try Task.checkCancellation()
            guard result == .success || result == .cannotComplete else { throw WindowIssue("\(window.appName) could not resize its window.") }
        }
    }

    @MainActor func writeTransitionFrames(_ targets: [(LiveWindow, CGRect)]) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            for (window, frame) in targets {
                group.addTask { @MainActor in try await self.writeTransitionFrame(frame, window: window) }
            }
            try await group.waitForAll()
        }
    }

    @MainActor func animateFrames(_ targets: [(LiveWindow, CGRect)], duration requestedDuration: Double? = nil) async throws {
        let starts = targets.map { actualFrame($0.0) ?? $0.0.frame }
        let screens = targets.map { screenFor($0.1) }
        let scales = screens.map { $0?.backingScaleFactor ?? 1 }
        let destinations = targets.enumerated().map { WindowTransition.pixelAligned($0.element.1, scale: scales[$0.offset]) }
        let duration = requestedDuration ?? targets.indices.map {
            WindowTransition.duration(from: starts[$0], to: destinations[$0], in: screens[$0].map(screenArea) ?? destinations[$0])
        }.max() ?? 0
        let interval = screens.compactMap { $0 }.map { 1.0/Double(($0.maximumFramesPerSecond > 0 ? $0.maximumFramesPerSecond : 60)) }.min() ?? 1.0/60
        let topology = NSScreen.screens.map { [$0.frame, $0.visibleFrame] }
        let startedAt = ProcessInfo.processInfo.systemUptime
        var batches = 0
        var compatibilityFallback = false
        var beforeFallback: [[String: Double]] = []
        defer {
            recordWindowDiagnostic("window-motion-result.json", [
                "elapsedSeconds": ProcessInfo.processInfo.systemUptime-startedAt,
                "plannedSeconds": duration, "frameIntervalSeconds": interval,
                "frameBatches": batches, "windows": targets.count,
                "compatibilityFallback": compatibilityFallback, "cancelled": Task.isCancelled,
                "beforeFallback": beforeFallback
            ])
        }
        var last = starts
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, duration > 0 {
            let started = ProcessInfo.processInfo.systemUptime
            while true {
                try Task.checkCancellation()
                guard NSScreen.screens.map({ [$0.frame, $0.visibleFrame] }) == topology else { throw CancellationError() }
                let progress = (ProcessInfo.processInfo.systemUptime-started)/duration
                if progress >= 1 { break }
                var updates: [(LiveWindow, CGRect)] = []
                for index in targets.indices {
                    let frame = WindowTransition.pixelAligned(WindowTransition.frame(from: starts[index], to: destinations[index], progress: progress), scale: scales[index])
                    if frame != last[index] { updates.append((targets[index].0, frame)); last[index] = frame }
                }
                do {
                    if !updates.isEmpty { batches += 1 }
                    try await writeTransitionFrames(updates)
                }
                catch is CancellationError { throw CancellationError() }
                catch {
                    compatibilityFallback = true
                    for (window, frame) in targets { try await setFrame(frame, window: window) }
                    return
                }
                let delay = WindowTransition.delay(now: ProcessInfo.processInfo.systemUptime, started: started, interval: interval)
                try await Task.sleep(nanoseconds: UInt64(delay*1_000_000_000))
            }
        }
        guard NSScreen.screens.map({ [$0.frame, $0.visibleFrame] }) == topology else { throw CancellationError() }
        batches += 1
        do { try await writeTransitionFrames(targets.indices.map { (targets[$0].0, destinations[$0]) }) }
        catch is CancellationError { throw CancellationError() }
        catch {
            compatibilityFallback = true
            for index in targets.indices { try await setFrame(destinations[index], window: targets[index].0) }
            return
        }
        // Give accepted writes a few display frames to appear before using the compatibility retry path.
        for _ in 0..<3 {
            try Task.checkCancellation()
            if targets.indices.allSatisfy({ verifyFrame(destinations[$0], window: targets[$0].0) }) { return }
            try await Task.sleep(nanoseconds: UInt64(interval*1_000_000_000))
        }
        for index in targets.indices where !verifyFrame(destinations[index], window: targets[index].0) {
            if let actual = actualFrame(targets[index].0) {
                let expected = destinations[index]
                beforeFallback.append(["xError": actual.minX-expected.minX, "yError": actual.minY-expected.minY,
                                       "widthError": actual.width-expected.width, "heightError": actual.height-expected.height])
            }
            compatibilityFallback = true
            try await setFrame(destinations[index], window: targets[index].0)
        }
    }
}
