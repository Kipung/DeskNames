import AppKit

func runGeometryTests() {
    let screen = MissionControlScreen(displayID: 2, uuid: "screen", appKitFrame: CGRect(x: 0, y: 0, width: 1440, height: 900), quartzFrame: CGRect(x: 0, y: 0, width: 1440, height: 900))
    let slots = (0..<3).map { MissionControlSlot(id: "desktop-\($0)", display: "screen", position: $0, isFullScreen: $0 == 1) }
    let generation = MissionControlGeneration(dockPID: 17, screens: [screen], slots: slots)
    let native = [CGRect(x: 320, y: 30, width: 200, height: 130), CGRect(x: 600, y: 30, width: 200, height: 130), CGRect(x: 880, y: 30, width: 200, height: 130)]
    let strip = MissionControlStrip(displayID: 2, frame: CGRect(x: 0, y: 0, width: 1440, height: 220), buttons: native)
    let placements = MissionControlGeometry.placements(strips: [strip], generation: generation)
    precondition(placements.map(\.desktopID) == ["desktop-0", "desktop-2"], "Full-screen slots must remain in the ordinal mapping")
    for (placement, center) in zip(placements, [CGFloat(420), CGFloat(980)]) {
        for width in [CGFloat(80), CGFloat(180), CGFloat(400)] {
            let frame = placement.labelFrame(fittingWidth: width)
            precondition(frame.midX == center, "Labels must be centered on their own native button")
            precondition(frame.width <= 268, "Labels must fit between neighboring native centers")
            precondition(frame.maxY == 676, "Labels must sit below the actual native strip")
        }
    }
    let translated = MissionControlScreen(displayID: 2, uuid: "screen", appKitFrame: CGRect(x: -1440, y: 300, width: 1440, height: 900), quartzFrame: CGRect(x: -1440, y: -300, width: 1440, height: 900))
    let translatedStrip = MissionControlStrip(displayID: 2, frame: strip.frame.offsetBy(dx: -1440, dy: -300), buttons: native.map { $0.offsetBy(dx: -1440, dy: -300) })
    let translatedGeneration = MissionControlGeneration(dockPID: 17, screens: [translated], slots: slots)
    let translatedPlacements = MissionControlGeometry.placements(strips: [translatedStrip], generation: translatedGeneration)
    precondition(translatedPlacements.count == placements.count)
    for (original, moved) in zip(placements, translatedPlacements) {
        precondition(moved.nativeFrame == original.nativeFrame.offsetBy(dx: -1440, dy: 300), "AX point coordinates must convert through the matched display")
    }
    let missing = MissionControlStrip(displayID: 2, frame: strip.frame, buttons: Array(native.dropLast()))
    precondition(MissionControlGeometry.placements(strips: [missing], generation: generation).isEmpty, "Count mismatch must hide that display")
    let compact = MissionControlStrip(displayID: 2, frame: CGRect(x: 0, y: 0, width: 5120, height: 40), buttons: [CGRect(x: 2278, y: -32, width: 65, height: 24), CGRect(x: 2375, y: -32, width: 67, height: 24), CGRect(x: 2474, y: -32, width: 68, height: 24), CGRect(x: 2574, y: -32, width: 68, height: 24), CGRect(x: 2674, y: -32, width: 68, height: 24), CGRect(x: 2774, y: -32, width: 68, height: 24)])
    let wideScreen = MissionControlScreen(displayID: 2, uuid: "screen", appKitFrame: CGRect(x: 0, y: 0, width: 5120, height: 1440), quartzFrame: CGRect(x: 0, y: 0, width: 5120, height: 1440))
    let sixSlots = (0..<6).map { MissionControlSlot(id: "desktop-\($0)", display: "screen", position: $0, isFullScreen: false) }
    let compactGeneration = MissionControlGeneration(dockPID: 17, screens: [wideScreen], slots: sixSlots)
    precondition(MissionControlGeometry.placements(strips: [compact], generation: compactGeneration).isEmpty, "Captured compact geometry must stay hidden")
    let offscreen = MissionControlStrip(displayID: 2, frame: strip.frame, buttons: native.map { $0.offsetBy(dx: 0, dy: -200) })
    precondition(MissionControlGeometry.placements(strips: [offscreen], generation: generation).isEmpty)
    precondition(MissionControlGeometry.placements(strips: [strip, strip], generation: generation).isEmpty, "Ambiguous display geometry must stay hidden")
    let captions = MissionControlStrip(displayID: 2, frame: strip.frame, buttons: native.map { CGRect(x: $0.midX - 32, y: 180, width: 64, height: 24) })
    let captionPlacements = MissionControlGeometry.placements(strips: [captions], generation: generation)
    precondition(captionPlacements.count == 2)
    precondition(captionPlacements.allSatisfy { $0.labelFrame(fittingWidth: 200).width == 200 && $0.labelFrame(fittingWidth: 200).maxY == 676 }, "Caption-only AX buttons must still allow names between their centers below the strip")
    var stability = MissionControlStability()
    precondition(stability.accept(placements, generation: generation, current: generation, sampledAt: 1, now: 1).isEmpty)
    precondition(stability.accept(placements, generation: generation, current: generation, sampledAt: 1.2, now: 1.2) == placements)
    let moved = placements.map { MissionControlPlacement(desktopID: $0.desktopID, displayID: $0.displayID, nativeFrame: $0.nativeFrame.offsetBy(dx: 10, dy: 0), availableWidth: $0.availableWidth, labelTop: $0.labelTop) }
    precondition(stability.accept(moved, generation: generation, current: generation, sampledAt: 1.4, now: 1.4).isEmpty, "Movement must hide labels until stable")
    precondition(stability.accept(moved, generation: generation, current: generation, sampledAt: 1.6, now: 1.6) == moved)
    precondition(stability.accept([], generation: generation, current: generation, sampledAt: 1.8, now: 1.8).isEmpty)
    precondition(stability.accept(moved, generation: generation, current: generation, sampledAt: 2, now: 2).isEmpty, "An invalid sample must clear the previous candidate")
    let reordered = MissionControlGeneration(dockPID: 17, screens: [screen], slots: [MissionControlSlot(id: "desktop-2", display: "screen", position: 0, isFullScreen: false), slots[1], MissionControlSlot(id: "desktop-0", display: "screen", position: 2, isFullScreen: false)])
    precondition(stability.accept(placements, generation: generation, current: reordered, sampledAt: 2.2, now: 2.2).isEmpty, "A delayed result for an old UUID order must never render")
    precondition(stability.accept(placements, generation: reordered, current: reordered, sampledAt: 2.4, now: 2.4).isEmpty)
    precondition(stability.accept(placements, generation: reordered, current: reordered, sampledAt: 2.6, now: 3.3).isEmpty, "A stale capture must never render")
    let restarted = MissionControlGeneration(dockPID: 18, screens: [screen], slots: slots)
    precondition(stability.accept(placements, generation: generation, current: restarted, sampledAt: 4, now: 4).isEmpty)
    precondition(stability.accept(placements, generation: generation, current: translatedGeneration, sampledAt: 4.2, now: 4.2).isEmpty)
    print("PASS: native centering and width, translated displays, full-screen slot preservation, count mismatch, captured compact strip, offscreen/ambiguous geometry, stability, animation hiding, UUID order, Dock/display generation and stale-result rejection")
}
