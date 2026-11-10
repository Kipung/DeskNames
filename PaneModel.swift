import AppKit
import SwiftUI

enum PanePreset: String, Codable, CaseIterable, Identifiable {
    case halves, thirds, fourColumns, quarters, rows, wideLeft, focus
    var id: String { rawValue }
    var name: String {
        switch self {
        case .halves: return "Two columns"
        case .thirds: return "Three columns"
        case .fourColumns: return "Four columns"
        case .quarters: return "Four quarters"
        case .rows: return "Two rows"
        case .wideLeft: return "Wide + stack"
        case .focus: return "Focus"
        }
    }
    var regions: [CGRect] {
        switch self {
        case .halves: return [CGRect(x: 0, y: 0, width: 0.5, height: 1), CGRect(x: 0.5, y: 0, width: 0.5, height: 1)]
        case .thirds: return (0..<3).map { CGRect(x: Double($0)/3, y: 0, width: 1.0/3, height: 1) }
        case .fourColumns: return (0..<4).map { CGRect(x: Double($0)/4, y: 0, width: 0.25, height: 1) }
        case .quarters: return (0..<4).map { CGRect(x: Double($0%2)/2, y: Double($0/2)/2, width: 0.5, height: 0.5) }
        case .rows: return [CGRect(x: 0, y: 0, width: 1, height: 0.5), CGRect(x: 0, y: 0.5, width: 1, height: 0.5)]
        case .wideLeft: return [CGRect(x: 0, y: 0, width: 2.0/3, height: 1), CGRect(x: 2.0/3, y: 0, width: 1.0/3, height: 0.5), CGRect(x: 2.0/3, y: 0.5, width: 1.0/3, height: 0.5)]
        case .focus: return [CGRect(x: 0, y: 0, width: 1, height: 1)]
        }
    }
}

struct PaneConfiguration: Codable, Equatable {
    var preset: PanePreset = .halves
    var gap: Double = 12
    var splitPositions: [String: Double]? = nil
    var sanitized: PaneConfiguration {
        var result = self
        result.gap = min(32, max(0, gap.isFinite ? gap : 12))
        if let positions = splitPositions {
            let splits = PaneDivider.all(for: preset)
            let valid = positions.allSatisfy { key, value in
                splits.contains { $0.id == key && value.isFinite && value >= $0.lower + 0.05 && value <= $0.upper - 0.05 }
            }
            let ordered = [true, false].allSatisfy { vertical in
                let axis = splits.filter { $0.vertical == vertical }
                let values = [0.0] + axis.map { positions[$0.id] ?? $0.position } + [1.0]
                return zip(values, values.dropFirst()).allSatisfy { $1 - $0 >= 0.05 }
            }
            result.splitPositions = valid && ordered && !positions.isEmpty ? positions : nil
        }
        return result
    }
}

final class PanePreferences: ObservableObject {
    private struct Saved: Codable { var enabled: Bool; var desktops: [String: PaneConfiguration] }
    private let defaults: UserDefaults
    private static let key = "smartPanes.v1"
    @Published private(set) var enabled: Bool
    @Published private(set) var desktops: [String: PaneConfiguration]
    @Published private(set) var edgeSnapping: Bool
    @Published private(set) var linkedResizing: Bool
    var onChange: (() -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        linkedResizing = defaults.bool(forKey: "linkedPaneResizingEnabled")
        edgeSnapping = defaults.bool(forKey: "edgeSnappingEnabled")
        let saved = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(Saved.self, from: $0) }
        enabled = saved?.enabled ?? true
        desktops = saved?.desktops.mapValues(\.sanitized) ?? [:]
    }

    func configuration(for desktopID: String) -> PaneConfiguration { desktops[desktopID] ?? PaneConfiguration() }
    func set(_ configuration: PaneConfiguration, for desktopID: String) {
        guard !desktopID.isEmpty else { return }
        desktops[desktopID] = configuration.sanitized
        save()
    }
    func setLinkedResizing(_ value: Bool) { linkedResizing = value; defaults.set(value, forKey: "linkedPaneResizingEnabled"); onChange?() }
    func setEdgeSnapping(_ value: Bool) { edgeSnapping=value;defaults.set(value,forKey:"edgeSnappingEnabled");onChange?() }
    func setEnabled(_ value: Bool) { enabled = value; save() }
    private func save() {
        if let data = try? JSONEncoder().encode(Saved(enabled: enabled, desktops: desktops)) { defaults.set(data, forKey: Self.key) }
        onChange?()
    }
}

struct PaneGeometry: Equatable {
    let area: CGRect
    let cells: [CGRect]

    init(area: CGRect, configuration: PaneConfiguration) {
        self.area = area
        guard Self.valid(area) else { cells = []; return }
        let gap = configuration.sanitized.gap
        let insetArea = area.insetBy(dx: gap/2, dy: gap/2)
        let frames = configuration.sanitized.regions.map { region in
            CGRect(x: insetArea.minX + region.minX * insetArea.width,
                   y: insetArea.minY + region.minY * insetArea.height,
                   width: region.width * insetArea.width, height: region.height * insetArea.height)
                .insetBy(dx: gap/2, dy: gap/2)
        }
        cells = frames.allSatisfy { Self.valid($0) && area.contains($0) } ? frames : []
    }

    init(area: CGRect, cells: [CGRect]) { self.area=area;self.cells=cells.allSatisfy({Self.valid($0) && area.contains($0)}) ? cells : [] }

    static func valid(_ rect: CGRect) -> Bool {
        [rect.minX, rect.minY, rect.width, rect.height].allSatisfy(\.isFinite) && rect.width > 0 && rect.height > 0
    }
    func hit(_ point: CGPoint) -> Int? { cells.firstIndex { $0.contains(point) } }
}

struct PaneMoveEvidence {
    private struct PointerSample { let point: CGPoint; let time: TimeInterval }
    private var referenceFrame: CGRect
    private var referencePointer: CGPoint
    private var referenceFrameTime: TimeInterval
    private var referencePointerTime: TimeInterval
    private var pointers: [PointerSample]
    private static let maximumDelay: TimeInterval = 0.2
    private(set) var latestFrame: CGRect
    private(set) var confirmations = 0
    private(set) var rejected = false
    var moved: Bool { confirmations >= 2 && !rejected }

    init(initialFrame: CGRect, initialPointer: CGPoint, time: TimeInterval) {
        referenceFrame = initialFrame; latestFrame = initialFrame; referencePointer = initialPointer
        referenceFrameTime = time; referencePointerTime = time
        pointers = [PointerSample(point: initialPointer, time: time)]
    }

    mutating func observe(frame: CGRect, pointer: CGPoint, time: TimeInterval) {
        guard !rejected else { return }
        guard PaneGeometry.valid(frame) else { rejected = true; return }
        guard time.isFinite, time > (pointers.last?.time ?? referenceFrameTime), pointer.x.isFinite, pointer.y.isFinite else { return }
        latestFrame = frame
        if abs(frame.width - referenceFrame.width) > 2 || abs(frame.height - referenceFrame.height) > 2 {
            referenceFrame = frame; referencePointer = pointer; confirmations = 0
            referenceFrameTime = time; referencePointerTime = time
            pointers = [PointerSample(point: pointer, time: time)]
            return
        }
        pointers.append(PointerSample(point: pointer, time: time))
        while pointers.count > 2 && pointers[1].time < time - Self.maximumDelay { pointers.removeFirst() }
        let dx = frame.minX - referenceFrame.minX, dy = frame.minY - referenceFrame.minY
        let distance = hypot(dx, dy), elapsed = time - referenceFrameTime
        guard distance >= 6 else { return }
        let expected = CGPoint(x: referencePointer.x + dx, y: referencePointer.y + dy)
        var best: (sample: PointerSample, error: CGFloat)?
        for (a, b) in zip(pointers, pointers.dropFirst()) {
            let sx = b.point.x - a.point.x, sy = b.point.y - a.point.y
            let lengthSquared = sx*sx + sy*sy
            guard lengthSquared > 0 else { continue }
            let fraction = min(1, max(0, ((expected.x - a.point.x)*sx + (expected.y - a.point.y)*sy)/lengthSquared))
            let sample = PointerSample(point: CGPoint(x: a.point.x + fraction*sx, y: a.point.y + fraction*sy),
                                       time: a.time + fraction*(b.time - a.time))
            let pointerElapsed = sample.time - referencePointerTime
            guard time - sample.time <= Self.maximumDelay, pointerElapsed >= elapsed/3, pointerElapsed <= elapsed*3 else { continue }
            let px = sample.point.x - referencePointer.x, py = sample.point.y - referencePointer.y
            let pointerDistance = hypot(px, py), error = hypot(dx - px, dy - py)
            guard pointerDistance >= 6, (dx*px + dy*py)/(distance*pointerDistance) >= 0.9,
                  error <= max(8, min(28, pointerDistance * 0.15)) else { continue }
            if best == nil || error < best!.error { best = (sample, error) }
        }
        guard let matched = best?.sample else { return }
        confirmations += 1
        referenceFrame = frame; referencePointer = matched.point
        referenceFrameTime = time; referencePointerTime = matched.time
    }
}
