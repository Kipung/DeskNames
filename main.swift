import AppKit
import SwiftUI
import Darwin

struct Desktop: Identifiable, Equatable {
    let id: String
    let spaceID: UInt64
    let display: String
    let position: Int
    let number: Int
    let isCurrent: Bool
    let isFullScreen: Bool
}
struct Appearance: Codable, Equatable {
    var name: String
    var color: Int
}
let palette: [Color] = [.init(red:0.37,green:0.85,blue:0.73), .init(red:0.55,green:0.67,blue:1), .init(red:0.81,green:0.64,blue:1), .init(red:1,green:0.72,blue:0.43), .init(red:1,green:0.55,blue:0.65)]
let icons = ["briefcase", "sparkle.magnifyingglass", "curlybraces", "sun.max", "leaf"]

final class SpaceReader {
    typealias Connection = @convention(c) () -> Int32
    typealias CopySpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?
    private let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW)
    func read() -> [Desktop] {
        guard let handle, let cp = dlsym(handle,"CGSMainConnectionID"), let sp = dlsym(handle,"CGSCopyManagedDisplaySpaces") else { return [] }
        let connection = unsafeBitCast(cp,to:Connection.self)()
        guard let raw = unsafeBitCast(sp,to:CopySpaces.self)(connection)?.takeRetainedValue() as? [[String:Any]] else { return [] }
        var result: [Desktop] = []; var number = 0
        for display in raw {
            let displayID = display["Display Identifier"] as? String ?? "Main"
            let current = (display["Current Space"] as? [String:Any])?["ManagedSpaceID"] as? NSNumber
            for (position,item) in (display["Spaces"] as? [[String:Any]] ?? []).enumerated() {
                guard let id = item["ManagedSpaceID"] as? NSNumber, let uuid = item["uuid"] as? String else { continue }
                number += 1
                result.append(Desktop(id:uuid,spaceID:id.uint64Value,display:displayID,position:position,number:number,isCurrent:id==current,isFullScreen:(item["type"] as? Int ?? 0) != 0))
            }
        }
        return result
    }
}

final class Store: ObservableObject {
    @Published var desktops: [Desktop] = []
    @Published var appearance: [String:Appearance] = [:]
    @Published var enabled = true { didSet { defaults.set(enabled,forKey:"labelsEnabled") } }
    @Published var vertical: Double = 0 { didSet { if !(-100...100).contains(vertical) { vertical=min(max(vertical.isFinite ? vertical : 0,-100),100) }; defaults.set(vertical,forKey:"vertical") } }
    @Published var horizontal: Double = 0 { didSet { if !(-600...600).contains(horizontal) { horizontal=min(max(horizontal.isFinite ? horizontal : 0,-600),600) }; defaults.set(horizontal,forKey:"horizontal") } }
    @Published var spacing: Double = 1 { didSet { if !(0.3...1.5).contains(spacing) { spacing=min(max(spacing.isFinite ? spacing : 1,0.3),1.5) }; defaults.set(spacing,forKey:"spacing") } }
    @Published var missionControl = false
    @Published var accessibilityGranted = AXIsProcessTrusted()
    let defaults: UserDefaults
    let reader = SpaceReader()
    var onChange: (() -> Void)?
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey:"desktopAppearance"), let saved = try? JSONDecoder().decode([String:Appearance].self,from:data) { appearance = saved }
        enabled = defaults.object(forKey:"labelsEnabled") as? Bool ?? true
        vertical = defaults.double(forKey:"vertical")
        horizontal = defaults.double(forKey:"horizontal")
        spacing = defaults.object(forKey:"spacing") as? Double ?? 1
        refresh()
    }
    func refresh() {
        let next = reader.read()
        if desktops != next { desktops = next; onChange?() }
    }
    func style(_ d:Desktop) -> Appearance {
        var value=appearance[d.id] ?? Appearance(name:d.isFullScreen ? "Full screen" : "Desktop \(d.number)",color:(d.number-1)%palette.count)
        // Saved preferences may hold a color index outside the palette; never index out of range.
        value.color=max(0,min(value.color,palette.count-1))
        return value
    }
    func name(_ d:Desktop) -> String { let n=style(d).name.trimmingCharacters(in:.whitespacesAndNewlines); return n.isEmpty ? "Desktop \(d.number)" : n }
    func update(_ d:Desktop,name:String?=nil,color:Int?=nil) {
        var value=style(d)
        if let name { value.name=String(name.prefix(40)) }
        if let color { value.color=max(0,min(color,palette.count-1)) }
        appearance[d.id]=value
        if let data=try? JSONEncoder().encode(appearance) { defaults.set(data,forKey:"desktopAppearance") }
        onChange?()
    }
    func starterNames() {
        let names=["Work","Research","Code","Personal","Focus"]
        for (i,d) in desktops.filter({!$0.isFullScreen}).enumerated() where appearance[d.id] == nil { update(d,name:names[i%names.count],color:i%palette.count) }
    }
}

struct NamePill: View {
    let number:Int; let name:String; let color:Color; let current:Bool
    var body: some View {
        HStack(spacing:8) {
            Text(String(format:"%02d",number)).font(.system(size:11,weight:.bold,design:.monospaced)).foregroundStyle(color)
            Text(name).font(.system(size:13,weight:.semibold)).lineLimit(1)
            if current { Circle().fill(color).frame(width:5,height:5) }
        }.padding(.horizontal,13).padding(.vertical,8)
        .background(Color(red:0.09,green:0.12,blue:0.15),in:Capsule())
        .overlay(Capsule().strokeBorder(color.opacity(current ? 0.9 : 0.4),lineWidth:1))
        .foregroundStyle(.white)
    }
}

struct MainView: View {
    @ObservedObject var store:Store
    @ObservedObject var workspace:LayoutController
    @ObservedObject var shortcuts:ShortcutSettings = ShortcutSettings()
    @State var page=0
    var body: some View {
        GeometryReader { geometry in
        let compact = geometry.size.width < 850
        HStack(spacing:0) {
            VStack(alignment:.leading,spacing:0) {
                HStack(spacing:10) {
                    Image(systemName:"rectangle.3.group.fill").font(.system(size:23)).foregroundStyle(palette[0])
                    if !compact { Text("DeskNames").font(.system(size:19,weight:.semibold)) }
                }.padding(.top,34)
                if !compact { Text("A place for everything.").font(.system(size:12)).foregroundStyle(.white.opacity(0.45)).padding(.top,10) }
                VStack(spacing:7) {
                    nav("Your desktops",icon:"rectangle.3.group",selected:page==0,compact:compact) { page=0 }
                    nav("Layouts & windows",icon:"square.grid.2x2",selected:page==1,compact:compact) { page=1 }
                    nav("Smart panes",icon:"rectangle.split.2x2",selected:page==4,compact:compact) { page=4 }
                    nav("Window routing",icon:"arrow.up.forward.app",selected:page==5,compact:compact) {page=5}
                    nav("Keyboard shortcuts",icon:"keyboard",selected:page==3,compact:compact) { page=3 }
                    nav("Label settings",icon:"slider.horizontal.3",selected:page==2,compact:compact) { page=2 }
                }.padding(.top,38)
                Spacer()
                if !compact {
                Circle().fill(palette[0]).frame(width:7,height:7)
                Text("Made for your Mac.").font(.system(size:13,weight:.medium)).padding(.top,12)
                Text("Free. Open source.\nNames stay on this Mac.").font(.system(size:12)).foregroundStyle(.white.opacity(0.43)).lineSpacing(5).padding(.top,8)
                Text("\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "DEV") · BUILD \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—")").font(.system(size:9,weight:.medium,design:.monospaced)).tracking(1.4).foregroundStyle(.white.opacity(0.3)).padding(.top,25).padding(.bottom,30)
                }
            }.padding(.horizontal,compact ? 12 : 24).frame(width:compact ? 72 : 212).background(Color(red:0.065,green:0.085,blue:0.105))
            VStack(alignment:.leading,spacing:20) {
                HStack {
                    VStack(alignment:.leading,spacing:8) {
                        Text(page==5 ? "New windows, right where they belong." : page==4 ? "Make room for your work." : page==3 ? "Your keys. Your choice." : page==2 ? "Make them yours." : (page==1 ? "Your workspace, remembered." : "Give your desktops a name.")).font(.system(size:27,weight:.semibold))
                        Text(page==5 ? "Send newly opened windows to the desktop you choose." : page==4 ? "Pick your panes. Hold Command. Drop into place." : page==3 ? "Set shortcuts for your everyday actions." : page==2 ? "Fine-tune your Mission Control labels." : (page==1 ? "Save, restore, and arrange your windows." : "Less searching. More room to think.")).font(.system(size:13)).foregroundStyle(.white.opacity(0.48))
                    }
                    Spacer()
                    Text("\(store.desktops.count) SPACES").font(.system(size:10,weight:.semibold,design:.monospaced)).tracking(1).foregroundStyle(palette[0]).padding(9).background(palette[0].opacity(0.1),in:Capsule())
                }
                if page==5 { WindowRoutingView(controller:workspace,store:store,settings:workspace.routing) } else if page==4 { SmartPanesView(workspace:workspace,store:store,preferences:workspace.panes,models:workspace.monitorPresets) } else if page==3 { ShortcutSettingsView(settings:shortcuts,workspace:workspace) } else if page==2 { settingsView } else if page==1 { LayoutView(controller:workspace,store:store) } else { desktopsView }
                Spacer(minLength:0)
                HStack(spacing:7) {
                    Image(systemName:"checkmark.circle.fill").foregroundStyle(palette[0])
                    Text("Saved automatically").foregroundStyle(.white.opacity(0.45))
                    Spacer()
                    Text(store.missionControl ? "Mission Control is open" : "Names follow your desktops").foregroundStyle(.white.opacity(0.3))
                }.font(.system(size:11))
            }.padding(30)
                .frame(maxWidth:1060,maxHeight:900)
                .frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.top)
                .background(Color(red:0.09,green:0.11,blue:0.135))
        }
        }.frame(minWidth:640,minHeight:520).preferredColorScheme(.dark)
    }
    func nav(_ title:String,icon:String,selected:Bool,compact:Bool=false,action:@escaping()->Void)->some View {
        Button(action:action) { HStack(spacing:10) { Image(systemName:icon).frame(width:17); if !compact { Text(title); Spacer() } }.font(.system(size:12,weight:.medium)).padding(12).foregroundStyle(selected ? palette[0] : .white.opacity(0.5)).background(selected ? palette[0].opacity(0.1) : .clear,in:RoundedRectangle(cornerRadius:9)) }.buttonStyle(.plain).help(title).accessibilityLabel(title)
    }
    var desktopsView: some View {
        VStack(alignment:.leading,spacing:16) {
            HStack { Text("YOUR DESKTOPS").tracking(1.6); Spacer(); Button("Control panel") {workspace.showSwitcher?()}; Text("Click a name to edit") }.font(.system(size:10,weight:.medium)).foregroundStyle(.white.opacity(0.4))
            ScrollView {
                VStack(spacing:8) {
                    ForEach(store.desktops) { d in
                        let style=store.style(d); let color=palette[style.color]
                        HStack(spacing:13) {
                            ZStack { RoundedRectangle(cornerRadius:10).fill(color.opacity(0.12)); Image(systemName:icons[style.color]).font(.system(size:18)).foregroundStyle(color) }.frame(width:43,height:43)
                            VStack(alignment:.leading,spacing:4) {
                                TextField("Desktop \(d.number)",text:Binding(get:{store.style(d).name},set:{store.update(d,name:$0)})).textFieldStyle(.plain).font(.system(size:15,weight:.semibold)).accessibilityLabel("Name for desktop \(d.number)")
                                Text(d.isFullScreen ? "FULL SCREEN" : "DESKTOP \(String(format:"%02d",d.number))").font(.system(size:9,weight:.medium,design:.monospaced)).tracking(1.5).foregroundStyle(.white.opacity(0.32))
                            }
                            if d.isCurrent { Text("Current").font(.system(size:10,weight:.medium)).foregroundStyle(color).padding(.horizontal,9).padding(.vertical,5).background(color.opacity(0.08),in:Capsule()) }
                            Menu { ForEach(0..<palette.count,id:\.self) { i in Button(["Mint","Blue","Lilac","Amber","Rose"][i]) {store.update(d,color:i)} } } label: { Circle().fill(color).frame(width:10,height:10) }.menuStyle(.borderlessButton).frame(width:25).accessibilityLabel("Color for desktop \(d.number)")
                        }.padding(12).background(Color.white.opacity(0.025),in:RoundedRectangle(cornerRadius:12)).overlay(RoundedRectangle(cornerRadius:12).strokeBorder(d.isCurrent ? color.opacity(0.4) : .white.opacity(0.055)))
                    }
                }
            }.frame(maxHeight:390)
            HStack(alignment:.top,spacing:12) {
                Image(systemName:"rectangle.topthird.inset.filled").foregroundStyle(palette[0]).font(.system(size:19))
                VStack(alignment:.leading,spacing:5) {
                    HStack { Text("Meet your Mission Control labels").font(.system(size:12,weight:.semibold)); Spacer(); Button("Open") { NSWorkspace.shared.open(URL(fileURLWithPath:"/System/Applications/Mission Control.app")) }.buttonStyle(.bordered).controlSize(.small) }
                    Text("Open Mission Control and hover over the desktops at the top. Your names appear as colored labels.").font(.system(size:11)).foregroundStyle(.white.opacity(0.45)).fixedSize(horizontal:false,vertical:true).lineSpacing(3)
                }
                Spacer()
            }.padding(16).background(palette[0].opacity(0.045),in:RoundedRectangle(cornerRadius:12))
        }
    }
    var settingsView: some View {
        VStack(alignment:.leading,spacing:22) {
            Toggle("Show labels in Mission Control",isOn:$store.enabled).toggleStyle(.switch).tint(palette[0])
            HStack { Spacer(); NamePill(number:1,name:"Work",color:palette[0],current:true); Spacer() }.padding(24).background(.white.opacity(0.025),in:RoundedRectangle(cornerRadius:12))
            Text("ALIGNMENT").font(.system(size:10,weight:.medium)).tracking(1.5).foregroundStyle(.white.opacity(0.4))
            Text("Automatic alignment").font(.system(size:14,weight:.semibold))
            Text("Names follow your desktop thumbnails as Mission Control changes. Labels appear when the expanded strip settles.").font(.system(size:12)).foregroundStyle(.white.opacity(0.55)).fixedSize(horizontal:false,vertical:true)
            if !store.accessibilityGranted {
                Text("Allow DeskNames in System Settings → Privacy & Security → Accessibility to align labels with your desktops.").font(.system(size:12)).foregroundStyle(palette[3]).fixedSize(horizontal:false,vertical:true)
            }
            Divider()
            Text("Early preview · macOS 26\nExpanded desktop strip supported. Full-screen Spaces keep their native labels.").font(.system(size:12)).foregroundStyle(.white.opacity(0.4)).lineSpacing(5)
            Button("Quit DeskNames") { NSApp.terminate(nil) }.buttonStyle(.bordered)
        }
    }
}

final class LabelPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
@MainActor final class OverlayController {
    let store: Store
    var panels: [String: LabelPanel] = [:]
    var rendered: [String: String] = [:]
    var widths: [String: Double] = [:]
    private let queue = DispatchQueue(label: "local.desknames.mission-control", qos: .userInitiated)
    private let reader = MissionControlReader()
    private let diagnostics = AlignmentDiagnostics()
    private var inFlight = false
    private var epoch: UInt64 = 0
    private var generation: MissionControlGeneration?
    private var stability = MissionControlStability()
    private var visibleSampleTime: TimeInterval = 0

    init(_ store: Store) { self.store = store }

    static func isMissionControlOpen() -> Bool {
        let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, 0) as? [[String: Any]] ?? []
        return windows.contains { window in
            let owner = window[kCGWindowOwnerName as String] as? String ?? ""
            let layer = window[kCGWindowLayer as String] as? Int ?? 0
            return (owner == "Dock" && layer == 18) || (owner == "WindowManager" && layer == 19)
        }
    }

    private func currentGeneration() -> MissionControlGeneration? {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return nil }
        let screens = MissionControlScreen.current()
        guard !screens.isEmpty else { return nil }
        return MissionControlGeneration(dockPID: dock.processIdentifier, screens: screens, slots: MissionControlSlot.snapshot(store.desktops))
    }

    func tick() {
        let open = Self.isMissionControlOpen()
        if store.missionControl != open { store.missionControl = open }
        let trusted = AXIsProcessTrusted()
        if store.accessibilityGranted != trusted { store.accessibilityGranted = trusted }
        guard open, store.enabled, trusted, let current = currentGeneration() else {
            invalidate()
            if store.defaults.bool(forKey: "alignmentDiagnosticsEnabled") {
                diagnostics.record(enabled: true, open: open, labelsEnabled: store.enabled, trusted: trusted, generation: currentGeneration(), capture: nil, placements: [], panels: panels)
            }
            return
        }
        if generation != current {
            invalidate()
            generation = current
        }
        let now = ProcessInfo.processInfo.systemUptime
        if now - visibleSampleTime > MissionControlStability.maximumAge {
            reconcile([])
        }
        guard !inFlight else { return }
        inFlight = true
        let requestEpoch = epoch
        let reader = self.reader
        queue.async { [weak self] in
            let capture = reader.capture(current)
            DispatchQueue.main.async {
                guard let self else { return }
                self.inFlight = false
                guard requestEpoch == self.epoch else { return }
                self.store.refresh()
                let stillOpen = Self.isMissionControlOpen()
                let trusted = AXIsProcessTrusted()
                let latest = self.currentGeneration()
                guard stillOpen, self.store.enabled, trusted, latest == current, capture.orderMatches else {
                    self.invalidate()
                    self.diagnostics.record(enabled: self.store.defaults.bool(forKey: "alignmentDiagnosticsEnabled"), open: stillOpen, labelsEnabled: self.store.enabled, trusted: trusted, generation: latest, capture: capture, placements: [], panels: self.panels)
                    return
                }
                let candidates = MissionControlGeometry.placements(strips: capture.strips, generation: current)
                let accepted = self.stability.accept(candidates, generation: current, current: latest, sampledAt: capture.sampledAt, now: ProcessInfo.processInfo.systemUptime)
                self.reconcile(accepted)
                self.visibleSampleTime = accepted.isEmpty ? 0 : capture.sampledAt
                self.diagnostics.record(enabled: self.store.defaults.bool(forKey: "alignmentDiagnosticsEnabled"), open: stillOpen, labelsEnabled: self.store.enabled, trusted: trusted, generation: latest, capture: capture, placements: accepted, panels: self.panels)
            }
        }
    }

    private func invalidate() {
        epoch &+= 1
        generation = nil
        stability.reset()
        visibleSampleTime = 0
        reconcile([])
    }

    private func reconcile(_ placements: [MissionControlPlacement]) {
        let visible = Set(placements.map(\.desktopID))
        for (id, panel) in panels where panel.isVisible && !visible.contains(id) { panel.orderOut(nil) }
        for placement in placements {
            guard let desktop = store.desktops.first(where: { $0.id == placement.desktopID && !$0.isFullScreen }) else { continue }
            let style = store.style(desktop)
            let signature = "\(desktop.number)|\(store.name(desktop))|\(style.color)|\(desktop.isCurrent)"
            let panel: LabelPanel
            if let existing = panels[desktop.id] { panel = existing } else {
                panel = LabelPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                panel.isOpaque = false
                panel.backgroundColor = .clear
                panel.hasShadow = false
                panel.ignoresMouseEvents = true
                panel.level = .screenSaver
                panel.hidesOnDeactivate = false
                panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
                panels[desktop.id] = panel
            }
            if rendered[desktop.id] != signature {
                let view = NSHostingView(rootView: NamePill(number: desktop.number, name: store.name(desktop), color: palette[style.color], current: desktop.isCurrent))
                panel.contentView = view
                rendered[desktop.id] = signature
                widths[desktop.id] = view.fittingSize.width
            }
            panel.setFrame(placement.labelFrame(fittingWidth: widths[desktop.id] ?? 120), display: true)
            panel.orderFrontRegardless()
        }
        let live = Set(store.desktops.filter { !$0.isFullScreen }.map(\.id))
        for key in Array(panels.keys) where !live.contains(key) {
            panels.removeValue(forKey: key)?.close()
            rendered.removeValue(forKey: key)
            widths.removeValue(forKey: key)
        }
    }
}

@MainActor final class AppDelegate:NSObject,NSApplicationDelegate {
    let store=Store()
    var window:NSWindow!
    var item:NSStatusItem!
    var overlay:OverlayController!
    var timer:Timer?
    private var lastDesktopRefresh: TimeInterval = 0
    private var spaceObserver: NSObjectProtocol?
    var workspace:LayoutController!
    var hotkeys:HotKeys?
    var smartPanes:SmartPaneController!
    var linkedPanes:LinkedPaneController!
    let shortcuts=ShortcutSettings()
    var switcher:NSPanel?
    private var switcherPreviousApp: NSRunningApplication?
    func applicationDidFinishLaunching(_ notification:Notification) {
        NSApp.setActivationPolicy(.accessory)
        let menu=NSMenu(); let appMenuItem=NSMenuItem(); let appMenu=NSMenu()
        appMenu.addItem(withTitle:"Quit DeskNames",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q")
        appMenuItem.submenu=appMenu;menu.addItem(appMenuItem);NSApp.mainMenu=menu
        item=NSStatusBar.system.statusItem(withLength:NSStatusItem.variableLength)
        item.button?.image=NSImage(systemSymbolName:"rectangle.3.group",accessibilityDescription:"DeskNames")
        item.button?.imagePosition = .imageLeading
        item.button?.target=self;item.button?.action=#selector(showSwitcher)
        overlay=OverlayController(store)
        workspace=LayoutController(store:store)
        smartPanes=SmartPaneController(workspace:workspace)
        smartPanes.start()
        linkedPanes = LinkedPaneController(workspace: workspace)
        workspace.showSwitcher = { [weak self] in self?.showSwitcher() }
        workspace.onSwitch = { [weak self] in self?.switcher?.orderOut(nil) }
        hotkeys=HotKeys { [weak self] id in MainActor.assumeIsolated {self?.shortcut(id)} }
        shortcuts.onChange = { [weak self] enabled,bindings in
            guard let self else{return ""}
            let result=self.hotkeys?.apply(enabled:enabled,bindings:bindings) ?? ""
            self.shortcuts.unavailable=self.hotkeys?.unavailable ?? []
            return result
        }
        shortcuts.apply()
        store.onChange = { [weak self] in self?.updateStatus() }
        updateStatus()
        timer=Timer(timeInterval:0.2,repeats:true) { [weak self] _ in DispatchQueue.main.async {guard let self else { return };let now=ProcessInfo.processInfo.systemUptime;if self.store.missionControl || now-self.lastDesktopRefresh>=1 {self.store.refresh();self.lastDesktopRefresh=now};self.overlay.tick();self.workspace.tick();self.smartPanes.tick();self.linkedPanes.tick()} }
        timer?.tolerance=0.04
        RunLoop.main.add(timer!,forMode:.common)
        spaceObserver=NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.activeSpaceDidChangeNotification,object:nil,queue:.main) { [weak self] _ in
            MainActor.assumeIsolated { self?.store.refresh();self?.workspace.tick() }
        }
    }
    func shortcut(_ id:UInt32) {
        shortcuts.lastAction=ShortcutAction.all.first(where:{$0.id==id})?.name ?? "Unknown action"
        if !workspace.busy {workspace.message=""}
        if let action=WindowAction.allCases.first(where:{$0.id==id}) { workspace.performWindowAction(action,focused:true);return }
        if PaneShortcut.all.contains(where: { $0.id == id }) { workspace.performPaneShortcut(id); return }
        if id==100 {showSwitcher();return}
        store.refresh()
        if id<100 {
            guard let d=store.desktops.first(where:{$0.number==Int(id)}) else {workspace.message="Desktop \(id) does not exist. Create it in Mission Control first.";return}
            workspace.switchTo(d)
        }
        else if let d=workspace.native.activeDesktop(reader:store.reader) { workspace.targetDesktop=d.id; if id==101 {workspace.save(d)};if id==102 {workspace.selectedLayoutID="";workspace.restore()} }
    }
    @objc func showSwitcher() {
        if switcher?.isVisible==true {closeSwitcher();return}
        store.refresh()
        let desktop = workspace.native.activeDesktop(reader: store.reader)
        switcherPreviousApp = NSWorkspace.shared.frontmostApplication
        window?.orderOut(nil)
        let panel=NSPanel(contentRect:NSRect(x:0,y:0,width:560,height:620),styleMask:[.titled,.fullSizeContentView],backing:.buffered,defer:false)
        panel.title="DeskNames control panel";panel.titleVisibility = .hidden;panel.titlebarAppearsTransparent=true;panel.level = .floating;panel.isReleasedWhenClosed=false;panel.hidesOnDeactivate=true;panel.appearance=NSAppearance(named:.darkAqua)
        panel.contentView=NSHostingView(rootView:SwitcherView(store:store,workspace:workspace,preferences:workspace.panes,models:workspace.monitorPresets,desktop:desktop,
            choose:{ [weak self] d in self?.workspace.switchTo(d) },
            close:{ [weak self] in self?.closeSwitcher() },
            openSettings:{ [weak self] in self?.showWindow() }))
        if let screen = NSScreen.screens.first(where: { screenUUID($0) == desktop?.display }) {
            let area = screen.visibleFrame
            panel.setFrameOrigin(CGPoint(x: area.midX-panel.frame.width/2, y: area.midY-panel.frame.height/2))
        } else { panel.center() }
        switcher=panel;NSApp.activate(ignoringOtherApps:true);panel.makeKeyAndOrderFront(nil)
    }
    private func closeSwitcher() {
        switcher?.orderOut(nil)
        if let previous = switcherPreviousApp, previous.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previous.activate(options: [])
        }
        switcherPreviousApp = nil
    }
    func updateStatus() { item?.button?.title="  "+store.desktops.filter(\.isCurrent).map{store.name($0)}.joined(separator:" · ") }
    private func showWindow() {
        switcher?.orderOut(nil)
        switcherPreviousApp = nil
        if window == nil {
            window=NSWindow(contentRect:NSRect(x:0,y:0,width:1020,height:820),styleMask:[.titled,.closable,.miniaturizable,.resizable,.fullSizeContentView],backing:.buffered,defer:false)
            window.contentMinSize=NSSize(width:640,height:520)
            window.title="DeskNames";window.titleVisibility = .hidden;window.titlebarAppearsTransparent=true;window.isReleasedWhenClosed=false
            window.appearance=NSAppearance(named:.darkAqua)
            window.contentView=NSHostingView(rootView:MainView(store:store,workspace:workspace,shortcuts:shortcuts))
            window.center()
            window.isRestorable = false
        }
        NSApp.activate(ignoringOtherApps:true)
        window.makeKeyAndOrderFront(nil)
    }
    func applicationWillTerminate(_ notification:Notification) { smartPanes?.stop();linkedPanes?.stop();timer?.invalidate();if let spaceObserver {NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver)} }
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows flag:Bool)->Bool {
        if switcher?.isVisible != true { showSwitcher() }
        return false
    }
}

try MainActor.assumeIsolated {
if CommandLine.arguments.contains("--self-test") {
    try runWorkspaceTests()
    runDesktopNavigationTests()
    try runScreenLayoutTests()
    runWindowRoutingTests()
    runShortcutTests()
    runGeometryTests()
    runPaneTests()
    runWindowActionTests()
    try runPaneInteractionTests()
    runMovementTests()
    let testDomain="local.desknames.test.\(UUID().uuidString)"
    let d=UserDefaults(suiteName:testDomain)!
    defer {d.removePersistentDomain(forName:testDomain)}
    let s=Store(defaults:d)
    let a=Desktop(id:"stable-id",spaceID:1,display:"test",position:0,number:1,isCurrent:true,isFullScreen:false)
    s.update(a,name:"Research",color:2)
    let moved=Desktop(id:"stable-id",spaceID:99,display:"test2",position:3,number:4,isCurrent:false,isFullScreen:false)
    let restored=Store(defaults:d)
    precondition(restored.name(moved)=="Research" && restored.style(moved).color==2)
    restored.update(moved,name:"   "); precondition(restored.name(moved)=="Desktop 4")
    restored.update(moved,name:String(repeating:"x",count:80),color:999)
    precondition(restored.style(moved).name.count==40 && restored.style(moved).color==4)
    print("PASS: persistence, desktop reordering, empty names, length/color bounds; live desktops: \(s.desktops.count)")
} else if CommandLine.arguments.contains("--movement-session-test") {
    NSApplication.shared.setActivationPolicy(.accessory)
    Task { @MainActor in
        do { try await runMovementSessionTests(); exit(0) } catch { print("FAIL: \(error.localizedDescription)"); exit(1) }
    }
    NSApplication.shared.run()
} else if CommandLine.arguments.contains("--pane-interaction-test") {
    NSApplication.shared.setActivationPolicy(.accessory)
    Task { @MainActor in
        do { try await runPaneInteractionSessionTests(); exit(0) } catch { print("FAIL: \(error.localizedDescription)"); exit(1) }
    }
    NSApplication.shared.run()
} else if CommandLine.arguments.contains("--window-refresh-test") {
    NSApplication.shared.setActivationPolicy(.prohibited)
    Task { @MainActor in
        do {try await runWindowRefreshSessionTest();exit(0)} catch {print("FAIL: \(error.localizedDescription)");exit(1)}
    }
    NSApplication.shared.run()
} else if CommandLine.arguments.contains("--layout-session-test") {
    NSApplication.shared.setActivationPolicy(.accessory)
    Task { @MainActor in
        do {try await runLayoutSessionTest();exit(0)} catch {print("FAIL: \(error.localizedDescription)");exit(1)}
    }
    NSApplication.shared.run()
} else if CommandLine.arguments.contains("--pane-session-test") {
    let app=NSApplication.shared
    app.setActivationPolicy(.prohibited)
    Task { @MainActor in await runPaneSessionTests(); exit(0) }
    app.run()
} else if let index=CommandLine.arguments.firstIndex(of:"--render-preview"),CommandLine.arguments.count>index+1 {
    let app=NSApplication.shared
    app.setActivationPolicy(.prohibited)
    let s=Store()
    func previewDimension(_ flag:String,_ fallback:Double)->Double {
        guard let i=CommandLine.arguments.firstIndex(of:flag),CommandLine.arguments.count>i+1,
              let value=Double(CommandLine.arguments[i+1]),value.isFinite,value>0,value<=5000 else{return fallback}
        return value
    }
    let host=NSHostingView(rootView:MainView(store:s,workspace:LayoutController(store:s),page:CommandLine.arguments.contains("--panes") ? 4 : CommandLine.arguments.contains("--layouts") ? 1:0)); host.frame=NSRect(x:0,y:0,width:previewDimension("--preview-width",1020),height:previewDimension("--preview-height",820))
    let window=NSWindow(contentRect:host.frame,styleMask:.borderless,backing:.buffered,defer:false)
    window.appearance=NSAppearance(named:.darkAqua);window.contentView=host
    host.layoutSubtreeIfNeeded()
    if let rep=host.bitmapImageRepForCachingDisplay(in:host.bounds) {
        host.cacheDisplay(in:host.bounds,to:rep)
        try rep.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:CommandLine.arguments[index+1]))
    }
} else {
    let app=NSApplication.shared
    let delegate=AppDelegate();app.delegate=delegate
    app.run()
}

}
