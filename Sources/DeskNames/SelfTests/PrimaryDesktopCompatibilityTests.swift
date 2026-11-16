import Foundation

@MainActor func runPrimaryDesktopCompatibilityTests() throws {
    func primary(_ display: String) -> Desktop {
        Desktop(id: "desknames:primary:\(display)", spaceID: 1, display: display,
                position: 0, number: 1, isCurrent: true, isFullScreen: false)
    }
    func window(_ display: String, desktopID: String?) -> SavedWindow {
        SavedWindow(bundleID: "local.fixture", title: "Fixture", ordinal: 0, windowID: 1, pid: 1,
                    displayID: display, frame: SavedRect(CGRect(x: 0, y: 0, width: 0.5, height: 1)),
                    desktopID: desktopID)
    }
    let desktop = primary("screen-a"), other = primary("screen-b")
    let legacy = DesktopLayout(id: "", savedAt: Date(timeIntervalSince1970: 1),
                               windows: [window("screen-a", desktopID: "")], autoRestore: true,
                               launchMissing: false, gatherWindows: false, name: "Original layout")
    let domain = "local.desknames.primary-compatibility.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: domain)!
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("primary-compatibility-\(UUID().uuidString).json")
    defer { defaults.removePersistentDomain(forName: domain); try? FileManager.default.removeItem(at: file) }
    let appearance = try JSONEncoder().encode(["": Appearance(name: "Original desktop", color: 2)])
    defaults.set(appearance, forKey: "desktopAppearance")
    let savedBytes = try JSONEncoder().encode(["": legacy])
    try savedBytes.write(to: file)
    let store = Store(defaults: defaults, reader: SpaceReader(snapshot: { [desktop] }))
    precondition(store.name(desktop) == "Original desktop" && store.style(desktop).color == 2)
    let workspace = LayoutController(store: store, file: file, native: NativeWindows(trustCheck: { false }, includeExternal: false))
    precondition(workspace.layouts[""] == nil && workspace.layouts[desktop.id]?.id == desktop.id)
    precondition(workspace.restoreSelection?.windows[0].desktopID == desktop.id)
    precondition(workspace.restoreSelection?.name == legacy.name && workspace.restoreSelection?.autoRestore == true)
    precondition(workspace.restoreSelection?.launchMissing == false)
    let after = try Data(contentsOf: file)
    precondition(after == savedBytes, "Resolving legacy layout identities must not rewrite saved files during construction")
    precondition(defaults.data(forKey: "desktopAppearance") == appearance,
                 "Reading a legacy desktop name must not rewrite preferences")

    store.appearance[desktop.id] = Appearance(name: "New name", color: 1)
    precondition(store.name(desktop) == "New name", "An explicit primary appearance takes precedence over the legacy alias")
    store.appearance.removeValue(forKey: desktop.id)
    store.desktops = [desktop, other]
    precondition(store.name(desktop) == "Desktop 1", "An ambiguous legacy name must not be assigned to a guessed primary desktop")
    var newer = legacy
    newer.id = desktop.id
    newer.name = "New layout"
    let collision = PrimaryDesktopCompatibility.layouts(["": legacy, desktop.id: newer], desktops: [desktop])
    precondition(collision[""]?.name == legacy.name && collision[desktop.id]?.name == newer.name,
                 "A legacy layout cannot replace an explicitly saved primary layout")
    let ambiguous = PrimaryDesktopCompatibility.layouts(["": legacy], desktops: [desktop, other])
    precondition(ambiguous[""] != nil && ambiguous[desktop.id] == nil,
                 "The old layout owner remains unresolved when multiple primary desktops exist")
    precondition(ambiguous[""]?.windows[0].desktopID == desktop.id,
                 "An individual window can resolve its primary desktop by exact display identity")
    var mismatch = legacy
    mismatch.windows = [window("screen-b", desktopID: "")]
    let unresolved = PrimaryDesktopCompatibility.layouts(["": mismatch], desktops: [desktop])
    precondition(unresolved[""]?.windows[0].desktopID == "" && unresolved[desktop.id] == nil,
                 "Contradictory saved display identity must not be reassigned")
    mismatch.windows = [window("screen-b", desktopID: nil)]
    let older = PrimaryDesktopCompatibility.layouts(["": mismatch], desktops: [desktop])
    precondition(older[""] != nil && older[desktop.id] == nil,
                 "An older window without desktop metadata still supplies display evidence against reassignment")
    var crossScreen = newer
    crossScreen.windows = [window("screen-a", desktopID: ""), window("screen-b", desktopID: "named-space")]
    let mapped = PrimaryDesktopCompatibility.layouts([newer.id: crossScreen], desktops: [desktop, other])
    precondition(mapped[newer.id]?.windows.map(\.desktopID) == [desktop.id, "named-space"],
                 "Legacy window references resolve without altering named desktop references")
    print("PASS: legacy primary desktop names and layouts remain accessible; load preserves saved bytes, explicit keys and ambiguous identities")
}
