import AppKit

struct MissionControlScreen: Equatable {
    let displayID: CGDirectDisplayID
    let uuid: String
    let appKitFrame: CGRect
    let quartzFrame: CGRect

    @MainActor static func current() -> [MissionControlScreen] {
        NSScreen.screens.compactMap { screen in
            guard let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value,
                  let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return nil }
            return MissionControlScreen(displayID: id, uuid: CFUUIDCreateString(nil, uuid)! as String, appKitFrame: screen.frame, quartzFrame: CGDisplayBounds(id))
        }.sorted { $0.displayID < $1.displayID }
    }

    func appKitRect(_ rect: CGRect) -> CGRect {
        CGRect(x: appKitFrame.minX + rect.minX - quartzFrame.minX, y: appKitFrame.maxY - (rect.maxY - quartzFrame.minY), width: rect.width, height: rect.height)
    }
}

struct MissionControlSlot: Equatable {
    let id: String
    let display: String
    let position: Int
    let isFullScreen: Bool

    static func snapshot(_ desktops: [Desktop]) -> [MissionControlSlot] {
        desktops.map { MissionControlSlot(id: $0.id, display: $0.display, position: $0.position, isFullScreen: $0.isFullScreen) }
    }
}

struct MissionControlGeneration: Equatable {
    let dockPID: pid_t
    let screens: [MissionControlScreen]
    let slots: [MissionControlSlot]
}

struct MissionControlStrip {
    let displayID: CGDirectDisplayID
    let frame: CGRect
    let buttons: [CGRect]
}

struct MissionControlPlacement: Equatable {
    let desktopID: String
    let displayID: CGDirectDisplayID
    let nativeFrame: CGRect
    let availableWidth: CGFloat
    let labelTop: CGFloat

    func labelFrame(fittingWidth: CGFloat) -> CGRect {
        let width = min(max(fittingWidth, 70), availableWidth)
        return CGRect(x: nativeFrame.midX - width / 2, y: labelTop - 36, width: width, height: 36)
    }
}

struct MissionControlStability {
    static let maximumAge: TimeInterval = 0.6
    private var generation: MissionControlGeneration?
    private var previous: [MissionControlPlacement] = []
    private var previousTime: TimeInterval = 0

    mutating func reset() {
        generation = nil
        previous = []
        previousTime = 0
    }

    mutating func accept(_ placements: [MissionControlPlacement], generation: MissionControlGeneration, current: MissionControlGeneration?, sampledAt: TimeInterval, now: TimeInterval) -> [MissionControlPlacement] {
        guard current == generation, now >= sampledAt, now - sampledAt <= Self.maximumAge, !placements.isEmpty else {
            reset()
            return []
        }
        let stable = self.generation == generation && sampledAt > previousTime && sampledAt - previousTime <= Self.maximumAge && previous.count == placements.count && zip(previous, placements).allSatisfy { before, after in
            before.desktopID == after.desktopID && before.displayID == after.displayID && Self.close(before.nativeFrame, after.nativeFrame) && abs(before.availableWidth - after.availableWidth) <= 1 && abs(before.labelTop - after.labelTop) <= 1
        }
        self.generation = generation
        previous = placements
        previousTime = sampledAt
        return stable ? placements : []
    }

    private static func close(_ a: CGRect, _ b: CGRect) -> Bool {
        zip([a.minX, a.minY, a.width, a.height], [b.minX, b.minY, b.width, b.height]).allSatisfy { abs($0 - $1) <= 1 }
    }
}

enum MissionControlGeometry {
    static func placements(strips: [MissionControlStrip], generation: MissionControlGeneration) -> [MissionControlPlacement] {
        guard Set(generation.screens.map(\.displayID)).count == generation.screens.count,
              Set(generation.screens.map(\.uuid)).count == generation.screens.count,
              Set(generation.slots.map(\.id)).count == generation.slots.count else { return [] }
        var result: [MissionControlPlacement] = []
        for screen in generation.screens {
            let matching = strips.filter { $0.displayID == screen.displayID }
            guard matching.count == 1, let strip = matching.first,
                  valid(screen.appKitFrame), valid(screen.quartzFrame),
                  abs(screen.appKitFrame.width - screen.quartzFrame.width) <= 1,
                  abs(screen.appKitFrame.height - screen.quartzFrame.height) <= 1,
                  valid(strip.frame), strip.frame.height > 40,
                  screen.quartzFrame.contains(strip.frame) else { continue }
            let slots = generation.slots.filter { $0.display == screen.uuid || (generation.screens.count == 1 && $0.display == "Main") }.sorted { $0.position < $1.position }
            guard !slots.isEmpty, slots.count == strip.buttons.count,
                  slots.map(\.position) == Array(0..<slots.count),
                  strip.buttons.allSatisfy({ valid($0) && strip.frame.contains($0) }),
                  zip(strip.buttons, strip.buttons.dropFirst()).allSatisfy({ $0.maxX <= $1.minX }) else { continue }
            let labelTop = screen.appKitRect(strip.frame).minY - 4
            let placements = slots.enumerated().compactMap { index, slot -> MissionControlPlacement? in
                guard !slot.isFullScreen else { return nil }
                let button = strip.buttons[index]
                var width = min(button.midX - strip.frame.minX, strip.frame.maxX - button.midX) * 2
                if index > 0 { width = min(width, button.midX - strip.buttons[index - 1].midX) }
                if index + 1 < strip.buttons.count { width = min(width, strip.buttons[index + 1].midX - button.midX) }
                return MissionControlPlacement(desktopID: slot.id, displayID: screen.displayID, nativeFrame: screen.appKitRect(button), availableWidth: width - 12, labelTop: labelTop)
            }
            guard placements.allSatisfy({ $0.availableWidth >= 70 && screen.appKitFrame.contains($0.labelFrame(fittingWidth: $0.availableWidth)) }) else { continue }
            result.append(contentsOf: placements)
        }
        return result
    }

    private static func valid(_ frame: CGRect) -> Bool {
        [frame.minX, frame.minY, frame.width, frame.height].allSatisfy(\.isFinite) && frame.width > 0 && frame.height > 0
    }
}

struct MissionControlCapture {
    let sampledAt: TimeInterval
    let strips: [MissionControlStrip]
    let orderMatches: Bool
}

final class MissionControlReader: @unchecked Sendable {
    private let spaces = SpaceReader()

    func capture(_ generation: MissionControlGeneration) -> MissionControlCapture {
        let sampledAt = ProcessInfo.processInfo.systemUptime
        guard AXIsProcessTrusted(), MissionControlSlot.snapshot(spaces.read()) == generation.slots else {
            return MissionControlCapture(sampledAt: sampledAt, strips: [], orderMatches: false)
        }
        let strips = readStrips(dockPID: generation.dockPID)
        let matches = MissionControlSlot.snapshot(spaces.read()) == generation.slots
        return MissionControlCapture(sampledAt: sampledAt, strips: strips, orderMatches: matches)
    }

    private func readStrips(dockPID: pid_t) -> [MissionControlStrip] {
        let dock = AXUIElementCreateApplication(dockPID)
        AXUIElementSetMessagingTimeout(dock, 0.15)
        guard let roots = children(dock), let missionControl = unique("mc", in: roots), let displays = children(missionControl) else { return [] }
        var result: [MissionControlStrip] = []
        for display in displays where string(display, kAXIdentifierAttribute) == "mc.display" {
            guard let displayID = attribute(display, "AXDisplayID") as? NSNumber,
                  let displayChildren = children(display), let strip = unique("mc.spaces", in: displayChildren),
                  let stripFrame = frame(strip), let stripChildren = children(strip),
                  let list = unique("mc.spaces.list", in: stripChildren), let buttons = children(list),
                  !buttons.isEmpty, buttons.allSatisfy({ string($0, kAXRoleAttribute) == kAXButtonRole }) else { continue }
            let frames = buttons.compactMap(frame)
            guard frames.count == buttons.count else { continue }
            result.append(MissionControlStrip(displayID: displayID.uint32Value, frame: stripFrame, buttons: frames))
        }
        return result
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private func children(_ element: AXUIElement) -> [AXUIElement]? { attribute(element, kAXChildrenAttribute) as? [AXUIElement] }
    private func string(_ element: AXUIElement, _ name: String) -> String? { attribute(element, name) as? String }

    private func unique(_ identifier: String, in elements: [AXUIElement]) -> AXUIElement? {
        let matches = elements.filter { string($0, kAXIdentifierAttribute) == identifier }
        return matches.count == 1 ? matches.first : nil
    }

    private func frame(_ element: AXUIElement) -> CGRect? {
        guard let rawPosition = attribute(element, kAXPositionAttribute), CFGetTypeID(rawPosition) == AXValueGetTypeID(),
              let rawSize = attribute(element, kAXSizeAttribute), CFGetTypeID(rawSize) == AXValueGetTypeID() else { return nil }
        let position = rawPosition as! AXValue, size = rawSize as! AXValue
        var point = CGPoint.zero, dimensions = CGSize.zero
        guard AXValueGetType(position) == .cgPoint, AXValueGetType(size) == .cgSize,
              AXValueGetValue(position, .cgPoint, &point), AXValueGetValue(size, .cgSize, &dimensions) else { return nil }
        return CGRect(origin: point, size: dimensions)
    }
}
