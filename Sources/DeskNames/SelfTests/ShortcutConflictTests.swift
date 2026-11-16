import AppKit
import Carbon

func runShortcutConflictTests() {
    let modifiers = UInt32(controlKey | optionKey | cmdKey)
    let row = PhysicalShortcut(key: 18, modifiers: modifiers)
    let pad = PhysicalShortcut(key: 83, modifiers: modifiers)
    let letter = PhysicalShortcut(key: 0, modifiers: modifiers)
    let bindings: [UInt32: ShortcutBinding] = [320: .init(key: 18, modifiers: modifiers), 100: .init(key: 0, modifiers: modifiers)]
    var probes: [PhysicalShortcut] = [], released: [PhysicalShortcut] = []
    let inspector = ShortcutConflictInspector(systemShortcuts: { .available([row]) }, register: { key in
        probes.append(key)
        if key == pad { return .init(status: OSStatus(eventHotKeyExistsErr), release: nil) }
        return .init(status: noErr, release: { released.append(key); return noErr })
    })
    let report = inspector.check(bindings, owned: [])
    precondition(report.checkedCount == 2 && report.isComplete)
    precondition(report.issues.count == 2 && report.issues.allSatisfy { $0.actionID == 320 })
    precondition(report.issues.first { $0.combination == row }?.cause == .macOS)
    precondition(report.issues.first { $0.combination == pad }?.cause == .registeredElsewhere)
    precondition(Set(probes) == [pad, letter] && released == [letter], "Only unowned, non-system combinations are probed and released")
    precondition(report.summary == "1 shortcut needs attention.")
    precondition(Set([row, pad]).count == 2, "Raw ownership keeps number-row and numpad registrations separate")

    probes.removeAll(); released.removeAll()
    let unavailableSystem = ShortcutConflictInspector(systemShortcuts: { .failed(OSStatus(memFullErr)) }, register: { key in
        probes.append(key)
        return .init(status: noErr, release: { released.append(key); return noErr })
    }).check(bindings, owned: [])
    precondition(!unavailableSystem.isComplete && unavailableSystem.systemCheckError == OSStatus(memFullErr) && unavailableSystem.issues.isEmpty)
    precondition(unavailableSystem.summary == "Shortcut check incomplete." && probes.count == 3 && released.count == 3,
                 "Failed system lookup must not claim that all shortcuts are conflict-free")
    var cleanupCount = 0
    let failedCleanup = ShortcutConflictInspector(systemShortcuts: { .available([]) }, register: { _ in
        .init(status: noErr, release: { cleanupCount += 1; return OSStatus(paramErr) })
    }).check([100: .init(key: 0, modifiers: modifiers)], owned: [])
    precondition(cleanupCount == 1 && !failedCleanup.isComplete && failedCleanup.issues[0].cause == .checkFailed(OSStatus(paramErr)))
    let failedRegistration = ShortcutConflictInspector(systemShortcuts: { .available([]) }, register: { _ in
        .init(status: OSStatus(memFullErr), release: { cleanupCount += 1; return noErr })
    }).check([100: .init(key: 0, modifiers: modifiers)], owned: [])
    precondition(cleanupCount == 2 && !failedRegistration.isComplete && failedRegistration.issues[0].cause == .checkFailed(OSStatus(memFullErr)),
                 "Even a failed registration must release any returned reference")

    let hotkeys = HotKeys(action: { _ in }, register: { _, binding in binding.key == row.key })
    _ = hotkeys.apply(enabled: true, bindings: [320: .init(key: row.key, modifiers: modifiers)])
    probes.removeAll()
    let ownershipInspector = ShortcutConflictInspector(systemShortcuts: { .available([]) }, register: { key in
        probes.append(key)
        return .init(status: OSStatus(eventHotKeyExistsErr), release: nil)
    })
    let partial = hotkeys.checkConflicts([320: .init(key: row.key, modifiers: modifiers)], inspector: ownershipInspector)
    precondition(probes == [pad] && partial.issues.count == 1 && partial.issues[0].combination == pad,
                 "A working row registration must not hide a conflicting numpad alias")
    _ = hotkeys.apply(enabled: false, bindings: [:])
    probes.removeAll()
    _ = hotkeys.checkConflicts([320: .init(key: row.key, modifiers: modifiers)], inspector: ownershipInspector)
    precondition(probes == [row, pad], "Disabling registrations clears physical ownership")

    let validSystem: [[String: Any]] = [
        [kHISymbolicHotKeyEnabled as String: true, kHISymbolicHotKeyCode as String: row.key, kHISymbolicHotKeyModifiers as String: modifiers],
        [kHISymbolicHotKeyEnabled as String: false, kHISymbolicHotKeyCode as String: pad.key, kHISymbolicHotKeyModifiers as String: modifiers]
    ]
    if case .available(let keys) = ShortcutConflictInspector.parseSystemShortcuts(validSystem) { precondition(keys == [row]) }
    else { preconditionFailure("Enabled system shortcuts must decode Carbon key/modifier pairs") }
    if case .failed = ShortcutConflictInspector.parseSystemShortcuts([[kHISymbolicHotKeyEnabled as String: true]]) { }
    else { preconditionFailure("Malformed enabled system shortcuts must fail the check") }

    let domain = "local.desknames.shortcut-conflicts.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: domain)!
    defer { defaults.removePersistentDomain(forName: domain) }
    let settings = ShortcutSettings(defaults: defaults)
    var checks = 0
    settings.onConflictCheck = { requested in
        checks += 1
        return ShortcutConflictReport(checkedCount: requested.count, issues: [], systemCheckError: nil)
    }
    let before = defaults.persistentDomain(forName: domain)
    settings.checkConflicts()
    precondition(!settings.enabled && settings.conflictReport?.checkedCount == ShortcutDefaults.bindings.count && checks == 1)
    precondition(defaults.persistentDomain(forName: domain) == nil && before == nil,
                 "Checking defaults before opt-in must not write preferences or enable shortcuts")
    settings.beginRecording(100)
    precondition(settings.conflictReport == nil)
    settings.checkConflicts()
    precondition(checks == 1, "Conflict probes must not run during recording")
    settings.cancelRecording(100)
    settings.checkConflicts()
    precondition(checks == 2 && settings.conflictReport != nil)
    precondition(settings.set(.init(key: 0, modifiers: modifiers), for: 100))
    precondition(settings.conflictReport == nil, "Editing bindings invalidates the prior report")
    settings.checkConflicts()
    let savedBeforeCheck = defaults.data(forKey: "keyboardShortcuts.v1")
    settings.checkConflicts()
    precondition(defaults.data(forKey: "keyboardShortcuts.v1") == savedBeforeCheck && !settings.enabled)
    var occupied = false
    settings.onChange = { _, _ in occupied = true; return "Unavailable" }
    settings.onConflictCheck = { requested in
        ShortcutConflictReport(checkedCount: requested.count, issues: occupied ? [
            .init(actionID: 100, combination: letter, cause: .registeredElsewhere)
        ] : [], systemCheckError: nil)
    }
    settings.checkConflicts()
    precondition(settings.conflictReport?.issues.isEmpty == true)
    settings.setEnabled(true)
    precondition(settings.conflictReport?.issues.count == 1,
                 "Enabling must refresh an existing report after active registrations change")
    settings.onChange = { _, _ in occupied = false; return "" }
    settings.apply()
    precondition(settings.conflictReport?.issues.isEmpty == true,
                 "Reapplying registrations refreshes the existing report even when bindings are unchanged")
    print("PASS: macOS and global shortcut conflict checks distinguish physical aliases, owned registrations and errors; probes release references; setup checks preserve opt-in and invalidate stale results")
}
