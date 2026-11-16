import AppKit
import Carbon

@MainActor func runPaneRangeTests() throws {
    let area = CGRect(x: -1920, y: -1080, width: 1920, height: 1040)
    let geometry = PaneGeometry(area: area, configuration: PaneConfiguration(preset: .fourColumns, gap: 12))
    let modifiers = UInt32(controlKey | optionKey | cmdKey)
    func context(id: UInt32 = 10, pid: Int32 = 20, desktop: String = "desktop", space: UInt64 = 30,
                 display: String = "display", geometry: PaneGeometry = geometry) -> PaneRangeChord.Context {
        .init(window: .init(id: id, pid: pid), desktopID: desktop, spaceID: space, displayID: display, geometry: geometry)
    }
    var chord = PaneRangeChord()
    let original = context()
    precondition(chord.press(2, modifiers: modifiers, context: original) == 2...2, "The first press places immediately")
    precondition(chord.press(3, modifiers: modifiers, context: original) == 2...3)
    precondition(chord.press(0, modifiers: modifiers, context: original) == 0...2, "Each endpoint uses the original anchor")
    precondition(chord.press(2, modifiers: modifiers, context: original) == 2...2)
    chord.reset()
    precondition(chord.press(3, modifiers: modifiers, context: original) == 3...3)
    precondition(chord.press(2, modifiers: modifiers, context: original) == 2...3, "Reverse order has the same span")
    chord.reset()
    precondition(chord.press(1, modifiers: modifiers, context: original) == 1...1)
    precondition(chord.press(3, modifiers: modifiers, context: original) == 1...3, "Skipped panes are included")
    for released in [UInt32(0), modifiers & ~UInt32(cmdKey), modifiers | UInt32(shiftKey)] {
        chord.modifiersChanged(released)
        chord.modifiersChanged(modifiers)
        precondition(chord.press(0, modifiers: modifiers, context: original) == 0...0, "Release and repress starts fresh")
        precondition(chord.press(3, modifiers: modifiers, context: original) == 0...3)
    }
    for changed in [context(id: 11), context(pid: 21), context(desktop: "other"), context(space: 31), context(display: "other"),
                    context(geometry: PaneGeometry(area: area, configuration: PaneConfiguration(preset: .thirds)))] {
        chord.reset()
        _ = chord.press(0, modifiers: modifiers, context: original)
        precondition(chord.press(2, modifiers: modifiers, context: changed) == 2...2, "Context changes start a new anchor")
        chord.observe(original)
        precondition(chord.anchor == nil, "Changing away and back expires the observed session")
    }
    _ = chord.press(0, modifiers: modifiers, context: original)
    chord.observe(nil)
    precondition(chord.anchor == nil)
    precondition(chord.press(-1, modifiers: modifiers, context: original) == nil)
    precondition(chord.press(4, modifiers: modifiers, context: original) == nil)
    precondition(chord.press(0, modifiers: 0, context: original) == 0...0 && chord.anchor == nil)
    _ = chord.press(0, modifiers: modifiers, context: original)
    precondition(chord.press(3, modifiers: UInt32(optionKey), context: original) == 3...3)

    for preset in PanePreset.allCases {
        for gap in [0.0, 12.0, 32.0] {
            for scale in [1.0, 2.0] {
                var config = PaneConfiguration(preset: preset, gap: gap)
                if let divider = PaneDivider.all(for: preset).first {
                    config = divider.moved(to: divider.vertical ? area.midX + 70 : area.midY + 70, in: area, configuration: config)
                }
                let grid = PaneGeometry(area: area, configuration: config, pixelScale: scale)
                for anchor in grid.cells.indices {
                    for endpoint in grid.cells.indices {
                        var sequence = PaneRangeChord()
                        let environment = context(geometry: grid)
                        _ = sequence.press(anchor, modifiers: modifiers, context: environment)
                        let range = sequence.press(endpoint, modifiers: modifiers, context: environment)!
                        let selected = Array(grid.cells[range])
                        let expected = CGRect(x: selected.map(\.minX).min()!, y: selected.map(\.minY).min()!,
                                              width: selected.map(\.maxX).max()! - selected.map(\.minX).min()!,
                                              height: selected.map(\.maxY).max()! - selected.map(\.minY).min()!)
                        precondition(grid.frame(spanning: range) == expected && area.contains(expected))
                    }
                }
            }
        }
    }
    let span = geometry.frame(spanning: 2...3)!
    precondition(span.width == geometry.cells[2].width + 12 + geometry.cells[3].width, "Spans include the gap")
    precondition(geometry.frame(spanning: 0...4) == nil && geometry.frame(spanning: -1...0) == nil)
    let quarters = PaneGeometry(area: area, configuration: PaneConfiguration(preset: .quarters, gap: 12))
    precondition(quarters.frame(spanning: 1...2) == quarters.frame(spanning: 0...3), "Diagonal cells use their bounding rectangle")

    let target = AXUIElementCreateApplication(getpid())
    func window(_ id: UInt32, _ frame: CGRect, space: [UInt64] = [30], minimized: Bool = false) -> LiveWindow {
        LiveWindow(id: id, target: .accessibility(target), pid: 20, bundleID: "test", appName: "Test", title: "Test",
                   frame: frame, spaceIDs: space, minimized: minimized)
    }
    let windows = [window(1, geometry.cells[0]), window(2, geometry.cells[1]), window(3, span)]
    let occupants = PaneOccupancy.matching(windows, geometry: geometry, spaceID: 30)
    precondition(occupants.count == 3 && occupants.first { $0.window.id == 3 }?.panes == [2, 3])
    let dividers = PaneDivider.all(for: .fourColumns)
    precondition(PaneOccupancy.participants(for: dividers[2], occupants: occupants).isEmpty, "No divider inside a spanning window")
    let participants = PaneOccupancy.participants(for: dividers[1], occupants: occupants)
    precondition(participants.count == 2 && Set(participants.map { $0.window.id }) == [2, 3], "A span is one resize participant")
    let resized = PaneGeometry(area: area, configuration: dividers[1].moved(to: area.midX + 80, in: area,
                                                                          configuration: PaneConfiguration(preset: .fourColumns, gap: 12)))
    precondition(participants.first { $0.window.id == 3 }?.frame(in: resized) == resized.frame(spanning: 2...3))
    let ambiguous = PaneOccupancy.matching(windows + [window(4, geometry.cells[2])], geometry: geometry, spaceID: 30)
    precondition(ambiguous.map { $0.window.id } == [1, 2], "Overlapping matches exclude the whole span")
    let ignored = [window(5, span, minimized: true), window(6, span, space: [31]), window(7, span, space: [30, 31])]
    precondition(PaneOccupancy.matching(ignored, geometry: geometry, spaceID: 30).isEmpty)
    let row = quarters.frame(spanning: 0...1)!
    let rowOccupants = PaneOccupancy.matching([window(1, row), window(2, quarters.cells[2]), window(3, quarters.cells[3])], geometry: quarters, spaceID: 30)
    let quarterDividers = PaneDivider.all(for: .quarters)
    precondition(PaneOccupancy.participants(for: quarterDividers.first { $0.vertical }!, occupants: rowOccupants).isEmpty)
    precondition(PaneOccupancy.participants(for: quarterDividers.first { !$0.vertical }!, occupants: rowOccupants).count == 3)
    let full = PaneOccupancy.matching([window(1, quarters.frame(spanning: 1...2)!)], geometry: quarters, spaceID: 30)
    precondition(full.count == 1 && full[0].panes == [0, 1, 2, 3])
    precondition(quarterDividers.allSatisfy { PaneOccupancy.participants(for: $0, occupants: full).isEmpty })
    let halves = PaneGeometry(area: area, configuration: PaneConfiguration(preset: .halves, gap: 12))
    let inferred = PaneOccupancy.matching([window(1, geometry.frame(spanning: 0...1)!), window(2, span)], geometry: halves, spaceID: 30)
    precondition(inferred.count == 2 && PaneOccupancy.participants(for: PaneDivider.all(for: .halves)[0], occupants: inferred).count == 2)
    let pairedSpans = [window(1, geometry.frame(spanning: 0...1)!), window(2, span)]
    for active in [PanePreset.fourColumns, .halves] {
        let configurations = ([active] + PanePreset.allCases.filter { $0 != active }).map { PaneConfiguration(preset: $0, gap: 12) }
        let links = PaneOccupancy.links(pairedSpans, configurations: configurations, area: area, pixelScale: 1, spaceID: 30)
        precondition(links.count == 1 && links[0].configuration.preset == active, "Equivalent handles prefer the active preset")
        precondition(links[0].occupants.count == 2 && Set(links[0].occupants.map { $0.window.id }).count == 2)
    }

    let domain = "local.desknames.panerange.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: domain)!
    defer { defaults.removePersistentDomain(forName: domain) }
    let legacyBindings: [UInt32: ShortcutBinding] = [322: .init(key: 20, modifiers: modifiers), 323: .init(key: 21, modifiers: modifiers)]
    struct Saved: Encodable { let enabled: Bool; let bindings: [UInt32: ShortcutBinding] }
    let saved = try JSONEncoder().encode(Saved(enabled: true, bindings: legacyBindings))
    defaults.set(saved, forKey: "keyboardShortcuts.v1")
    let settings = ShortcutSettings(defaults: defaults)
    precondition(settings.enabled && settings.bindings == legacyBindings)
    var installed: [UInt32: ShortcutBinding] = [:]
    let hotkeys = HotKeys(action: { _ in }, register: { id, binding in installed[id] = binding; return true })
    var interruptions = 0
    hotkeys.chordInterrupted = { interruptions += 1; chord.reset() }
    hotkeys.modifiersChanged = { chord.modifiersChanged($0) }
    precondition(hotkeys.apply(enabled: settings.enabled, bindings: settings.bindings).isEmpty && installed == legacyBindings)
    _ = chord.press(2, modifiers: modifiers, context: original)
    hotkeys.observeChordInput(.keyDown, key: 21, modifiers: modifiers)
    precondition(chord.press(3, modifiers: modifiers, context: original) == 2...3, "Saved pane keys preserve the chord")
    hotkeys.observeChordInput(.flagsChanged, key: 0, modifiers: modifiers)
    precondition(chord.anchor != nil)
    hotkeys.observeChordInput(.flagsChanged, key: 0, modifiers: UInt32(controlKey))
    hotkeys.observeChordInput(.flagsChanged, key: 0, modifiers: modifiers)
    precondition(chord.press(3, modifiers: modifiers, context: original) == 3...3, "Release events expire even between polling ticks")
    for type in [NSEvent.EventType.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown] {
        _ = chord.press(2, modifiers: modifiers, context: original)
        hotkeys.observeChordInput(type, key: 0, modifiers: modifiers)
        precondition(chord.anchor == nil, "Other input ends a pane chord")
    }
    let beforeDisable = interruptions
    _ = hotkeys.apply(enabled: false, bindings: settings.bindings)
    precondition(interruptions == beforeDisable + 1 && defaults.data(forKey: "keyboardShortcuts.v1") == saved, "Reconfiguration expires chords without rewriting bindings")
    print("PASS: pane range anchors, modifier/context expiry, all preset spans, gaps/scales/dividers, linked span participants, existing bindings")
}
