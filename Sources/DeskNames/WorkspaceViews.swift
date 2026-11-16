import SwiftUI
import AppKit
import Carbon

struct LayoutView:View {
    @ObservedObject var controller:LayoutController
    @ObservedObject var store:Store
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:18) {
                if !controller.trusted {
                    VStack(alignment:.leading,spacing:9) {
                        Label("Allow DeskNames to arrange windows",systemImage:"hand.raised.fill").font(.headline)
                        Text("Enable DeskNames in System Settings → Privacy & Security → Accessibility. This lets it read window titles, move and resize windows, and use desktop shortcuts.").font(.system(size:12)).foregroundStyle(.secondary)
                        Button("Open Accessibility settings") {controller.native.requestPermission()}.buttonStyle(.borderedProminent)
                    }.padding(16).background(palette[0].opacity(0.1),in:RoundedRectangle(cornerRadius:12))
                }
                HStack {
                    Picker("Desktop",selection:$controller.targetDesktop) {ForEach(store.desktops.filter{!$0.isFullScreen}) {d in Text(store.name(d)).tag(d.id)}}
                    Button("Go") {if let d=controller.selectedDesktop {controller.switchTo(d)}}
                }
                VStack(alignment:.leading,spacing:12) {
                    HStack(spacing:10) {
                        Button(controller.restoreSelection == nil ? "Save this desktop's windows" : "Save again") {controller.save()}.buttonStyle(.borderedProminent)
                        Button("Restore now") {controller.restore()}.buttonStyle(.bordered).disabled(controller.restoreSelection == nil)
                        if controller.busy {ProgressView().controlSize(.small);Button("Cancel") {controller.cancel()}}
                    }.disabled(!controller.trusted)
                    if controller.selectedDesktop != nil,let layout=controller.restoreSelection {
                        SavedLayoutCard(controller:controller,layout:layout)
                    } else {
                        Text("Nothing saved for this desktop yet. Arrange its windows the way you like, then save. Automatic restore and the other options appear here once a layout is saved.").font(.system(size:12)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                    }
                    DisclosureGroup("More options") {
                        VStack(alignment:.leading,spacing:8) {
                            Toggle("Save the current desktop on every connected screen",isOn:$controller.saveAcrossScreens)
                            Picker("Restore from",selection:$controller.selectedLayoutID) {
                                Text("This desktop's own save").tag("")
                                ForEach(controller.layouts.values.sorted{$0.savedAt>$1.savedAt}) {layout in
                                    Text(layout.name ?? store.desktops.first(where:{$0.id==layout.id}).map(store.name) ?? "Saved arrangement").tag(layout.id)
                                }
                            }.controlSize(.small)
                        }.padding(.top,6)
                    }.font(.system(size:12))
                }.padding(15).background(.white.opacity(0.035),in:RoundedRectangle(cornerRadius:12))
                if controller.message != LayoutController.initialMessage {
                    Text(controller.message).font(.system(size:12)).foregroundStyle(palette[0]).fixedSize(horizontal:false,vertical:true).textSelection(.enabled)
                }
                DisclosureGroup("Arrange windows now") {
                    VStack(alignment:.leading,spacing:12) {
                        HStack {Stepper("Columns: \(controller.columns)",value:$controller.columns,in:1...4);Stepper("Rows: \(controller.rows)",value:$controller.rows,in:1...4);Text("Gap");Slider(value:$controller.gap,in:0...32,step:2).frame(width:70);Spacer();Button("Tile this desktop") {controller.tile()}.disabled(controller.busy || !controller.trusted)}.font(.system(size:11))
                        HStack {
                            Picker("Window",selection:$controller.selectedWindow) {
                                Text("Choose a window").tag(UInt32(0))
                                ForEach(controller.windows) {w in Text(String(w.label.prefix(70))).tag(w.id)}
                            }
                            Button("Refresh") {controller.refresh()}
                        }
                        HStack(spacing:12) {
                            VStack(spacing:5) {
                                ForEach(0..<controller.rows,id:\.self) {r in HStack(spacing:5) {
                                    ForEach(0..<controller.columns,id:\.self) {c in
                                        Button("\(r*controller.columns+c+1)") {controller.snap(r*controller.columns+c,columns:controller.columns,rows:controller.rows)}.frame(maxWidth:.infinity,minHeight:24).background(palette[0].opacity(0.1),in:RoundedRectangle(cornerRadius:5)).buttonStyle(.plain)
                                    }
                                }}
                            }.frame(width:180).padding(8).background(.white.opacity(0.035),in:RoundedRectangle(cornerRadius:9))
                            VStack(alignment:.leading,spacing:8) {
                                HStack {Button("Left half") {controller.snap(0,columns:2,rows:1)};Button("Right half") {controller.snap(1,columns:2,rows:1)}}
                                HStack {Button("Fill screen") {controller.snap(0,columns:1,rows:1)};Button("Move to desktop") {controller.moveSelected()}}
                                Text("Select a window, then a grid cell or desktop.").font(.system(size:10)).foregroundStyle(.secondary)
                            }.controlSize(.small)
                        }.disabled(controller.selectedWindow==0 || controller.busy || !controller.trusted)
                        WindowActionButtons(controller:controller)
                    }.padding(.top,8)
                }.font(.system(size:12,weight:.medium))
                if !controller.shortcutStatus.isEmpty {Text("Last shortcut: "+controller.shortcutStatus).font(.caption).foregroundStyle(.orange)}
            }.padding(.trailing,8)
        }.onAppear {controller.refresh()}
    }
}

/// One saved layout: what it holds and how it restores. Shared by Settings and the control panel.
struct SavedLayoutCard:View {
    @ObservedObject var controller:LayoutController
    let layout:DesktopLayout
    var body:some View {
        VStack(alignment:.leading,spacing:10) {
            HStack {Image(systemName:"square.stack.3d.up.fill").foregroundStyle(palette[0]);Text("\(layout.windows.count) saved windows").fontWeight(.semibold);Spacer();Text("Saved "+layout.savedAt.formatted(.relative(presentation:.named))).foregroundStyle(.secondary)}
            SavedLayoutPreview(layout:layout)
            if layout.stackingSource != DesktopLayout.currentStackingSource || layout.windows.contains(where:{$0.exactFrame==nil || $0.stackingIndex==nil || $0.displayProfile==nil}) {
                Text("Older save: save again to refresh exact positions, monitor models and overlap order.").font(.caption).foregroundStyle(.orange)
            }
            Text(layout.windows.map{ $0.bundleID.split(separator:".").last.map(String.init) ?? $0.bundleID }.uniqued().joined(separator:" · ")).font(.system(size:11)).foregroundStyle(.secondary).lineLimit(2)
            Toggle("Restore automatically when I enter this desktop",isOn:option(\.autoRestore,default:false))
            Toggle("Open missing apps when restoring",isOn:option(\.launchMissing,default:true))
            Toggle("Gather windows from other desktops on Restore now",isOn:option(\.gatherWindows,default:false))
            Text("Automatic restore keeps focus and only repositions windows already on the desktop. Restore now also restores overlap order. Unsaved documents and browser tabs are not recreated.").font(.system(size:11)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
        }.font(.system(size:12))
    }
    private func option(_ key:WritableKeyPath<DesktopLayout,Bool>,default fallback:Bool)->Binding<Bool> {
        Binding(get:{controller.layouts[layout.id]?[keyPath:key] ?? fallback},set:{controller.option(key,$0,layoutID:layout.id)})
    }
}
extension Array where Element:Hashable {func uniqued()->[Element] {var seen=Set<Element>();return filter{seen.insert($0).inserted}}}

struct SwitcherView: View {
    @ObservedObject var store: Store
    @ObservedObject var workspace: LayoutController
    @ObservedObject var preferences: PanePreferences
    @ObservedObject var models: MonitorPresets
    let desktop: Desktop?
    var updater: AppUpdater? = nil
    var loginItem: LoginItemController? = nil
    var pinCandidate: LiveWindow? = nil
    let choose: (Desktop) -> Void
    let close: () -> Void
    let openSettings: (SettingsPage?) -> Void
    @State private var search = ""
    @State private var index = 0
    @State var section = 0
    var sectionChanged: ((Int) -> Void)? = nil
    @State private var error = ""
    @FocusState private var focused: Bool

    private var presets: [PanePreset] {
        PanePreset.allCases.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
    }
    private var desktops: [Desktop] {
        store.desktops.filter { search.isEmpty || store.name($0).localizedCaseInsensitiveContains(search) || String($0.number) == search }
    }
    private var config: PaneConfiguration { workspace.paneConfiguration(for: desktop?.id ?? "") }
    private var available: Bool {
        guard let desktop else { return false }
        return !workspace.busy && !desktop.id.isEmpty && store.desktops.contains {
            $0.id == desktop.id && $0.display == desktop.display && $0.isCurrent && !$0.isFullScreen
        }
    }
    private var shared: Bool {
        guard let desktop else { return false }
        return models.configuration(on: desktop.display) != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "rectangle.3.group.fill").foregroundStyle(palette[0])
                Text("DeskNames").font(.system(size: 17, weight: .semibold))
                Spacer()
                Button("Settings") { openSettings(nil) }.buttonStyle(.plain).foregroundStyle(.secondary)
                Button("Quit") { NSApp.terminate(nil) }.buttonStyle(.plain).foregroundStyle(.secondary)
                    .help("Quit DeskNames (⌘Q)")
                Button(action: close) { Image(systemName: "xmark").padding(6) }
                    .buttonStyle(.plain).accessibilityLabel("Close control panel")
            }
            if !store.accessibilityGranted {
                HStack(spacing: 12) {
                    Image(systemName: "hand.raised.fill").foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Accessibility needed").font(.system(size: 13, weight: .semibold))
                        Text("Enable DeskNames in Accessibility. Approval is detected automatically; no relaunch needed.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button("Allow…") { workspace.native.requestPermission() }.buttonStyle(.borderedProminent)
                }.padding(12).background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            }
            Picker("Show", selection: $section) {
                Text("Pane layouts").tag(0)
                Text("Desktops").tag(1)
                Text("Saved windows").tag(2)
            }.pickerStyle(.segmented).labelsHidden()
            if section != 2 {
                HStack(spacing: 9) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField(section == 0 ? "Find a pane layout…" : "Jump to a desktop…", text: $search)
                        .textFieldStyle(.plain).focused($focused).onSubmit { select() }
                }.font(.system(size: 16)).padding(12)
                    .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
            }
            if section == 2 {
                savedWindows
                Spacer(minLength: 0)
            } else if section == 0 {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(desktop.map { "Layout for " + store.name($0) } ?? "No ordinary desktop available")
                            .font(.system(size: 14, weight: .semibold))
                        Text(shared ? "Shared with matching monitors" : "Current desktop")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(config.preset.name).font(.caption).foregroundStyle(palette[0])
                }
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                        ForEach(Array(presets.enumerated()), id: \.element.id) { i, preset in
                            presetButton(preset, at: i)
                        }
                    }.padding(2)
                    if presets.isEmpty { Text("No matching layouts").foregroundStyle(.secondary).padding() }
                }
                .disabled(!available)
                if !available {
                    Text(workspace.busy ? "Finish the window operation to choose a layout." : "Open this panel on an ordinary desktop to choose its layout.")
                        .font(.caption).foregroundStyle(.orange)
                } else {
                    Text("Choose guides for Command-drag. Existing windows stay in place.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 5) {
                            ForEach(Array(desktops.enumerated()), id: \.element.id) { i, d in
                                Button { choose(d) } label: {
                                    HStack {
                                        Image(systemName: icons[store.style(d).color]).foregroundStyle(palette[store.style(d).color]).frame(width: 24)
                                        Text(store.name(d))
                                        Spacer()
                                        if d.isCurrent { Text("Current").font(.caption).foregroundStyle(.secondary) }
                                        Text("\(d.number)").monospacedDigit().foregroundStyle(.secondary)
                                    }.padding(12).background(index == i ? Color.white.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 8))
                                }.buttonStyle(.plain).id(i)
                            }
                            if desktops.isEmpty { Text("No matching desktops").foregroundStyle(.secondary).padding() }
                        }
                    }.onChange(of: index) { proxy.scrollTo(index) }
                }
                PinControls(workspace: workspace, candidate: pinCandidate)
            }
            if !error.isEmpty { Text(error).font(.caption).foregroundStyle(.orange) }
            Divider()
            HStack {
                if section != 2 { Text("↑ ↓ ← →  Browse    ↩  Choose").font(.caption) }
                Spacer()
                Text("esc  Close").font(.caption)
            }.foregroundStyle(.secondary)
        }
        .padding(20).frame(width: 560, height: 620)
        .background(Color(red: 0.09, green: 0.11, blue: 0.135)).preferredColorScheme(.dark)
        .onAppear { focused = true; index = presets.firstIndex(of: config.preset) ?? 0 }
        .onChange(of: search) { index = 0; error = "" }
        .onChange(of: section) { sectionChanged?(section); search = ""; index = 0; error = ""; focused = true }
        .onKeyPress(.downArrow) { move(section == 0 ? 3 : 1); return .handled }
        .onKeyPress(.upArrow) { move(section == 0 ? -3 : -1); return .handled }
        .onKeyPress(.rightArrow) { if section == 0 && search.isEmpty { move(1); return .handled }; return .ignored }
        .onKeyPress(.leftArrow) { if section == 0 && search.isEmpty { move(-1); return .handled }; return .ignored }
        .onExitCommand(perform: close)
    }

    @ViewBuilder private var savedWindows: some View {
        let layout = desktop.flatMap { workspace.layouts[$0.id] }
        VStack(alignment: .leading, spacing: 12) {
            Text(desktop.map { "Windows on " + store.name($0) } ?? "No ordinary desktop available")
                .font(.system(size: 14, weight: .semibold))
            HStack(spacing: 10) {
                Button(layout == nil ? "Save this desktop's windows" : "Save again") {
                    if let desktop { workspace.targetDesktop = desktop.id; workspace.save(desktop) }
                }.buttonStyle(.borderedProminent)
                Button("Restore now") {
                    guard let desktop else { return }
                    close()
                    workspace.targetDesktop = desktop.id; workspace.selectedLayoutID = ""; workspace.restore()
                }.disabled(layout == nil)
                if workspace.busy { ProgressView().controlSize(.small) }
                Spacer()
                Button("More in Settings") { openSettings(.layouts) }.buttonStyle(.plain).foregroundStyle(.secondary).font(.caption)
            }.disabled(!available)
            if let layout {
                SavedLayoutCard(controller: workspace, layout: layout)
                    .padding(13).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
            } else {
                Text("Arrange this desktop's windows the way you like, then save. DeskNames can put them back whenever you return.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if workspace.message != LayoutController.initialMessage {
                Text(workspace.message).font(.caption).foregroundStyle(palette[0]).lineLimit(3)
            }
        }
    }

    private func presetButton(_ preset: PanePreset, at i: Int) -> some View {
        Button { apply(preset) } label: {
            VStack(alignment: .leading, spacing: 9) {
                PaneDiagram(configuration: PaneConfiguration(preset: preset, gap: 6), compact: true, hovered: nil, onHover: nil)
                    .frame(height: 48).accessibilityHidden(true)
                HStack {
                    Text(preset.name).font(.system(size: 11, weight: .medium))
                    Spacer(minLength: 0)
                    if config.preset == preset { Image(systemName: "checkmark.circle.fill").foregroundStyle(palette[0]) }
                }
            }.padding(11)
                .background(index == i ? palette[0].opacity(0.15) : .white.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(index == i ? palette[0] : .white.opacity(0.1), lineWidth: 1))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(preset.name + " pane layout")
            .accessibilityValue(config.preset == preset ? "Current layout" : "")
    }
    private func move(_ offset: Int) {
        guard section != 2 else { return }
        let count = section == 0 ? presets.count : desktops.count
        index = max(0, min(index + offset, count - 1))
    }
    private func select() {
        if section == 0, presets.indices.contains(index) { apply(presets[index]) }
        if section == 1, desktops.indices.contains(index) { choose(desktops[index]) }
    }
    private func apply(_ preset: PanePreset) {
        guard let desktop, workspace.choosePanePreset(preset, for: desktop) else {
            error = workspace.message; return
        }
        close()
    }
}
