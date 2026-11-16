import SwiftUI
import Carbon

struct PhysicalShortcut: Hashable {
    let key: UInt32
    let modifiers: UInt32

    var displayName: String {
        ShortcutBinding(key: key, modifiers: modifiers).displayName + (key == ShortcutKey.normalized(key) ? "" : " (numpad)")
    }
}

struct ShortcutConflictReport {
    enum Cause: Equatable {
        case macOS, registeredElsewhere, checkFailed(OSStatus)
        var description: String {
            switch self {
            case .macOS: return "Used by a macOS shortcut"
            case .registeredElsewhere: return "Used by another registered shortcut"
            case .checkFailed(let status): return "Could not check this combination (\(status))"
            }
        }
    }
    struct Issue: Identifiable {
        let actionID: UInt32
        let combination: PhysicalShortcut
        let cause: Cause
        var id: String { "\(actionID):\(combination.key):\(combination.modifiers)" }
        var actionName: String { ShortcutAction.all.first { $0.id == actionID }?.name ?? "Shortcut" }
    }
    let checkedCount: Int
    let issues: [Issue]
    let systemCheckError: OSStatus?
    var isComplete: Bool {
        systemCheckError == nil && !issues.contains { if case .checkFailed = $0.cause { return true }; return false }
    }
    var summary: String {
        if checkedCount == 0 { return "No shortcut bindings to check." }
        if !isComplete { return "Shortcut check incomplete." }
        let conflicts = Set(issues.map(\.actionID)).count
        return conflicts == 0 ? "No conflicts detected in \(checkedCount) shortcuts." : "\(conflicts) shortcut\(conflicts == 1 ? " needs" : "s need") attention."
    }
    static let limitation = "Checks macOS shortcuts and current global registrations. Some app-specific shortcuts cannot be detected."
}

struct ShortcutConflictInspector {
    enum SystemShortcuts {
        case available(Set<PhysicalShortcut>)
        case failed(OSStatus)
    }
    struct Registration {
        let status: OSStatus
        let release: (() -> OSStatus)?
    }
    var systemShortcuts: () -> SystemShortcuts = Self.readSystemShortcuts
    var register: (PhysicalShortcut) -> Registration = Self.registerProbe

    func check(_ bindings: [UInt32: ShortcutBinding], owned: Set<PhysicalShortcut>) -> ShortcutConflictReport {
        precondition(Thread.isMainThread)
        guard !bindings.isEmpty else { return ShortcutConflictReport(checkedCount: 0, issues: [], systemCheckError: nil) }
        let reserved: Set<PhysicalShortcut>
        let systemError: OSStatus?
        switch systemShortcuts() {
        case .available(let shortcuts): reserved = shortcuts; systemError = nil
        case .failed(let error): reserved = []; systemError = error
        }
        var issues: [ShortcutConflictReport.Issue] = []
        for (actionID, binding) in bindings.sorted(by: { $0.key < $1.key }) {
            for key in ShortcutKey.physicalKeys(for: binding.key) {
                let combination = PhysicalShortcut(key: key, modifiers: binding.modifiers)
                let cause: ShortcutConflictReport.Cause?
                if reserved.contains(combination) { cause = .macOS }
                else if owned.contains(combination) { cause = nil }
                else {
                    let registration = register(combination)
                    let cleanup = registration.release?()
                    if let cleanup, cleanup != noErr { cause = .checkFailed(cleanup) }
                    else if registration.status == OSStatus(eventHotKeyExistsErr) { cause = .registeredElsewhere }
                    else if registration.status != noErr { cause = .checkFailed(registration.status) }
                    else if cleanup == nil { cause = .checkFailed(OSStatus(paramErr)) }
                    else { cause = nil }
                }
                if let cause { issues.append(.init(actionID: actionID, combination: combination, cause: cause)) }
            }
        }
        return ShortcutConflictReport(checkedCount: bindings.count, issues: issues, systemCheckError: systemError)
    }

    private static func readSystemShortcuts() -> SystemShortcuts {
        var values: Unmanaged<CFArray>?
        let status = CopySymbolicHotKeys(&values)
        let array = values?.takeRetainedValue()
        guard status == noErr else { return .failed(status) }
        guard let list = array as? [[String: Any]] else { return .failed(OSStatus(paramErr)) }
        return parseSystemShortcuts(list)
    }

    static func parseSystemShortcuts(_ list: [[String: Any]]) -> SystemShortcuts {
        var result = Set<PhysicalShortcut>()
        for item in list {
            guard let enabled = item[kHISymbolicHotKeyEnabled as String] as? NSNumber else { return .failed(OSStatus(paramErr)) }
            if !enabled.boolValue { continue }
            guard let key = item[kHISymbolicHotKeyCode as String] as? NSNumber,
                  let modifiers = item[kHISymbolicHotKeyModifiers as String] as? NSNumber else { return .failed(OSStatus(paramErr)) }
            result.insert(PhysicalShortcut(key: key.uint32Value, modifiers: modifiers.uint32Value))
        }
        return .available(result)
    }

    private static func registerProbe(_ combination: PhysicalShortcut) -> Registration {
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(combination.key, combination.modifiers,
                                         EventHotKeyID(signature: 0x444E434B, id: 1), GetApplicationEventTarget(),
                                         UInt32(kEventHotKeyExclusive), &reference)
        return Registration(status: status, release: reference.map { reference in { UnregisterEventHotKey(reference) } })
    }
}

struct ShortcutConflictView: View {
    @ObservedObject var settings: ShortcutSettings
    var compact = false
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label(settings.conflictReport?.summary ?? "Check shortcut conflicts", systemImage: icon)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Button(settings.conflictReport == nil ? "Check" : "Recheck") { settings.checkConflicts() }
                    .disabled(settings.recordingAction != nil)
            }
            if let report = settings.conflictReport {
                if let error = report.systemCheckError {
                    Text("Could not read macOS shortcuts (\(error)). Recheck before relying on this result.")
                        .foregroundStyle(.orange)
                }
                if !report.issues.isEmpty {
                    DisclosureGroup("Show affected shortcuts", isExpanded: $expanded) {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(report.issues) { issue in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(issue.actionName + " · " + issue.combination.displayName).fontWeight(.medium)
                                        Text(issue.cause.description).foregroundStyle(.secondary)
                                    }
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.frame(maxHeight: compact ? 100 : 140)
                    }
                    Text("Choose different keys in Keyboard shortcuts, or change the conflicting shortcut in macOS or the other app.")
                        .foregroundStyle(.secondary)
                }
            }
            Text(ShortcutConflictReport.limitation).foregroundStyle(.secondary)
        }.font(.caption).controlSize(.small).padding(12)
            .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
    }

    private var icon: String {
        guard let report = settings.conflictReport else { return "keyboard" }
        return report.isComplete && report.issues.isEmpty ? "checkmark.circle" : "exclamationmark.triangle"
    }
}
