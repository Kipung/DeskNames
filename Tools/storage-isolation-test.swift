import Foundation

let arguments = CommandLine.arguments
let key = "DeskNamesStorageProbeSentinel"
if arguments.contains("--child") {
    try RuntimeStorage.configure(arguments: arguments)
    let storage = RuntimeStorage.current
    precondition(UserDefaults.standard === storage.defaults)
    precondition(UserDefaults.standard.object(forKey: key) == nil, "Isolated standard defaults must not fall back to the application domain")
    UserDefaults.standard.set("isolated", forKey: "frameworkPreference")
    precondition(UserDefaults.standard.synchronize())
    let reloaded = try RuntimeStorage(directory: storage.directory!)
    precondition(reloaded.defaults.string(forKey: "frameworkPreference") == "isolated")
    let data = try Data(contentsOf: storage.directory!.appendingPathComponent("preferences.plist"))
    let persisted = try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: Any]
    precondition(persisted["frameworkPreference"] as? String == "isolated" && persisted[key] == nil)
} else {
    try runStorageTests()
    let defaults = UserDefaults.standard
    defaults.set("application sentinel", forKey: key)
    precondition(defaults.synchronize())
    defer { defaults.removeObject(forKey: key); defaults.synchronize() }
    let child = Process()
    child.executableURL = URL(fileURLWithPath: arguments[0])
    child.arguments = ["--child", "--storage", arguments[1]]
    try child.run()
    child.waitUntilExit()
    precondition(child.terminationStatus == 0)
    precondition(defaults.string(forKey: key) == "application sentinel")
    precondition(defaults.object(forKey: "frameworkPreference") == nil)
    print("PASS: separate process redirects framework standard defaults, excludes the application sentinel, persists and reloads only the absolute suite")
}
