import Foundation
import ObjectiveC

final class RuntimeStorage {
    private(set) static var current = RuntimeStorage()
    let directory: URL?
    private let isolatedDefaults: UserDefaults?
    var isIsolated: Bool { directory != nil }
    var defaults: UserDefaults { isolatedDefaults ?? UserDefaults.standard }
    var preferencesDomainName: String {
        directory?.appendingPathComponent("preferences").path ?? Bundle.main.bundleIdentifier!
    }
    var supportDirectory: URL {
        if let directory { return directory.appendingPathComponent("Application Support/DeskNames", isDirectory: true) }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("DeskNames", isDirectory: true)
    }

    private init() { directory = nil; isolatedDefaults = nil }

    init(directory: URL) throws {
        let directory = directory.standardizedFileURL
        self.directory = directory
        let file = directory.appendingPathComponent("preferences.plist")
        if FileManager.default.fileExists(atPath: file.path) {
            let data = try Data(contentsOf: file)
            guard (try PropertyListSerialization.propertyList(from: data, format: nil)) is [String: Any] else {
                throw CocoaError(.propertyListReadCorrupt)
            }
        }
        guard let defaults = UserDefaults(suiteName: directory.appendingPathComponent("preferences").path) else {
            throw CocoaError(.fileReadUnknown)
        }
        isolatedDefaults = defaults
        try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
    }

    static func configure(arguments: [String]) throws {
        guard let directory = try storageDirectory(arguments: arguments) else { return }
        let storage = try RuntimeStorage(directory: directory)
        // AppKit writes window preferences independently of DeskNames' models. An absolute
        // suite excludes the live app domain; CFFIXED_USER_HOME does not redirect cfprefsd.
        guard let getter = class_getClassMethod(UserDefaults.self, #selector(getter: UserDefaults.standard)) else {
            throw CocoaError(.featureUnsupported)
        }
        let defaults = storage.defaults
        let implementation: @convention(block) (AnyObject) -> UserDefaults = { _ in defaults }
        method_setImplementation(getter, imp_implementationWithBlock(implementation))
        current = storage
    }

    static func storageDirectory(arguments: [String]) throws -> URL? {
        let indices = arguments.indices.filter { arguments[$0] == "--storage" }
        guard let index = indices.first else { return nil }
        guard indices.count == 1, arguments.count > index + 1, arguments[index + 1].hasPrefix("/") else {
            throw NSError(domain: "DeskNames.Storage", code: 1, userInfo: [NSLocalizedDescriptionKey: "--storage requires one absolute directory path."])
        }
        return URL(fileURLWithPath: arguments[index + 1], isDirectory: true).standardizedFileURL
    }
}
