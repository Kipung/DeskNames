import SwiftUI
import ServiceManagement

@MainActor final class LoginItemController: ObservableObject {
    private let readStatus: () -> SMAppService.Status
    private let changeRegistration: (Bool) throws -> Void
    @Published private(set) var status: SMAppService.Status
    @Published private(set) var error = ""
    var enabled: Bool { status == .enabled || status == .requiresApproval }

    init(readStatus: @escaping () -> SMAppService.Status = { SMAppService.mainApp.status },
         changeRegistration: @escaping (Bool) throws -> Void = { enabled in
             if enabled { try SMAppService.mainApp.register() }
             else { try SMAppService.mainApp.unregister() }
         }) {
        self.readStatus = readStatus
        self.changeRegistration = changeRegistration
        status = readStatus()
    }
    func refresh() { status = readStatus() }
    func setEnabled(_ value: Bool) {
        error = ""
        do { try changeRegistration(value) }
        catch { self.error = "Could not change launch at login. \(error.localizedDescription)" }
        refresh()
    }
}

struct LoginItemControls: View {
    @ObservedObject var controller: LoginItemController
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Launch DeskNames at login", isOn: Binding(get: { controller.enabled }, set: controller.setEnabled))
            if controller.status == .requiresApproval {
                Text("Allow DeskNames in System Settings → General → Login Items.").foregroundStyle(.secondary)
                Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
            }
            if controller.status == .notFound {
                Text("Keep DeskNames in Applications before enabling launch at login.").foregroundStyle(.secondary)
            }
            if !controller.error.isEmpty { Text(controller.error).foregroundStyle(.orange) }
        }.font(.caption).controlSize(.small)
            .onAppear { controller.refresh() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in controller.refresh() }
    }
}
