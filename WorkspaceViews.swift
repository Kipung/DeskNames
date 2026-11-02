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
                    Button("Refresh") {controller.refresh()}
                }
                Toggle("Include current desktops on all connected screens",isOn:$controller.saveAcrossScreens).font(.system(size:12))
                Picker("Saved arrangement",selection:$controller.selectedLayoutID) {
                    Text("This desktop").tag("")
                    ForEach(controller.layouts.values.sorted{$0.savedAt>$1.savedAt}) {layout in
                        Text(layout.name ?? store.desktops.first(where:{$0.id==layout.id}).map(store.name) ?? "Saved arrangement").tag(layout.id)
                    }
                }.controlSize(.small)
                HStack(spacing:10) {
                    Button("Save current layout") {controller.save()}.buttonStyle(.borderedProminent)
                    Button("Restore layout") {controller.restore()}.buttonStyle(.bordered).disabled(controller.restoreSelection == nil)
                    if controller.busy {ProgressView().controlSize(.small)}
                }.disabled(controller.busy || !controller.trusted)
                if controller.busy {Button("Cancel operation") {controller.cancel()}}
                if controller.selectedDesktop != nil,let layout=controller.restoreSelection {
                    VStack(alignment:.leading,spacing:10) {
                        HStack {Image(systemName:"square.stack.3d.up.fill").foregroundStyle(palette[0]);Text("\(layout.windows.count) saved windows").fontWeight(.semibold);Spacer();Text(layout.savedAt,style:.time).foregroundStyle(.secondary)}
                        SavedLayoutPreview(layout:layout)
                        if layout.windows.contains(where:{$0.exactFrame==nil || $0.stackingIndex==nil || $0.displayProfile==nil}) {
                            Text("Older save: save the arrangement again to capture exact positions, monitor models and overlap order.").font(.caption).foregroundStyle(.orange)
                        }
                        Text(layout.windows.map{ $0.bundleID.split(separator:".").last.map(String.init) ?? $0.bundleID }.uniqued().joined(separator:" · ")).font(.system(size:11)).foregroundStyle(.secondary)
                        Toggle("Restore automatically when I enter this desktop",isOn:Binding(get:{controller.layouts[layout.id]?.autoRestore ?? false},set:{controller.option(\.autoRestore,$0,layoutID:layout.id)}))
                        Toggle("Open missing apps when restoring",isOn:Binding(get:{controller.layouts[layout.id]?.launchMissing ?? true},set:{controller.option(\.launchMissing,$0,layoutID:layout.id)}))
                        Toggle("Gather windows from other desktops on manual restore",isOn:Binding(get:{controller.layouts[layout.id]?.gatherWindows ?? false},set:{controller.option(\.gatherWindows,$0,layoutID:layout.id)}))
                        Text("Automatic restore keeps focus and restores positions on visible desktops. Use Restore layout to restore overlap order too. Gathering may switch desktops briefly. Unsaved documents and browser tabs are not recreated.").font(.system(size:11)).foregroundStyle(.secondary)
                    }.font(.system(size:12)).padding(15).background(.white.opacity(0.035),in:RoundedRectangle(cornerRadius:12))
                }
                Divider()
                HStack {Text("ARRANGE WINDOWS").font(.system(size:10,weight:.medium)).tracking(1.4).foregroundStyle(.secondary);Spacer();Button("Tile this desktop") {controller.tile()}.disabled(controller.busy || !controller.trusted)}
                HStack {Stepper("Columns: \(controller.columns)",value:$controller.columns,in:1...4);Stepper("Rows: \(controller.rows)",value:$controller.rows,in:1...4);Text("Gap");Slider(value:$controller.gap,in:0...32,step:2).frame(width:70)}.font(.system(size:11))
                Picker("Window",selection:$controller.selectedWindow) {
                    Text("Choose a window").tag(UInt32(0))
                    ForEach(controller.windows) {w in Text(String(w.label.prefix(70))).tag(w.id)}
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
                Text(controller.message).font(.system(size:12)).foregroundStyle(palette[0]).fixedSize(horizontal:false,vertical:true).textSelection(.enabled)
                Divider()
                Text("Manage shortcuts in Keyboard shortcuts.").font(.system(size:11,design:.monospaced)).foregroundStyle(.secondary)
                if !controller.shortcutStatus.isEmpty {Text(controller.shortcutStatus).font(.caption).foregroundStyle(.orange)}
            }.padding(.trailing,8)
        }.onAppear {controller.refresh()}
    }
}
extension Array where Element:Hashable {func uniqued()->[Element] {var seen=Set<Element>();return filter{seen.insert($0).inserted}}}

struct SwitcherView:View {
    @ObservedObject var store:Store
    let choose:(Desktop)->Void
    let close:()->Void
    @State private var search=""
    @State private var index=0
    @FocusState private var focused:Bool
    var filtered:[Desktop] {store.desktops.filter{search.isEmpty || store.name($0).localizedCaseInsensitiveContains(search) || String($0.number)==search}}
    var body:some View {
        VStack(alignment:.leading,spacing:14) {
            HStack {Image(systemName:"magnifyingglass");TextField("Jump to a desktop…",text:$search).textFieldStyle(.plain).focused($focused).onSubmit{select()};Text("esc").font(.caption).foregroundStyle(.secondary)}.font(.system(size:20)).padding(8)
            Divider()
            if filtered.isEmpty {Text("No matching desktops").foregroundStyle(.secondary).padding()}
            ForEach(Array(filtered.enumerated()),id:\.element.id) {i,d in
                Button {choose(d)} label:{HStack {Image(systemName:icons[store.style(d).color]).foregroundStyle(palette[store.style(d).color]).frame(width:24);Text(store.name(d));Spacer();if d.isCurrent {Text("Current").font(.caption).foregroundStyle(.secondary)};Text("\(d.number)").monospacedDigit().foregroundStyle(.secondary)}.padding(12).background(index==i ? Color.white.opacity(0.08):.clear,in:RoundedRectangle(cornerRadius:8))}.buttonStyle(.plain)
            }
        }.padding(20).frame(width:460).background(Color(red:0.09,green:0.11,blue:0.135)).preferredColorScheme(.dark)
        .onAppear{focused=true}.onChange(of:search){index=0}
        .onMoveCommand {direction in if direction == .down {index=max(0,min(index+1,filtered.count-1))};if direction == .up {index=max(0,index-1)}}
        .onExitCommand{close()}
    }
    func select(){if filtered.indices.contains(index){choose(filtered[index])}}
}
