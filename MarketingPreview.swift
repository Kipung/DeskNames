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
    for frame in 0..<96 {
        let progress = min(1, max(0, Double(frame-24)/30))
        try renderFixture(PaneDemoFrame(progress: progress, showGuides: frame >= 12 && frame < 60),
                          size: CGSize(width: 1120, height: 720), to: directory.appendingPathComponent(String(format: "frame-%03d.png", frame)))
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

private struct PaneDemoFrame: View {
    let progress: Double
    let showGuides: Bool
    private let area = CGRect(x: 0, y: 0, width: 1024, height: 480)
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Label("DeskNames", systemImage: "rectangle.3.group.fill").font(.system(size: 24, weight: .semibold))
                Spacer()
                Text("A place for every window.").font(.system(size: 18)).foregroundStyle(.secondary)
            }
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 20).fill(Color(red: 0.08, green: 0.12, blue: 0.15))
                let geometry = PaneGeometry(area: area, configuration: PaneConfiguration(preset: .thirds, gap: 10))
                ForEach(0..<3) { index in
                    let target = geometry.cells[index]
                    let start = CGRect(x: CGFloat(90 + index*145), y: CGFloat(45 + index*35), width: 440, height: 310)
                    let frame = WindowTransition.frame(from: start, to: target, progress: progress)
                    if showGuides {
                        RoundedRectangle(cornerRadius: 10).stroke(palette[0].opacity(0.65), style: StrokeStyle(lineWidth: 2, dash: [7, 6]))
                            .frame(width: target.width, height: target.height).position(x: target.midX, y: target.midY)
                    }
                    sampleWindow(index).frame(width: frame.width, height: frame.height)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.12)))
                        .shadow(color: .black.opacity(0.24), radius: 14, y: 8)
                        .position(x: frame.midX, y: frame.midY)
                }
            }.frame(width: area.width, height: area.height)
            HStack {
                Label(progress < 1 ? "Choose a layout. Fit your windows." : "Room to create, read, and plan.", systemImage: progress < 1 ? "command" : "checkmark.circle.fill")
                    .font(.system(size: 19, weight: .medium)).foregroundStyle(palette[0])
                Spacer()
                Text("Illustrated demo · sample content").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }.padding(48).frame(width: 1120, height: 720)
            .background(Color(red: 0.055, green: 0.07, blue: 0.085)).preferredColorScheme(.dark)
    }
    private func sampleWindow(_ index: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                ForEach([Color.red, .yellow, .green], id: \.self) { color in Circle().fill(color.opacity(0.8)).frame(width: 7, height: 7) }
                Spacer()
                Text(["Draft", "Reading", "Tasks"][index]).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
            }.padding(13).background(.white.opacity(0.04))
            VStack(alignment: .leading, spacing: 16) {
                Text(["Make room\nfor good ideas.", "A quieter\nworkspace.", "One thing\nat a time."][index]).font(.system(size: 27, weight: .semibold))
                Text(["A small project, a clear desk,\nand space to think.", "Keep the reference nearby.\nLet the work stay in focus.", "Sketch the idea\nBuild a first version\nTake a short break"][index]).font(.system(size: 13)).foregroundStyle(.secondary).lineSpacing(7)
                ForEach(0..<3) { row in
                    RoundedRectangle(cornerRadius: 3).fill(palette[index].opacity(0.09)).frame(width: CGFloat(140+row*20), height: 7)
                }
                Spacer(minLength: 0)
            }.padding(22)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(red: 0.11, green: 0.14, blue: 0.17))
    }
}
