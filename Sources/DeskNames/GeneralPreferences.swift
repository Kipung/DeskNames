import SwiftUI

final class GeneralPreferences: ObservableObject {
    private let defaults: UserDefaults
    @Published private(set) var showMenuBarIcon: Bool
    @Published private(set) var showDesktopNames: Bool
    @Published private(set) var hideWhenInactive: Bool
    var onChange: (() -> Void)?

    init(defaults: UserDefaults = RuntimeStorage.current.defaults) {
        self.defaults = defaults
        showMenuBarIcon = defaults.object(forKey: "showMenuBarIcon") as? Bool ?? true
        showDesktopNames = defaults.object(forKey: "showDesktopNamesInMenuBar") as? Bool ?? true
        hideWhenInactive = defaults.object(forKey: "hideControlCenterWhenInactive") as? Bool ?? true
    }
    func setShowMenuBarIcon(_ value: Bool) {
        showMenuBarIcon = value; defaults.set(value, forKey: "showMenuBarIcon"); onChange?()
    }
    func setShowDesktopNames(_ value: Bool) {
        showDesktopNames = value; defaults.set(value, forKey: "showDesktopNamesInMenuBar"); onChange?()
    }
    func setHideWhenInactive(_ value: Bool) {
        hideWhenInactive = value; defaults.set(value, forKey: "hideControlCenterWhenInactive"); onChange?()
    }
}

struct GeneralSettingsView: View {
    @ObservedObject var preferences: GeneralPreferences
    var loginItem: LoginItemController? = nil
    var updater: AppUpdater? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Menu bar and window").font(.headline)
                    Toggle("Show DeskNames in the menu bar", isOn: Binding(get: { preferences.showMenuBarIcon }, set: preferences.setShowMenuBarIcon))
                    Toggle("Show desktop names beside the icon", isOn: Binding(get: { preferences.showDesktopNames }, set: preferences.setShowDesktopNames))
                        .disabled(!preferences.showMenuBarIcon)
                    Toggle("Hide control center when switching apps", isOn: Binding(get: { preferences.hideWhenInactive }, set: preferences.setHideWhenInactive))
                    Text("When the icon is hidden, open DeskNames from Applications or use your control-panel shortcut to return. Opening the app always shows the control center.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                if let loginItem {
                    Divider()
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Startup").font(.headline)
                        LoginItemControls(controller: loginItem)
                    }
                }
                if let updater {
                    Divider()
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Updates").font(.headline)
                        UpdateControls(updater: updater)
                    }
                }
                Divider()
                HStack {
                    Text("DeskNames \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "DEV")")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Quit DeskNames") { NSApp.terminate(nil) }
                }
            }.padding(.vertical, 4)
        }
    }
}
