import SwiftUI
import AppKit

struct SmartPanesView: View {
    @ObservedObject var workspace: LayoutController
    @ObservedObject var store: Store
    @ObservedObject var preferences: PanePreferences
    @ObservedObject var models: MonitorPresets
    @State private var desktopID = ""
    @State private var hoveredPane: Int?

    private var desktop: Desktop? {
        store.desktops.first { $0.id == desktopID && !$0.isFullScreen }
            ?? store.desktops.first { $0.isCurrent && !$0.isFullScreen }
    }
    private var config: PaneConfiguration { workspace.paneConfiguration(for: desktop?.id ?? "") }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 19) {
                HStack(spacing: 12) {
                    Image(systemName: "command").font(.system(size: 23, weight: .medium)).foregroundStyle(palette[0])
                        .frame(width: 48, height: 48).background(palette[0].opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 5) {
                        Toggle("Hold ⌘ while dragging to snap", isOn: Binding(get: { preferences.enabled }, set: preferences.setEnabled))
                            .font(.system(size: 14, weight: .semibold))
                        Text("Drag by the title bar. Release the mouse first, then Command.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                if !workspace.trusted {
                    HStack {
                        Label("Allow Accessibility to snap windows.", systemImage: "hand.raised")
                        Spacer()
                        Button("Open settings") { workspace.native.requestPermission() }
                    }.font(.system(size: 11)).padding(12)
                        .background(palette[3].opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                }
                Toggle("Snap at screen edges and corners",isOn:Binding(get:{preferences.edgeSnapping},set:preferences.setEdgeSnapping)).font(.system(size:12))
                HStack {
                    Picker("Layout for", selection: Binding(get: { desktop?.id ?? "" }, set: { desktopID = $0; hoveredPane = nil })) {
                        ForEach(store.desktops.filter { !$0.isFullScreen }) { d in Text(store.name(d)).tag(d.id) }
                    }.frame(maxWidth: 245)
                    Spacer()
                    if desktop?.isCurrent == true {
                        Label("Current desktop", systemImage: "circle.fill").font(.system(size: 10)).foregroundStyle(palette[0])
                    }
                    Button { if let desktop { workspace.previewPanes?(desktop.id) } } label: {
                        Label("Preview panes", systemImage: "rectangle.dashed")
                    }.disabled(workspace.busy || desktop?.isCurrent != true)
                }.controlSize(.small)

                if let desktop,let display=ConnectedDisplay.all().first(where:{$0.id==desktop.display}) {
                    Toggle("Share this preset with every \(display.profile.name) monitor",isOn:Binding(get:{models.values[display.profile.model]?.enabled ?? false},set:{models.set(display.profile,enabled:$0,configuration:config)})).font(.system(size:12))
                    Text("Matches the monitor model, not its serial number. Matching screens share the pane layout and spacing.").font(.caption).foregroundStyle(.secondary)
                }

                VStack(spacing: 0) {
                    HStack(spacing: 5) {
                        ForEach(0..<3) { _ in Circle().fill(.white.opacity(0.16)).frame(width: 6, height: 6) }
                        Spacer()
                        Text(config.preset.name).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: "display").foregroundStyle(.secondary).font(.system(size: 11))
                    }.padding(.horizontal, 14).frame(height: 29).background(.black.opacity(0.15))
                    PaneDiagram(configuration: config, compact: false, hovered: hoveredPane) { hoveredPane = $0 }
                        .frame(height: 178).padding(10)
                        .background(LinearGradient(colors: [palette[0].opacity(0.07), Color(red: 0.11, green: 0.13, blue: 0.18)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    HStack(spacing: 7) {
                        Image(systemName: "cursorarrow.motionlines")
                        Text("Layout preview · hold ⌘ while dragging a window to show full-screen panes")
                        Spacer()
                    }.font(.system(size: 10)).foregroundStyle(.secondary).padding(11)
                }.clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.1), lineWidth: 1))

                HStack {
                    Text("CHOOSE A LAYOUT").font(.system(size: 10, weight: .medium)).tracking(1.4).foregroundStyle(.secondary)
                    Spacer()
                    Text("Remembered for \(desktop.map(store.name) ?? "this desktop")").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                    ForEach(PanePreset.allCases) { preset in
                        Button { update(PaneConfiguration(preset: preset, gap: config.gap)); hoveredPane = nil } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                PaneDiagram(configuration: PaneConfiguration(preset: preset, gap: 6), compact: true,
                                            hovered: nil, onHover: nil).frame(height: 47)
                                HStack {
                                    Text(preset.name).font(.system(size: 11, weight: .medium))
                                    Spacer(minLength: 0)
                                    if config.preset == preset { Image(systemName: "checkmark.circle.fill").foregroundStyle(palette[0]) }
                                }
                            }.padding(10).background(config.preset == preset ? palette[0].opacity(0.1) : .white.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(config.preset == preset ? palette[0].opacity(0.7) : .white.opacity(0.08), lineWidth: 1))
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityLabel(preset.name + " pane layout")
                            .accessibilityValue(config.preset == preset ? "Selected" : "")
                    }
                }
                HStack(spacing: 12) {
                    Text("Space between panes").font(.system(size: 11))
                    Slider(value: Binding(get: { config.gap }, set: { update(PaneConfiguration(preset: config.preset, gap: $0)) }), in: 0...32, step: 2)
                        .frame(maxWidth: 200).accessibilityLabel("Space between panes")
                    Text("\(Int(config.gap)) pt").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).frame(width: 42)
                    Spacer()
                }
                HStack(alignment: .top, spacing: 22) {
                    instruction("1", "Grab a window", "Drag its title bar as usual.")
                    instruction("⌘", "Choose a pane", "Hold Command and move over it.")
                    instruction("3", "Release to fit", "Release the mouse, then Command.")
                }
                Text("Pane layouts guide dragging. Your saved window arrangements stay in Layouts & windows.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }.padding(.trailing, 8)
        }
    }

    private func update(_ config: PaneConfiguration) {
        guard let desktop else{return}
        if let display=ConnectedDisplay.all().first(where:{$0.id==desktop.display}),models.values[display.profile.model]?.enabled == true {
            models.set(display.profile,enabled:true,configuration:config)
        } else {preferences.set(config, for: desktop.id)}
    }
    private func instruction(_ number: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(number).font(.system(size: 11, weight: .semibold)).foregroundStyle(palette[0])
                .frame(width: 24, height: 24).background(palette[0].opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 11, weight: .semibold))
                Text(detail).font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PaneDiagram: View {
    let configuration: PaneConfiguration
    let compact: Bool
    let hovered: Int?
    let onHover: ((Int?) -> Void)?
    var body: some View {
        GeometryReader { proxy in
            let geometry = PaneGeometry(area: CGRect(origin: .zero, size: proxy.size),
                                        configuration: PaneConfiguration(preset: configuration.preset, gap: compact ? 4 : max(3, configuration.gap/2)))
            ZStack(alignment: .topLeading) {
                ForEach(geometry.cells.indices, id: \.self) { i in
                    let frame = geometry.cells[i]
                    RoundedRectangle(cornerRadius: compact ? 3 : 9)
                        .fill(palette[0].opacity(hovered == i ? 0.20 : (compact ? 0.18 : 0.055)))
                        .overlay(RoundedRectangle(cornerRadius: compact ? 3 : 9).stroke(palette[0].opacity(hovered == i ? 0.95 : 0.35), lineWidth: hovered == i ? 2 : 1))
                        .overlay {
                            if !compact {
                                VStack(spacing: 7) {
                                    Text("\(i+1)").font(.system(size: 15, weight: .semibold, design: .rounded))
                                        .foregroundStyle(hovered == i ? palette[0] : .white.opacity(0.8))
                                        .frame(width: 34, height: 34).background(.white.opacity(0.045), in: Circle())
                                    Text("Pane \(i+1)").font(.system(size: 10)).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .frame(width: frame.width, height: frame.height).position(x: frame.midX, y: frame.midY)
                        .onHover { inside in onHover?(inside ? i : nil) }
                }
            }
        }.allowsHitTesting(!compact)
    }
}

struct PaneOverlayView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let geometry: PaneGeometry
    let hovered: Int?
    let title: String
    let previewOnly: Bool
    var edgeSnap = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(geometry.cells.indices, id: \.self) { i in
                let rect = geometry.cells[i].offsetBy(dx: -geometry.area.minX, dy: -geometry.area.minY)
                RoundedRectangle(cornerRadius: 15)
                    .fill(palette[0].opacity(hovered == i ? 0.16 : 0.035))
                    .overlay(RoundedRectangle(cornerRadius: 15).stroke(palette[0].opacity(hovered == i ? 1 : 0.45), lineWidth: hovered == i ? 3 : 1.5))
                    .overlay {
                        VStack(spacing: 9) {
                            Text("\(i+1)").font(.system(size: 24, weight: .semibold, design: .rounded))
                                .foregroundStyle(hovered == i ? palette[0] : .white)
                                .frame(width: 64, height: 64).background(.ultraThinMaterial, in: Circle())
                                .overlay(Circle().stroke(.white.opacity(0.16), lineWidth: 1))
                            Text(hovered == i ? "Release to fit" : "Pane \(i+1)").font(.system(size: 12, weight: .medium))
                                .padding(.horizontal, 11).padding(.vertical, 5).background(.ultraThinMaterial, in: Capsule())
                        }
                    }
                    .frame(width: rect.width, height: rect.height).position(x: rect.midX, y: rect.midY)
            }
            VStack {
                Spacer()
                HStack(spacing: 13) {
                    Image(systemName: "rectangle.split.2x2").foregroundStyle(palette[0])
                    Text(title).fontWeight(.semibold)
                    Divider().frame(height: 17)
                    Text(previewOnly ? "Preview · closes in 4 seconds" : edgeSnap ? "Release the mouse to snap" : "⌘ held · release the mouse to snap")
                        .foregroundStyle(.secondary)
                    Text("esc").font(.system(size: 10, design: .monospaced)).padding(5)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                }.font(.system(size: 12)).padding(.horizontal, 18).padding(.vertical, 12)
                    .background(.regularMaterial, in: Capsule()).overlay(Capsule().stroke(.white.opacity(0.13), lineWidth: 1))
                    .padding(.bottom, 22)
            }.frame(width: geometry.area.width, height: geometry.area.height)
        }.frame(width: geometry.area.width, height: geometry.area.height)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovered)
            .preferredColorScheme(.dark)
    }
}

struct PaneResultView: View {
    let text: String
    let success: Bool
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: success ? "checkmark.circle.fill" : "info.circle.fill").foregroundStyle(success ? palette[0] : palette[3])
            Text(text).font(.system(size: 12, weight: .medium)).lineLimit(2)
        }.padding(15).frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.regularMaterial, in: Capsule()).preferredColorScheme(.dark)
    }
}
