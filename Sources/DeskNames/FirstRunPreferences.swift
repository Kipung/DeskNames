import Foundation
import Combine

final class FirstRunPreferences: ObservableObject {
    enum Step: String { case accessibility, shortcuts, layout, complete }
    private static let key = "onboarding.v1"
    private let defaults: UserDefaults
    @Published private(set) var step: Step
    var isPresented: Bool { step != .complete }

    init(defaults: UserDefaults, domainName: String) {
        self.defaults = defaults
        let saved = defaults.persistentDomain(forName: domainName) ?? [:]
        if let value = saved[Self.key] as? String, let step = Step(rawValue: value) {
            self.step = step
        } else if saved.isEmpty {
            step = .accessibility
            defaults.set(step.rawValue, forKey: Self.key)
        } else {
            step = .complete
        }
    }

    func advance() {
        switch step {
        case .accessibility: set(.shortcuts)
        case .shortcuts: set(.layout)
        case .layout, .complete: finish()
        }
    }
    func finish() { set(.complete) }
    private func set(_ value: Step) {
        step = value
        defaults.set(value.rawValue, forKey: Self.key)
    }
}

enum PreferenceMigrations {
    private static let spacingVersionKey = "paneSpacingMigrationVersion"

    @discardableResult static func migratePaneSpacing(in defaults: UserDefaults) -> Bool {
        guard defaults.integer(forKey: spacingVersionKey) < 1 else { return true }
        var updates: [String: Data] = [:]
        var migratedAll = true
        stores: for key in ["smartPanes.v1", "monitorModelPresets.v1"] {
            guard let stored = defaults.object(forKey: key) else { continue }
            guard let data = stored as? Data,
                  var root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { migratedAll = false; continue }
            let desktopPanes = key == "smartPanes.v1"
            guard var entries = (desktopPanes ? root["desktops"] : root) as? [String: Any] else { migratedAll = false; continue }
            var changed = false
            for (id, value) in entries {
                guard var entry = value as? [String: Any],
                      var panes = (desktopPanes ? entry : entry["panes"]) as? [String: Any] else { migratedAll = false; continue stores }
                if (panes["gap"] as? NSNumber)?.doubleValue == 12 {
                    panes["gap"] = 0
                    if desktopPanes { entry = panes } else { entry["panes"] = panes }
                    entries[id] = entry
                    changed = true
                }
            }
            if changed {
                if desktopPanes { root["desktops"] = entries } else { root = entries }
                guard let encoded = try? JSONSerialization.data(withJSONObject: root) else { migratedAll = false; continue }
                updates[key] = encoded
            }
        }
        for (key, data) in updates { defaults.set(data, forKey: key) }
        defaults.set(1, forKey: spacingVersionKey)
        return migratedAll
    }
}
