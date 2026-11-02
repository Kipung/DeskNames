import AppKit

@MainActor final class AlignmentDiagnostics {
    private let queue = DispatchQueue(label: "local.desknames.alignment-diagnostics", qos: .utility)
    private var samples: [[String: Any]] = []
    private var lastSample: TimeInterval = 0

    func record(enabled: Bool, open: Bool, labelsEnabled: Bool, trusted: Bool, generation: MissionControlGeneration?, capture: MissionControlCapture?, placements: [MissionControlPlacement], panels: [String: LabelPanel]) {
        guard enabled else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastSample >= 1 else { return }
        lastSample = now
        let sample: [String: Any] = [
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "uptime": now,
            "sampledAt": capture?.sampledAt ?? NSNull(),
            "missionControlOpen": open,
            "labelsEnabled": labelsEnabled,
            "accessibilityGranted": trusted,
            "dockPID": generation?.dockPID ?? NSNull(),
            "orderMatches": capture?.orderMatches ?? false,
            "screens": generation?.screens.map { ["displayID": $0.displayID, "uuid": $0.uuid, "appKitFrame": Self.rect($0.appKitFrame), "quartzFrame": Self.rect($0.quartzFrame)] as [String: Any] } ?? [],
            "slots": generation?.slots.map { ["desktopID": $0.id, "display": $0.display, "position": $0.position, "isFullScreen": $0.isFullScreen] as [String: Any] } ?? [],
            "strips": capture?.strips.map { ["displayID": $0.displayID, "frame": Self.rect($0.frame), "buttons": $0.buttons.map(Self.rect)] as [String: Any] } ?? [],
            "placements": placements.map { ["desktopID": $0.desktopID, "displayID": $0.displayID, "nativeFrame": Self.rect($0.nativeFrame), "availableWidth": $0.availableWidth, "labelTop": $0.labelTop] as [String: Any] },
            "panels": panels.sorted { $0.key < $1.key }.map { ["desktopID": $0.key, "visible": $0.value.isVisible, "frame": Self.rect($0.value.frame)] as [String: Any] }
        ]
        samples.append(sample)
        if samples.count > 100 { samples.removeFirst(samples.count - 100) }
        let snapshot: [String: Any] = ["schemaVersion": 1, "samples": samples]
        queue.async {
            guard let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("DeskNames", isDirectory: true),
                  let data = try? JSONSerialization.data(withJSONObject: snapshot, options: [.sortedKeys]) else { return }
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try data.write(to: directory.appendingPathComponent("alignment-diagnostics.json"), options: .atomic)
            } catch {
                NSLog("DeskNames alignment diagnostics could not be saved: %@", error.localizedDescription)
            }
        }
    }

    private static func rect(_ frame: CGRect) -> [String: CGFloat] {
        ["x": frame.minX, "y": frame.minY, "width": frame.width, "height": frame.height]
    }
}
