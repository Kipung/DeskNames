import Foundation
import ServiceManagement

@MainActor func runFirstRunTests() throws {
    let domain = "local.desknames.first-run-test.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: domain)!
    defer { defaults.removePersistentDomain(forName: domain) }
    func clear() { defaults.removePersistentDomain(forName: domain) }
    func state() -> FirstRunPreferences { FirstRunPreferences(defaults: defaults, domainName: domain) }

    defaults.register(defaults: ["registeredDefault": true])
    let fresh = state()
    precondition(fresh.step == .accessibility, "Registered and global defaults must not hide first-run setup")
    defaults.set(false, forKey: "labelsEnabled")
    precondition(state().step == .accessibility, "An interrupted new install resumes despite later preference writes")
    fresh.advance()
    precondition(state().step == .shortcuts)
    fresh.advance()
    precondition(state().step == .layout)
    fresh.finish()
    precondition(!state().isPresented, "Completed or skipped setup must not return")
    for (key, value) in ["labelsEnabled": false, "unfamiliarFutureKey": "", "keyboardShortcuts.v1": Data(),
                         "didShowFirstLaunchPanel": false, "onboarding.v1": "future-state"] as [String: Any] {
        clear()
        defaults.set(value, forKey: key)
        let before = defaults.persistentDomain(forName: domain)!
        precondition(!state().isPresented, "Any saved preference must suppress onboarding")
        precondition(NSDictionary(dictionary: before).isEqual(to: defaults.persistentDomain(forName: domain)!))
    }

    clear()
    let shortcuts = ShortcutSettings(defaults: defaults)
    precondition(!shortcuts.enabled)
    let panes = PanePreferences(defaults: defaults)
    precondition(panes.enabled && !panes.edgeSnapping && !panes.linkedResizing)
    precondition(panes.configuration(for: "new-desktop").gap == 0)
    precondition(!RoutingSettings(defaults: defaults).enabled)
    var applied = false
    shortcuts.onChange = { enabled, bindings in applied = enabled && !bindings.isEmpty; return "" }
    shortcuts.enableSuggestions()
    precondition(applied && ShortcutSettings(defaults: defaults).enabled)
    precondition(shortcuts.bindings == ShortcutDefaults.bindings)
    let custom = ShortcutBinding(key: 0, modifiers: 256)
    precondition(shortcuts.set(custom, for: 100))
    precondition(shortcuts.set(nil, for: ShortcutAction.pin.id))
    shortcuts.enableSuggestions()
    precondition(shortcuts.bindings[100] == custom, "Opting in must preserve custom bindings")
    precondition(shortcuts.bindings[ShortcutAction.pin.id] != nil)

    clear()
    let paneJSON = """
    {"enabled":false,"futureField":"keep","desktops":{
      "old":{"preset":"thirds","gap":12,"splitPositions":{"v0":0.4},"unknown":42},
      "custom":{"preset":"halves","gap":8},
      "near":{"preset":"rows","gap":12.0001},
      "zero":{"preset":"focus","gap":0}}}
    """
    let monitorJSON = """
    {"disabled":{"enabled":false,"panes":{"preset":"quarters","gap":12},"unknown":"keep"},
     "custom":{"enabled":true,"panes":{"preset":"rows","gap":6}},
     "enabled":{"enabled":true,"panes":{"preset":"halves","gap":12}}}
    """
    let panesKey = "smartPanes.v1", monitorsKey = "monitorModelPresets.v1"
    defaults.set(Data(paneJSON.utf8), forKey: panesKey)
    defaults.set(Data(monitorJSON.utf8), forKey: monitorsKey)
    defaults.set(Data([1, 2, 3]), forKey: "keyboardShortcuts.v1")
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("first-run-test-\(UUID().uuidString).json")
    let workspace = LayoutController(store: Store(defaults: defaults), file: file,
                                     native: NativeWindows(trustCheck: { false }, includeExternal: false))
    precondition(workspace.gap == 0)
    precondition(defaults.data(forKey: panesKey) == Data(paneJSON.utf8))
    precondition(defaults.object(forKey: "paneSpacingMigrationVersion") == nil, "Model construction must not migrate preferences in tests or preview modes")
    let paneExpected = paneJSON.replacingOccurrences(of: "\"gap\":12,", with: "\"gap\":0,")
    let monitorExpected = monitorJSON.replacingOccurrences(of: "\"gap\":12}", with: "\"gap\":0}")
    precondition(PreferenceMigrations.migratePaneSpacing(in: defaults))
    func json(_ data: Data) throws -> NSDictionary { try JSONSerialization.jsonObject(with: data) as! NSDictionary }
    let migratedPanes = try json(defaults.data(forKey: panesKey)!)
    let migratedMonitors = try json(defaults.data(forKey: monitorsKey)!)
    let expectedPanes = try json(Data(paneExpected.utf8))
    let expectedMonitors = try json(Data(monitorExpected.utf8))
    precondition(migratedPanes.isEqual(expectedPanes))
    precondition(migratedMonitors.isEqual(expectedMonitors))
    let migratedPreferences = PanePreferences(defaults: defaults)
    let migratedPresets = MonitorPresets(defaults: defaults)
    precondition(!migratedPreferences.enabled && migratedPreferences.configuration(for: "old").gap == 0)
    precondition(migratedPresets.values["disabled"]?.enabled == false && migratedPresets.values["disabled"]?.panes.gap == 0)
    precondition(defaults.data(forKey: "keyboardShortcuts.v1") == Data([1, 2, 3]))
    precondition(!state().isPresented)
    defaults.set(Data(paneJSON.utf8), forKey: panesKey)
    defaults.set(Data(monitorJSON.utf8), forKey: monitorsKey)
    precondition(PreferenceMigrations.migratePaneSpacing(in: defaults))
    precondition(defaults.data(forKey: panesKey) == Data(paneJSON.utf8), "A later deliberate 12-point desktop gap survives")
    precondition(defaults.data(forKey: monitorsKey) == Data(monitorJSON.utf8), "A later deliberate 12-point monitor gap survives")

    clear()
    precondition(PreferenceMigrations.migratePaneSpacing(in: defaults))
    defaults.set(Data(paneJSON.utf8), forKey: panesKey)
    precondition(PreferenceMigrations.migratePaneSpacing(in: defaults))
    precondition(defaults.data(forKey: panesKey) == Data(paneJSON.utf8), "Fresh installs also mark the migration complete")

    clear()
    defaults.set(Data(paneJSON.utf8), forKey: panesKey)
    defaults.set(Data("broken".utf8), forKey: monitorsKey)
    precondition(!PreferenceMigrations.migratePaneSpacing(in: defaults))
    let readablePanes = try json(defaults.data(forKey: panesKey)!)
    precondition(readablePanes.isEqual(expectedPanes), "An unreadable monitor store must not block desktop migration")
    precondition(defaults.data(forKey: monitorsKey) == Data("broken".utf8))
    defaults.set(Data(paneJSON.utf8), forKey: panesKey)
    defaults.set(Data(monitorJSON.utf8), forKey: monitorsKey)
    precondition(PreferenceMigrations.migratePaneSpacing(in: defaults))
    precondition(defaults.data(forKey: panesKey) == Data(paneJSON.utf8), "A later choice of 12 survives even after other malformed data is repaired")
    precondition(defaults.data(forKey: monitorsKey) == Data(monitorJSON.utf8), "Repairing a store must not repeat the migration")

    clear()
    let onboardingBeforeMigration = state()
    PreferenceMigrations.migratePaneSpacing(in: defaults)
    let isolatedStore = Store(defaults: defaults)
    let isolatedFile = FileManager.default.temporaryDirectory.appendingPathComponent("DeskNames-startup-\(UUID().uuidString).json")
    let startupWorkspace = LayoutController(store: isolatedStore, file: isolatedFile, native: NativeWindows(trustCheck: { false }, includeExternal: false))
    precondition(onboardingBeforeMigration.isPresented && state().isPresented,
                 "Migration and model initialization must not suppress a fresh welcome session")
    precondition(startupWorkspace.gap == 0 && startupWorkspace.panes.configuration(for: "fresh").gap == 0)

    var loginStatus = SMAppService.Status.notRegistered
    var registrations = 0
    let login = LoginItemController(readStatus: { loginStatus }, changeRegistration: { value in
        registrations += 1
        loginStatus = value ? .requiresApproval : .notRegistered
    })
    precondition(!login.enabled && registrations == 0, "Reading login state must not register the app")
    login.setEnabled(true)
    precondition(login.enabled && login.status == .requiresApproval && registrations == 1)
    loginStatus = .enabled
    login.refresh()
    precondition(login.enabled && login.status == .enabled && registrations == 1)
    login.setEnabled(false)
    precondition(!login.enabled && registrations == 2)
    let refused = LoginItemController(readStatus: { .notRegistered }, changeRegistration: { _ in throw WindowIssue("Test refusal") })
    refused.setEnabled(true)
    precondition(!refused.enabled && refused.error.contains("Test refusal"))
    print("First-run, pane spacing migration and login-item state tests passed.")
}
