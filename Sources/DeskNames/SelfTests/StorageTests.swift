import Foundation

func runStorageTests() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("DeskNames-storage-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let first = try RuntimeStorage(directory: root.appendingPathComponent("first"))
    let second = try RuntimeStorage(directory: root.appendingPathComponent("second"))
    precondition(first.isIsolated && second.isIsolated)
    precondition(first.supportDirectory.path == root.appendingPathComponent("first/Application Support/DeskNames").path)
    first.defaults.set(true, forKey: "enabled")
    first.defaults.set(27, forKey: "count")
    first.defaults.set(1.25, forKey: "ratio")
    first.defaults.set(Data([1, 2, 3]), forKey: "bindings")
    first.defaults.set("complete", forKey: "onboarding.v1")
    second.defaults.set(false, forKey: "enabled")
    precondition(first.defaults.synchronize() && second.defaults.synchronize())
    let loaded = try RuntimeStorage(directory: root.appendingPathComponent("first"))
    precondition(loaded.defaults.bool(forKey: "enabled"))
    precondition(loaded.defaults.integer(forKey: "count") == 27)
    precondition(loaded.defaults.double(forKey: "ratio") == 1.25)
    precondition(loaded.defaults.data(forKey: "bindings") == Data([1, 2, 3]))
    precondition(loaded.defaults.persistentDomain(forName: loaded.preferencesDomainName)?["onboarding.v1"] as? String == "complete")
    precondition(second.defaults.object(forKey: "bindings") == nil && !second.defaults.bool(forKey: "enabled"))
    loaded.defaults.removeObject(forKey: "bindings")
    precondition(loaded.defaults.synchronize())
    let reloaded = try RuntimeStorage(directory: root.appendingPathComponent("first"))
    precondition(reloaded.defaults.data(forKey: "bindings") == nil)
    let bytes = try Data(contentsOf: root.appendingPathComponent("first/preferences.plist"))
    let persisted = try PropertyListSerialization.propertyList(from: bytes, format: nil) as! [String: Any]
    precondition(persisted["bindings"] == nil && persisted["count"] as? Int == 27)
    let absent = try RuntimeStorage.storageDirectory(arguments: ["DeskNames"])
    let parsed = try RuntimeStorage.storageDirectory(arguments: ["DeskNames", "--storage", root.path])
    precondition(absent == nil && parsed == root)
    for arguments in [["DeskNames", "--storage"], ["DeskNames", "--storage", "relative"], ["DeskNames", "--storage", root.path, "--storage", root.path]] {
        do { _ = try RuntimeStorage.storageDirectory(arguments: arguments); preconditionFailure("Invalid storage arguments must refuse without using live defaults") }
        catch { }
    }
    try Data("invalid plist".utf8).write(to: root.appendingPathComponent("first/preferences.plist"))
    do { _ = try RuntimeStorage(directory: root.appendingPathComponent("first")); preconditionFailure("Corrupt isolated storage must not fall back to live preferences") }
    catch { }
    print("PASS: isolated file preferences reload typed values and removals; directories stay separate; invalid paths and corrupt storage fail closed")
}
