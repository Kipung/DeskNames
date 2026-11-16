import AppKit
import Carbon

func runShortcutDeliveryTests() {
    runNumberShortcutTests()
    precondition(ControlPanelToggle.closes(isVisible: true, applicationActive: true))
    precondition(!ControlPanelToggle.closes(isVisible: true, applicationActive: false), "A panel hidden on deactivation must reopen on the next shortcut")
    precondition(!ControlPanelToggle.closes(isVisible: false, applicationActive: true))
    precondition(!ControlPanelToggle.closes(isVisible: false, applicationActive: false))
    var delivery = ShortcutDelivery()
    let first = delivery.receive(101)
    precondition(delivery.action == "Save active layout" && delivery.result == "Received.")
    let second = delivery.receive(102)
    precondition(delivery.complete(second, result: ShortcutRefusal.noLayout.message))
    precondition(!delivery.complete(first, result: "Saved an earlier layout."))
    precondition(delivery.action == "Restore active layout" && delivery.result == ShortcutRefusal.noLayout.message,
                 "An older operation must not replace the latest shortcut's refusal")
    precondition(delivery.complete(second, result: "Operation cancelled."))
    let replacement = delivery.receive(320)
    precondition(!delivery.complete(second, result: "An old cancelled operation finished."))
    precondition(delivery.complete(replacement, result: "Moved the focused window."))
    precondition(delivery.actionID == 320 && delivery.result == "Moved the focused window.",
                 "Replacement completion must belong to the replacement shortcut")

    let actions = Dictionary(uniqueKeysWithValues: ShortcutAction.all.map { ($0.id, $0) })
    for action in ShortcutAction.all where action.requiresAccessibility {
        precondition(action.refusal(trusted: false, busy: false) == .accessibility,
                     "Revoked Accessibility must be reported before looking for an external window")
    }
    for id in [UInt32(100), PaneShortcut.next, PaneShortcut.previous, PaneShortcut.toggleLinked] {
        precondition(actions[id]!.refusal(trusted: false, busy: false) == nil,
                     "The control panel and pane preferences must remain available without Accessibility")
    }
    precondition(actions[103]!.refusal(trusted: true, busy: false, hasWindow: false) == .noWindow,
                 "Pinning without a focused window must report a quiet refusal")
    for id in [UInt32(101), 102] {
        precondition(actions[id]!.refusal(trusted: true, busy: true) == .busy)
        precondition(actions[id]!.refusal(trusted: true, busy: false, hasDesktop: false) == .noDesktop,
                     "Saving and restoring without an ordinary desktop must not silently return")
    }
    precondition(actions[102]!.refusal(trusted: true, busy: false, hasDesktop: true, hasLayout: false) == .noLayout,
                 "Restoring an unsaved desktop must explain the missing layout")
    precondition(actions[102]!.refusal(trusted: true, busy: false, hasDesktop: true, hasLayout: true) == nil)
    precondition(actions[1]!.refusal(trusted: true, busy: true) == nil,
                 "Desktop requests keep the existing queueing behavior while a writer finishes")

    let domain = "local.desknames.delivery.test.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: domain)!
    defer { defaults.removePersistentDomain(forName: domain) }
    let settings = ShortcutSettings(defaults: defaults)
    let request = settings.receive(103)
    precondition(settings.complete(request, result: ShortcutRefusal.noWindow.message))
    precondition(settings.lastAction == ShortcutAction.pin.name && settings.delivery.result == ShortcutRefusal.noWindow.message)
    settings.apply()
    precondition(settings.delivery.result == ShortcutRefusal.noWindow.message,
                 "Registration changes must not erase the last delivered shortcut result")
    print("PASS: shortcut trust, busy, missing-window/desktop/layout refusals; latest delivery owns asynchronous results; diagnostic survives registration changes")
}

private func runNumberShortcutTests() {
    let numberRows: [UInt32] = [29, 18, 19, 20, 21, 23, 22, 26, 28, 25]
    let numberPad: [UInt32] = [82, 83, 84, 85, 86, 87, 88, 89, 91, 92]
    let modifiers = UInt32(controlKey | optionKey | cmdKey | shiftKey)
    let domain = "local.desknames.number-shortcuts.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: domain)!
    defer { defaults.removePersistentDomain(forName: domain) }
    defaults.set(Data("{\"enabled\":false,\"bindings\":[]}".utf8), forKey: "keyboardShortcuts.v1")
    let settings = ShortcutSettings(defaults: defaults)
    for (digit, keys) in zip(numberRows, numberPad).enumerated() {
        let row = ShortcutBinding(key: keys.0, modifiers: modifiers)
        let pad = ShortcutBinding(key: keys.1, modifiers: modifiers)
        precondition(row == pad && Set([row, pad]).count == 1,
                     "The same digit has one shortcut identity on either keyboard")
        precondition(pad.displayName == row.displayName && pad.displayName.hasSuffix(String(digit)))
        precondition(ShortcutSettings.validation([100: pad]) == nil)
        precondition(ShortcutSettings.validation([100: row, 101: pad]) != nil,
                     "Number-row and numpad aliases cannot belong to different actions")
        settings.beginRecording(100)
        settings.record(key: UInt16(keys.1), flags: [.control, .option, .command, .shift, .numericPad])
        precondition(settings.recordingAction == nil && settings.bindings[100]?.key == keys.0,
                     "Recording a numpad digit saves its ordinary number shortcut")
        precondition(ShortcutSettings(defaults: defaults).bindings[100]?.key == keys.0)
        var registered: [UInt32] = []
        var unregisters = 0
        let hotkeys = HotKeys(action: { _ in }, register: { id, binding in
            precondition(id == 320 && binding.modifiers == modifiers)
            registered.append(binding.key)
            return true
        }, unregister: { registered.removeAll(); unregisters += 1 })
        precondition(hotkeys.apply(enabled: true, bindings: [320: pad]).isEmpty)
        precondition(Set(registered) == Set([keys.0, keys.1]) && hotkeys.registeredCount == 1,
                     "One number shortcut must register both physical keys under the same action")
        var interruptions = 0
        hotkeys.chordInterrupted = { interruptions += 1 }
        hotkeys.observeChordInput(.keyDown, key: keys.0, modifiers: modifiers)
        hotkeys.observeChordInput(.keyDown, key: keys.1, modifiers: modifiers)
        precondition(interruptions == 0, "Mixing number-row and numpad pane keys must retain the chord")
        _ = hotkeys.apply(enabled: false, bindings: [320: pad])
        withExtendedLifetime(hotkeys) {
            precondition(registered.isEmpty && hotkeys.registeredCount == 0 && unregisters == 2,
                         "Disabling a numeric shortcut unregisters every physical alias")
        }
    }
    struct Saved: Encodable { let enabled: Bool; let bindings: [UInt32: ShortcutBinding] }
    let saved = try! JSONEncoder().encode(Saved(enabled: true, bindings: [100: .init(key: 83, modifiers: modifiers)]))
    defaults.set(saved, forKey: "keyboardShortcuts.v1")
    let loaded = ShortcutSettings(defaults: defaults)
    precondition(loaded.enabled && loaded.bindings[100]?.key == 18 && loaded.bindings.count == 1,
                 "Loading numpad shortcuts retains the configured action and enabled preference")
    precondition(defaults.data(forKey: "keyboardShortcuts.v1") == saved, "Loading must not rewrite saved preferences")
    for blocked in [UInt32(18), 83] {
        let partial = HotKeys(action: { _ in }, register: { _, binding in binding.key != blocked })
        precondition(!partial.apply(enabled: true, bindings: [320: .init(key: 18, modifiers: modifiers)]).isEmpty)
        precondition(partial.registeredCount == 1 && partial.unavailable == [320],
                     "A conflict on one physical key is reported while the other stays usable")
        _ = partial.apply(enabled: false, bindings: [:])
        precondition(partial.registeredCount == 0 && partial.unavailable.isEmpty)
    }
    precondition(ShortcutKey.physicalKeys(for: 49) == [49], "Non-numeric shortcuts register once")
    print("PASS: all ten numpad digits record, persist, detect alias conflicts, register both physical keys, retain pane chords and report partial conflicts")
}
