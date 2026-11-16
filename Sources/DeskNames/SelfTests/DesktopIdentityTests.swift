import Foundation

@MainActor func runDesktopIdentityTests() {
    try! runPrimaryDesktopCompatibilityTests()
    let screenID = "E2E73C74-42BF-43E1-906A-A8466B33480C"
    func group(_ display: String?, fullscreen: Bool = false) -> [String: Any] {
        var result: [String: Any] = [
            "Current Space": ["ManagedSpaceID": NSNumber(value: 7)],
            "Spaces": [["ManagedSpaceID": NSNumber(value: 7), "uuid": "desktop-id", "type": fullscreen ? 4 : 0]]
        ]
        result["Display Identifier"] = display
        return result
    }
    let nativeMain = group("Main")
    let sole = SpaceReader.desktops(in: [nativeMain], screenIDs: [screenID])
    precondition(sole.count == 1)
    let desktop = sole[0]
    precondition(desktop.display == screenID, "A sole native Main display must match the physical screen for pane placement and layout capture")
    precondition(desktop.id == "desktop-id" && desktop.spaceID == 7 && desktop.position == 0 && desktop.number == 1)
    precondition(desktop.isCurrent && !desktop.isFullScreen)
    precondition(SpaceReader.desktops(in: [group(screenID)], screenIDs: ["other"]) == sole,
                 "An explicit native display UUID remains authoritative")
    precondition(SpaceReader.desktops(in: [group(nil)], screenIDs: [screenID]) == sole)
    let fullscreen = SpaceReader.desktops(in: [group("Main", fullscreen: true)], screenIDs: [screenID])[0]
    precondition(fullscreen.isCurrent && fullscreen.isFullScreen && fullscreen.display == screenID)
    precondition(SpaceReader.desktops(in: [nativeMain], screenIDs: []).first?.display == "Main")
    precondition(SpaceReader.desktops(in: [nativeMain], screenIDs: [screenID, "other"]).first?.display == "Main",
                 "Shared Spaces across multiple screens cannot be assigned to a guessed display")
    precondition(SpaceReader.desktops(in: [nativeMain, group("other")], screenIDs: [screenID]).first?.display == "Main",
                 "A partially observed display topology must not resolve Main")
    precondition(SpaceReader.desktops(in: [], screenIDs: [screenID]).isEmpty)
    var primary: [String: Any] = ["ManagedSpaceID": NSNumber(value: 1), "uuid": "", "type": 0]
    let secondary: [String: Any] = ["ManagedSpaceID": NSNumber(value: 3), "uuid": "second-desktop", "type": 0]
    var raw: [[String: Any]] = [["Display Identifier": screenID,
                               "Current Space": ["ManagedSpaceID": NSNumber(value: 1)], "Spaces": [primary]]]
    let reader = SpaceReader(snapshot: { SpaceReader.desktops(in: raw, screenIDs: [screenID]) })
    let domain = "local.desknames.primary-desktop-test.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: domain)!
    defer { defaults.removePersistentDomain(forName: domain) }
    let store = Store(defaults: defaults, reader: reader)
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("primary-desktop-\(UUID().uuidString).json")
    let workspace = LayoutController(store: store, file: file, native: NativeWindows(trustCheck: { false }, includeExternal: false))
    let initial = store.desktops[0]
    precondition(!initial.id.isEmpty && initial.isCurrent && !initial.isFullScreen)
    for preset in PanePreset.allCases {
        precondition(workspace.choosePanePreset(preset, for: initial), "A sole primary desktop can select each pane layout")
        precondition(PanePreferences(defaults: defaults).configuration(for: initial.id).preset == preset)
    }
    precondition(workspace.choosePanePreset(.fourColumns, for: initial))
    raw[0]["Spaces"] = [primary, secondary]
    store.refresh()
    precondition(store.desktops[0].id == initial.id && store.desktops[1].id == "second-desktop")
    precondition(workspace.paneConfiguration(for: store.desktops[0].id).preset == .fourColumns,
                 "Adding a second desktop preserves the primary desktop's chosen layout")
    primary["ManagedSpaceID"] = NSNumber(value: 17)
    raw[0]["Current Space"] = ["ManagedSpaceID": NSNumber(value: 17)]
    raw[0]["Spaces"] = [secondary, primary]
    store.refresh()
    precondition(store.desktops[1].id == initial.id && store.desktops[1].isCurrent)
    precondition(workspace.choosePanePreset(.rows, for: store.desktops[1]))
    precondition(PanePreferences(defaults: defaults).configuration(for: initial.id).preset == .rows,
                 "Primary identity must not depend on transient Space IDs or desktop position")
    var otherDisplay = raw[0]
    otherDisplay["Display Identifier"] = "other-screen"
    let both = SpaceReader.desktops(in: [raw[0], otherDisplay], screenIDs: [screenID, "other-screen"])
    precondition(Set(both.filter { $0.spaceID == 17 }.map(\.id)).count == 2, "Unnamed desktops on different displays have different identities")
    raw[0]["Spaces"] = [primary, primary]
    precondition(reader.read().isEmpty, "Multiple unnamed desktops must not share a guessed identity")
    primary["type"] = 4
    raw[0]["Spaces"] = [primary]
    precondition(reader.read().isEmpty, "An unnamed fullscreen Space is not the primary desktop")
    primary["type"] = 0
    primary["uuid"] = NSNumber(value: 42)
    raw[0]["Spaces"] = [primary]
    precondition(reader.read().isEmpty, "Malformed UUID values must not be treated as an unnamed primary desktop")
    primary.removeValue(forKey: "uuid")
    raw[0]["Spaces"] = [primary]
    precondition(reader.read().first?.id == initial.id, "An absent primary UUID and an empty one have the same identity")
    print("PASS: single-display Main identity resolves for pane placement and capture; explicit UUIDs, Space flags and ambiguous topologies are preserved")
    print("PASS: a sole UUID-less desktop selects and persists all seven pane layouts without creating another desktop; adding and reordering desktops preserves the choice")
}
