import AppKit
import SwiftUI

// Offscreen rendering uses only fixtures; no screen capture or personal storage.
@MainActor func renderMarketing(to directory: URL) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let domain = "local.desknames.marketing.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: domain)!
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("marketing-\(UUID().uuidString).json")
    defer { defaults.removePersistentDomain(forName: domain); try? FileManager.default.removeItem(at: file) }
    let store = Store(defaults: defaults)
    store.desktops = ["Create", "Read", "Plan"].enumerated().map {
        Desktop(id: "sample-\($0.offset)", spaceID: UInt64($0.offset+1), display: "sample-display", position: $0.offset, number: $0.offset+1, isCurrent: $0.offset == 0, isFullScreen: false)
    }
    for (index, desktop) in store.desktops.enumerated() {
        store.update(desktop, name: ["Create", "Read", "Plan"][index], color: index)
    }
    let workspace = LayoutController(store: store, file: file, native: NativeWindows(trustCheck: { true }, includeExternal: false))
    workspace.panes.set(PaneConfiguration(preset: .thirds, gap: 0), for: store.desktops[0].id)
    let panel = SwitcherView(store: store, workspace: workspace, preferences: workspace.panes, models: workspace.monitorPresets,
                             desktop: store.desktops[0], choose: { _ in }, close: {}, openSettings: {})
    try renderFixture(panel, size: CGSize(width: 560, height: 620), to: directory.appendingPathComponent("control-panel.png"))
    let frames = Int((PaneDemoFrame.duration*PaneDemoFrame.fps).rounded())
    for frame in 0..<frames {
        try renderFixture(PaneDemoFrame(time: Double(frame)/PaneDemoFrame.fps),
                          size: PaneDemoFrame.canvas.size, to: directory.appendingPathComponent(String(format: "frame-%03d.png", frame)))
    }
    print("Rendered isolated marketing fixtures; no desktop screenshot or user documents were captured.")
}

@MainActor private func renderFixture<V: View>(_ view: V, size: CGSize, to url: URL) throws {
    let host = NSHostingView(rootView: view)
    host.sizingOptions = []
    host.frame = CGRect(origin: .zero, size: size)
    let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.appearance = NSAppearance(named: .darkAqua)
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw WindowIssue("Could not render the demo fixture.") }
    host.cacheDisplay(in: host.bounds, to: rep)
    guard let data = rep.representation(using: .png, properties: [:]) else { throw WindowIssue("Could not encode the demo image.") }
    try data.write(to: url)
    window.close()
}


// Illustrated, looping walkthrough: pick a layout, Command-drag windows into it, save the arrangement,
// rearrange with shortcuts, restore it, then jump to another named desktop.
// Window motion uses the production PaneGeometry and WindowTransition functions.
private struct PaneDemoFrame: View {
    // GIF delays are whole centiseconds; 50 fps gives an even 2 cs per frame.
    static let fps = 50.0
    static let duration = 18.4
    static let canvas = CGRect(x: 0, y: 0, width: 1120, height: 700)
    let time: Double

    private static let stage = CGRect(x: 40, y: 36, width: 1040, height: 580)
    private static let area = CGRect(x: 52, y: 76, width: 1016, height: 528)
    private static let panel = CGRect(x: 730, y: 70, width: 330, height: 362)
    private static let menuItem = CGPoint(x: 925, y: 50)
    private static let rest = CGPoint(x: 860, y: 480)
    private static let cells = PaneGeometry(area: area, configuration: PaneConfiguration(preset: .thirds, gap: 10)).cells
    private static let halves = PaneGeometry(area: area, configuration: PaneConfiguration(preset: .halves, gap: 10)).cells
    private static let starts = (0..<3).map { CGRect(x: 150 + Double($0)*150, y: 120 + Double($0)*45, width: 430, height: 330) }
    // Topmost window first so every title bar is visible when grabbed.
    private static let dragOrder = [2, 1, 0]
    private static func press(_ step: Int) -> Double { 2.95 + 1.5*Double(step) }
    private static func grab(_ window: Int) -> CGPoint { CGPoint(x: starts[window].minX + 130, y: starts[window].minY + 18) }
    private static func drop(_ window: Int) -> CGPoint { CGPoint(x: cells[window].minX + 130, y: cells[window].minY + 30) }
    private static func card(_ index: Int) -> CGRect {
        CGRect(x: panel.minX + 16 + Double(index%3)*102, y: panel.minY + 98 + Double(index/3)*84, width: 92, height: 58)
    }
    private static let clicks = [0.75, 1.95, 11.6]
    private static func region(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> CGRect {
        PaneGeometry.frames(in: area, regions: [CGRect(x: x, y: y, width: w, height: h)], gap: 10)[0]
    }
    private struct Move { let window: Int; let start: Double; let target: CGRect; var duration = 0.24 }
    // Shortcut moves act on the focused window: Draft was dragged last, then Tasks is clicked.
    private static let moves: [Move] = [
        Move(window: 0, start: 9.25, target: region(0, 0, 1, 1)),
        Move(window: 0, start: 10.05, target: region(0.5, 0, 0.5, 1)),
        Move(window: 0, start: 10.85, target: region(0, 0.5, 0.5, 0.5)),
        Move(window: 2, start: 12.25, target: region(0, 0, 0.5, 0.5)),
    ] + (0..<3).map { Move(window: $0, start: 13.25 + 0.06*Double($0), target: cells[$0], duration: 0.45) }
    private struct Keystroke { let time: Double; let keys: [String]; let label: String }
    private static let keystrokes = [
        Keystroke(time: 7.7, keys: ["⌃", "⌥", "S"], label: "Save layout for Create"),
        Keystroke(time: 9.2, keys: ["⌃", "⌥", "↩"], label: "Maximize"),
        Keystroke(time: 10.0, keys: ["⌃", "⌥", "→"], label: "Right half"),
        Keystroke(time: 10.8, keys: ["⌃", "⌥", "J"], label: "Bottom-left quarter"),
        Keystroke(time: 12.2, keys: ["⌃", "⌥", "U"], label: "Top-left quarter"),
        Keystroke(time: 13.2, keys: ["⌃", "⌥", "R"], label: "Restore layout"),
        Keystroke(time: 14.7, keys: ["⌃", "⌥", "2"], label: "Go to Read"),
        Keystroke(time: 16.0, keys: [], label: "Each desktop keeps its own name, panes, and layout."),
    ]
    private static func keystrokeEnd(_ index: Int) -> Double {
        index + 1 < keystrokes.count ? min(keystrokes[index + 1].time - 0.1, keystrokes[index].time + 1.1) : 17.6
    }
    private static let path: [(Double, CGPoint)] = {
        var keys: [(Double, CGPoint)] = [(0, rest), (0.2, rest), (0.7, menuItem), (1.1, menuItem),
                                         (1.85, CGPoint(x: card(1).midX, y: card(1).midY)), (2.15, CGPoint(x: card(1).midX, y: card(1).midY))]
        for (step, window) in dragOrder.enumerated() {
            let p = press(step)
            keys += [(p - 0.05, grab(window)), (p + 0.1, grab(window)), (p + 0.8, drop(window)), (p + 1.0, drop(window))]
        }
        let tasks = CGPoint(x: cells[2].midX + 40, y: cells[2].midY + 60)
        keys += [(7.95, rest), (11.0, rest), (11.5, tasks), (11.75, tasks), (12.6, rest)]
        return keys
    }()

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Dip through the background so the loop restarts cleanly.
            if time < 18.0 { scene(time).opacity(1 - ramp(time, 17.6, 18.0)) } else { scene(0).opacity(ramp(time, 18.0, 18.4)) }
        }.frame(width: Self.canvas.width, height: Self.canvas.height)
            .background(Color(red: 0.055, green: 0.07, blue: 0.085)).preferredColorScheme(.dark)
    }

    private func scene(_ t: Double) -> some View {
        let slide = ramp(t, 14.9, 15.7)
        let shift = -Self.stage.width*slide
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 20).fill(Color(red: 0.08, green: 0.11, blue: 0.145))
                .frame(width: Self.stage.width, height: Self.stage.height).position(x: Self.stage.midX, y: Self.stage.midY)
            ZStack(alignment: .topLeading) {
                createDesktop(t).offset(x: shift)
                readDesktop.offset(x: shift + Self.stage.width)
            }.frame(width: Self.canvas.width, height: Self.canvas.height, alignment: .topLeading)
                .mask(RoundedRectangle(cornerRadius: 20).frame(width: Self.stage.width, height: Self.stage.height).position(x: Self.stage.midX, y: Self.stage.midY))
            menuBar(t)
            controlPanel(t)
            keystrokeHUD(t)
            cursor(t)
            captions(t)
        }.frame(width: Self.canvas.width, height: Self.canvas.height, alignment: .topLeading)
    }

    // MARK: Desktops

    private func createDesktop(_ t: Double) -> some View {
        let guides = ramp(t, 2.3, 2.65) * (1 - ramp(t, 7.15, 7.5))
        let cursor = cursorPoint(t)
        return ZStack(alignment: .topLeading) {
            ForEach(0..<3) { index in
                let cell = Self.cells[index]
                let hovering = dragging(t) != nil && cell.contains(cursor)
                RoundedRectangle(cornerRadius: 10).fill(palette[0].opacity(hovering ? 0.14 : 0))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(palette[0].opacity(hovering ? 0.95 : 0.6), style: StrokeStyle(lineWidth: 2, dash: [7, 6])))
                    .frame(width: cell.width, height: cell.height).position(x: cell.midX, y: cell.midY).opacity(guides)
            }
            ForEach(0..<3) { index in
                let frame = windowFrame(index, t)
                window(title: ["Draft", "Reading", "Tasks"][index], heading: ["Make room\nfor good ideas.", "A quieter\nworkspace.", "One thing\nat a time."][index],
                       body: ["A small project, a clear desk,\nand space to think.", "Keep the reference nearby.\nLet the work stay in focus.", "Sketch the idea\nBuild a first version\nTake a short break"][index],
                       accent: palette[index], lifted: dragging(t) == index)
                    .frame(width: frame.width, height: frame.height).position(x: frame.midX, y: frame.midY)
                    .zIndex(stackOrder(index, t))
            }
        }
    }

    private var readDesktop: some View {
        ZStack(alignment: .topLeading) {
            ForEach(0..<2) { index in
                let frame = Self.halves[index]
                window(title: ["Article", "Notes"][index], heading: ["Notes on\nslow mornings.", "Highlights"][index],
                       body: ["Start with one page.\nThe rest of the day can wait.", "Read before replying\nKeep one tab open\nWrite it down"][index],
                       accent: palette[index == 0 ? 2 : 1], lifted: false)
                    .frame(width: frame.width, height: frame.height).position(x: frame.midX, y: frame.midY)
            }
        }
    }

    private func window(title: String, heading: String, body: String, accent: Color, lifted: Bool) -> some View {
        // Overlaying on a flexible clear view keeps the window at its given size; overflow clips at the bottom.
        Color.clear.overlay(alignment: .topLeading) { VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                ForEach([Color.red, .yellow, .green], id: \.self) { color in Circle().fill(color.opacity(0.8)).frame(width: 7, height: 7) }
                Spacer()
                Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
            }.padding(13).background(.white.opacity(0.04))
            VStack(alignment: .leading, spacing: 16) {
                // Fixed height lets small windows clip their content like a real window instead of truncating text.
                Text(heading).font(.system(size: 27, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                Text(body).font(.system(size: 13)).foregroundStyle(.secondary).lineSpacing(7).fixedSize(horizontal: false, vertical: true)
                ForEach(0..<3) { row in
                    RoundedRectangle(cornerRadius: 3).fill(accent.opacity(0.14)).frame(width: CGFloat(140 + row*20), height: 7)
                }
                Spacer(minLength: 0)
            }.padding(22)
        } }
            .background(Color(red: 0.11, green: 0.14, blue: 0.17))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(lifted ? 0.22 : 0.12)))
            .shadow(color: .black.opacity(lifted ? 0.42 : 0.24), radius: lifted ? 24 : 14, y: lifted ? 14 : 8)
    }

    // MARK: Window motion

    private func dragging(_ t: Double) -> Int? {
        Self.dragOrder.enumerated().first { t >= Self.press($0.offset) && t < Self.press($0.offset) + 0.8 }?.element
    }

    private func stackOrder(_ index: Int, _ t: Double) -> Double {
        if index == 2 && t >= 11.6 { return 20 }
        guard let step = Self.dragOrder.firstIndex(of: index), t >= Self.press(step) else { return Double(index) }
        return 10 + Double(step)
    }

    private func windowFrame(_ index: Int, _ t: Double) -> CGRect {
        let step = Self.dragOrder.firstIndex(of: index)!
        let start = Self.starts[index], p = Self.press(step), grab = Self.grab(index)
        guard t >= p else { return start }
        let hand = t < p + 0.8 ? cursorPoint(t) : Self.drop(index)
        let carried = start.offsetBy(dx: hand.x - grab.x, dy: hand.y - grab.y)
        var frame = WindowTransition.frame(from: carried, to: Self.cells[index], progress: (t - p - 0.8)/0.35)
        for move in Self.moves where move.window == index && t >= move.start {
            frame = WindowTransition.frame(from: frame, to: move.target, progress: (t - move.start)/move.duration)
        }
        return frame
    }

    // MARK: Chrome

    private func menuBar(_ t: Double) -> some View {
        let name = t < 15.3 ? "Create" : "Read"
        let active = t >= 0.75 && t < 2.35
        return ZStack(alignment: .topLeading) {
            UnevenRoundedRectangle(topLeadingRadius: 20, topTrailingRadius: 20).fill(.black.opacity(0.35))
                .frame(width: Self.stage.width, height: 28).position(x: Self.stage.midX, y: Self.stage.minY + 14)
            Text("Tue 10:24").font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.85))
                .position(x: Self.stage.maxX - 46, y: Self.stage.minY + 14)
            HStack(spacing: 6) {
                Image(systemName: "rectangle.3.group")
                Text(name)
            }.font(.system(size: 12, weight: .medium)).foregroundStyle(.white)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(.white.opacity(active ? 0.2 : 0), in: RoundedRectangle(cornerRadius: 5))
                .frame(width: 100).position(Self.menuItem)
        }
    }

    private func controlPanel(_ t: Double) -> some View {
        let visible = ramp(t, 0.8, 1.05) * (1 - ramp(t, 2.15, 2.35))
        let panel = Self.panel
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 14).fill(Color(red: 0.13, green: 0.15, blue: 0.18).opacity(0.97))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.12)))
                .shadow(color: .black.opacity(0.45), radius: 26, y: 14)
                .frame(width: panel.width, height: panel.height).position(x: panel.midX, y: panel.midY)
            HStack(spacing: 8) {
                Image(systemName: "rectangle.3.group.fill").foregroundStyle(palette[0])
                Text("DeskNames").font(.system(size: 14, weight: .semibold))
            }.position(x: panel.minX + 68, y: panel.minY + 24)
            HStack(spacing: 0) {
                ForEach(0..<2) { tab in
                    let selected = tab == 0
                    Text(["Pane layouts", "Desktops"][tab]).font(.system(size: 12, weight: .medium))
                        .foregroundStyle(selected ? Color.white : .secondary)
                        .frame(width: (panel.width - 32)/2, height: 24)
                        .background(selected ? Color.white.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 6))
                }
            }.padding(2).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                .position(x: panel.midX, y: panel.minY + 62)
            layoutGrid(t)
        }.opacity(visible).scaleEffect(0.96 + 0.04*visible, anchor: UnitPoint(x: 0.75, y: 0))
    }

    private func layoutGrid(_ t: Double) -> some View {
        let chosen = t >= 1.95
        return ZStack(alignment: .topLeading) {
            ForEach(Array(PanePreset.allCases.enumerated()), id: \.offset) { index, preset in
                let card = Self.card(index)
                let selected = preset == .thirds ? chosen : (preset == .halves && !chosen)
                VStack(spacing: 5) {
                    glyph(preset, selected: selected).frame(width: card.width, height: card.height)
                    Text(preset.name).font(.system(size: 10)).foregroundStyle(selected ? palette[0] : .secondary).lineLimit(1)
                }.frame(width: card.width + 8).position(x: card.midX, y: card.midY + 10)
            }
        }
    }

    private func glyph(_ preset: PanePreset, selected: Bool) -> some View {
        let inner = CGRect(x: 8, y: 8, width: 76, height: 42)
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8).fill(.white.opacity(selected ? 0.1 : 0.04))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? palette[0] : .white.opacity(0.1), lineWidth: selected ? 2 : 1))
            ForEach(Array(preset.regions.enumerated()), id: \.offset) { _, region in
                let cell = CGRect(x: inner.minX + region.minX*inner.width, y: inner.minY + region.minY*inner.height,
                                  width: region.width*inner.width, height: region.height*inner.height).insetBy(dx: 1.5, dy: 1.5)
                RoundedRectangle(cornerRadius: 3).fill((selected ? palette[0] : Color.white).opacity(selected ? 0.55 : 0.22))
                    .frame(width: cell.width, height: cell.height).position(x: cell.midX, y: cell.midY)
            }
        }
    }

    private func cursor(_ t: Double) -> some View {
        let point = cursorPoint(t)
        let pressed = dragging(t) != nil || Self.clicks.contains { abs(t - $0) < 0.08 }
        let ripple = Self.clicks.map { (t - $0)/0.4 }.first { $0 >= 0 && $0 < 1 }
        return ZStack(alignment: .topLeading) {
            if let ripple {
                Circle().stroke(.white.opacity(0.55*(1 - ripple)), lineWidth: 2)
                    .frame(width: 14 + 30*ripple, height: 14 + 30*ripple).position(point)
            }
            Arrow().fill(.white).overlay(Arrow().stroke(.black, lineWidth: 1.2))
                .frame(width: 16, height: 24).scaleEffect(pressed ? 0.88 : 1, anchor: .topLeading)
                .shadow(color: .black.opacity(0.4), radius: 3, y: 2)
                .position(x: point.x + 8, y: point.y + 12)
            if dragging(t) != nil {
                Text("⌘").font(.system(size: 15, weight: .semibold)).frame(width: 28, height: 26)
                    .background(Color(white: 0.92), in: RoundedRectangle(cornerRadius: 6)).foregroundStyle(.black)
                    .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
                    .position(x: point.x + 34, y: point.y + 36)
            }
        }
    }

    private func captions(_ t: Double) -> some View {
        let labels = ["Choose a layout", "Command-drag", "Save", "Shortcuts", "Restore", "Switch desktops"]
        let step = [2.6, 7.6, 9.1, 13.1, 14.6].firstIndex { t < $0 } ?? 5
        return HStack(spacing: 6) {
            ForEach(0..<labels.count, id: \.self) { index in
                let active = index == step
                HStack(spacing: 7) {
                    Text("\(index + 1)").font(.system(size: 11, weight: .bold)).frame(width: 19, height: 19)
                        .background(active ? palette[0] : .white.opacity(0.12), in: Circle())
                        .foregroundStyle(active ? Color.black : .secondary)
                    Text(labels[index]).font(.system(size: 14, weight: active ? .semibold : .regular))
                        .foregroundStyle(active ? Color.white : .secondary)
                }.padding(.horizontal, 11).padding(.vertical, 7)
                    .background(active ? Color.white.opacity(0.08) : .clear, in: Capsule())
            }
            Spacer()
            Text("Illustrated demo · sample content").font(.system(size: 11)).foregroundStyle(.secondary)
        }.frame(width: Self.stage.width).position(x: Self.stage.midX, y: Self.stage.maxY + 44)
    }

    private func keystrokeHUD(_ t: Double) -> some View {
        let index = Self.keystrokes.lastIndex { t >= $0.time }
        let stroke = index.map { Self.keystrokes[$0] }
        let opacity = index.map { ramp(t, Self.keystrokes[$0].time, Self.keystrokes[$0].time + 0.12) * (1 - ramp(t, Self.keystrokeEnd($0) - 0.15, Self.keystrokeEnd($0))) } ?? 0
        let pressed = index.map { t - Self.keystrokes[$0].time < 0.14 } ?? false
        return HStack(spacing: 6) {
            ForEach(Array((stroke?.keys ?? []).enumerated()), id: \.offset) { _, key in
                Text(key).font(.system(size: 17, weight: .semibold)).frame(minWidth: 34, minHeight: 32)
                    .background(Color(white: 0.93), in: RoundedRectangle(cornerRadius: 7)).foregroundStyle(.black)
                    .shadow(color: .black.opacity(0.35), radius: pressed ? 1 : 3, y: pressed ? 1 : 3)
                    .offset(y: pressed ? 2 : 0)
            }
            Text(stroke?.label ?? "").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                .padding(.leading, (stroke?.keys.isEmpty ?? true) ? 4 : 8)
        }.padding(.horizontal, 14).padding(.vertical, 10)
            .background(Color(red: 0.06, green: 0.08, blue: 0.1).opacity(0.92), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(palette[0].opacity(0.35)))
            .shadow(color: .black.opacity(0.5), radius: 20, y: 10)
            .opacity(opacity).position(x: Self.stage.midX, y: Self.stage.maxY - 56)
    }

    // MARK: Timing

    private func cursorPoint(_ t: Double) -> CGPoint {
        let keys = Self.path
        guard let next = keys.firstIndex(where: { $0.0 > t }) else { return keys.last!.1 }
        guard next > 0 else { return keys[0].1 }
        let (t0, a) = keys[next - 1], (t1, b) = keys[next]
        let e = ramp(t, t0, t1)
        // Bow the path slightly, like a hand moving a mouse.
        let bow = sin(Double.pi*e)*0.08
        return CGPoint(x: a.x + (b.x - a.x)*e - (b.y - a.y)*bow, y: a.y + (b.y - a.y)*e + (b.x - a.x)*bow)
    }

    private func ramp(_ t: Double, _ start: Double, _ end: Double) -> Double {
        let x = min(1, max(0, (t - start)/(end - start)))
        return x < 0.5 ? 4*x*x*x : 1 - pow(-2*x + 2, 3)/2
    }
}

private struct Arrow: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width/16, h = rect.height/24
        var path = Path()
        for (x, y) in [(0.0, 0.0), (0, 19), (4.5, 15), (7.5, 22), (10.5, 20.5), (7.5, 14), (13.5, 14)] {
            let point = CGPoint(x: rect.minX + x*w, y: rect.minY + y*h)
            if path.isEmpty { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}
