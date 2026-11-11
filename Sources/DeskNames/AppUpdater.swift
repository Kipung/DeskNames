import AppKit
import SwiftUI
import Sparkle

@MainActor final class AppUpdater: ObservableObject {
    private let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
    @Published private(set) var canCheck = false
    @Published private(set) var automaticChecks = false
    @Published private(set) var automaticDownloads = false
    @Published private(set) var startupError = ""

    init() {
        controller.updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheck)
        controller.updater.publisher(for: \.automaticallyChecksForUpdates).assign(to: &$automaticChecks)
        controller.updater.publisher(for: \.automaticallyDownloadsUpdates).assign(to: &$automaticDownloads)
    }
    func start() {
        do { try controller.updater.start() }
        catch { startupError = "Updates are unavailable: \(error.localizedDescription)" }
    }
    func check() { controller.checkForUpdates(nil) }
    func setAutomaticChecks(_ value: Bool) { controller.updater.automaticallyChecksForUpdates = value }
    func setAutomaticDownloads(_ value: Bool) { controller.updater.automaticallyDownloadsUpdates = value }
}

struct UpdateControls: View {
    @ObservedObject var updater: AppUpdater
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Button("Check for Updates…") { updater.check() }.disabled(!updater.canCheck)
                Spacer()
                Toggle("Check automatically", isOn: Binding(get: { updater.automaticChecks }, set: updater.setAutomaticChecks))
            }
            Toggle("Download and install updates automatically", isOn: Binding(get: { updater.automaticDownloads }, set: updater.setAutomaticDownloads))
                .disabled(!updater.automaticChecks)
            if !updater.startupError.isEmpty { Text(updater.startupError).foregroundStyle(.orange) }
        }.font(.caption).controlSize(.small)
    }
}
