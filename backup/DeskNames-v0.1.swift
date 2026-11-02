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
    @Published var vertical: Double = 0 { didSet { defaults.set(vertical,forKey:"vertical") } }
    @Published var horizontal: Double = 0 { didSet { defaults.set(horizontal,forKey:"horizontal") } }
    @Published var spacing: Double = 1 { didSet { defaults.set(spacing,forKey:"spacing") } }
    @Published var missionControl = false
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
    func style(_ d:Desktop) -> Appearance { appearance[d.id] ?? Appearance(name:d.isFullScreen ? "Full screen" : "Desktop \(d.number)",color:(d.number-1)%palette.count) }
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
    @State private var settings=false
    var body: some View {
        HStack(spacing:0) {
            VStack(alignment:.leading,spacing:0) {
                HStack(spacing:10) {
                    Image(systemName:"rectangle.3.group.fill").font(.system(size:23)).foregroundStyle(palette[0])
                    Text("DeskNames").font(.system(size:19,weight:.semibold))
                }.padding(.top,34)
                Text("A place for everything.").font(.system(size:12)).foregroundStyle(.white.opacity(0.45)).padding(.top,10)
                VStack(spacing:7) {
                    nav("Your desktops",icon:"rectangle.3.group",selected:!settings) { settings=false }
                    nav("Label settings",icon:"slider.horizontal.3",selected:settings) { settings=true }
                }.padding(.top,38)
                Spacer()
                Circle().fill(palette[0]).frame(width:7,height:7)
                Text("Made for your Mac.").font(.system(size:13,weight:.medium)).padding(.top,12)
                Text("Free. Open source.\nNames stay on this Mac.").font(.system(size:12)).foregroundStyle(.white.opacity(0.43)).lineSpacing(5).padding(.top,8)
                Text("VERSION 0.1 · PREVIEW").font(.system(size:9,weight:.medium,design:.monospaced)).tracking(1.4).foregroundStyle(.white.opacity(0.3)).padding(.top,25).padding(.bottom,30)
            }.padding(.horizontal,24).frame(width:212).background(Color(red:0.065,green:0.085,blue:0.105))
            VStack(alignment:.leading,spacing:20) {
                HStack {
                    VStack(alignment:.leading,spacing:8) {
                        Text(settings ? "Make them yours." : "Give your desktops a name.").font(.system(size:27,weight:.semibold))
                        Text(settings ? "Fine-tune your Mission Control labels." : "Less searching. More room to think.").font(.system(size:13)).foregroundStyle(.white.opacity(0.48))
                    }
                    Spacer()
                    Text("\(store.desktops.count) SPACES").font(.system(size:10,weight:.semibold,design:.monospaced)).tracking(1).foregroundStyle(palette[0]).padding(9).background(palette[0].opacity(0.1),in:Capsule())
                }
                if settings { settingsView } else { desktopsView }
                Spacer(minLength:0)
                HStack(spacing:7) {
                    Image(systemName:"checkmark.circle.fill").foregroundStyle(palette[0])
                    Text("Saved automatically").foregroundStyle(.white.opacity(0.45))
                    Spacer()
                    Text(store.missionControl ? "Mission Control is open" : "Names follow your desktops").foregroundStyle(.white.opacity(0.3))
                }.font(.system(size:11))
            }.padding(30).frame(maxWidth:.infinity,maxHeight:.infinity).background(Color(red:0.09,green:0.11,blue:0.135))
        }.frame(width:860,height:720).preferredColorScheme(.dark)
    }
    func nav(_ title:String,icon:String,selected:Bool,action:@escaping()->Void)->some View {
        Button(action:action) { HStack(spacing:10) { Image(systemName:icon).frame(width:17); Text(title); Spacer() }.font(.system(size:12,weight:.medium)).padding(12).foregroundStyle(selected ? palette[0] : .white.opacity(0.5)).background(selected ? palette[0].opacity(0.1) : .clear,in:RoundedRectangle(cornerRadius:9)) }.buttonStyle(.plain)
    }
    var desktopsView: some View {
        VStack(alignment:.leading,spacing:16) {
            HStack { Text("YOUR DESKTOPS").tracking(1.6); Spacer(); Text("Click a name to edit") }.font(.system(size:10,weight:.medium)).foregroundStyle(.white.opacity(0.4))
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
            Text("Label positions are estimated from your display. If they need adjusting, use these controls, then reopen Mission Control.").font(.system(size:12)).foregroundStyle(.white.opacity(0.55)).fixedSize(horizontal:false,vertical:true)
            HStack { Text("Vertical offset"); Slider(value:$store.vertical,in:-100...100,step:1); Text("\(Int(store.vertical)) pt").monospacedDigit().frame(width:45) }.font(.system(size:12))
            HStack { Text("Label spacing"); Slider(value:$store.spacing,in:0.3...1.5,step:0.01); Text("\(Int(store.spacing*100))%").monospacedDigit().frame(width:45) }.font(.system(size:12))
            HStack { Text("Horizontal offset"); Slider(value:$store.horizontal,in:-600...600,step:1); Text("\(Int(store.horizontal)) pt").monospacedDigit().frame(width:48) }.font(.system(size:12))
            HStack { TextField("Vertical",value:$store.vertical,format:.number).accessibilityLabel("Vertical offset points"); TextField("Spacing",value:$store.spacing,format:.number).accessibilityLabel("Spacing multiplier"); TextField("Horizontal",value:$store.horizontal,format:.number).accessibilityLabel("Horizontal offset points") }.textFieldStyle(.roundedBorder)
            Button("Reset alignment") { store.vertical=0;store.spacing=1;store.horizontal=0 }.buttonStyle(.bordered)
            Divider()
            Text("Early preview · macOS 26\nExpanded desktop strip supported. Full-screen Spaces keep their native labels. Other display layouts may need adjustment.").font(.system(size:12)).foregroundStyle(.white.opacity(0.4)).lineSpacing(5)
            Button("Quit DeskNames") { NSApp.terminate(nil) }.buttonStyle(.bordered)
        }
    }
}

final class LabelPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
final class OverlayController {
    let store:Store
    var panels:[String:LabelPanel]=[:]
    var rendered:[String:String]=[:]
    var expanded:Set<String>=[]
    var wasOpen=false
    init(_ store:Store) { self.store=store }
    static func isMissionControlOpen() -> Bool {
        let windows=CGWindowListCopyWindowInfo(.optionOnScreenOnly,0) as? [[String:Any]] ?? []
        return windows.contains { w in
            let owner=w[kCGWindowOwnerName as String] as? String ?? ""
            let layer=w[kCGWindowLayer as String] as? Int ?? 0
            return (owner=="Dock" && layer==18) || (owner=="WindowManager" && layer==19)
        }
    }
    func tick() {
        let open=Self.isMissionControlOpen()
        if store.missionControl != open { store.missionControl=open }
        if !open || !store.enabled {
            panels.values.forEach{$0.orderOut(nil)}
            if !open { expanded=[] }; wasOpen=open; return
        }
        let mouse=NSEvent.mouseLocation
        for screen in NSScreen.screens {
            let displayID=(screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
            guard let uuid=CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else {continue}
            let key=CFUUIDCreateString(nil,uuid)! as String
            if NSMouseInRect(mouse,screen.frame,false) && mouse.y>screen.frame.maxY-40 { expanded.insert(key) }
            guard expanded.contains(key) else {continue}
            let spaces=store.desktops.filter{ $0.display==key || (NSScreen.screens.count==1 && $0.display=="Main") }
            let n=spaces.count
            guard n>0 else {continue}
            let gap=min(0.94/Double(n),0.12)*screen.frame.width*store.spacing
            let centerY=screen.frame.maxY-screen.frame.height*0.116+5+store.vertical
            for (i,d) in spaces.enumerated() where !d.isFullScreen {
                let style=store.style(d)
                let pill=NamePill(number:d.number,name:store.name(d),color:palette[style.color],current:d.isCurrent)
                let view=NSHostingView(rootView:pill)
                let width=min(max(view.fittingSize.width,120),max(70,gap-12))
                let panel:LabelPanel
                if let existing=panels[d.id] {panel=existing} else {
                    panel=LabelPanel(contentRect:.zero,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
                    panel.isOpaque=false;panel.backgroundColor = .clear;panel.hasShadow=false;panel.ignoresMouseEvents=true
                    panel.level = .screenSaver;panel.hidesOnDeactivate=false
                    panel.collectionBehavior=[.canJoinAllSpaces,.stationary,.fullScreenAuxiliary,.ignoresCycle]
                    panels[d.id]=panel
                }
                let signature="\(store.name(d))|\(style.color)|\(d.isCurrent)"
                if rendered[d.id] != signature { panel.contentView=view; rendered[d.id]=signature }
                panel.setFrame(NSRect(x:screen.frame.midX+store.horizontal+(Double(i)-Double(n-1)/2)*gap-width/2,y:centerY-18,width:width,height:36),display:true)
                panel.orderFrontRegardless()
            }
        }
        let live=Set(store.desktops.filter{!$0.isFullScreen}.map(\.id))
        for key in Array(panels.keys) where !live.contains(key) {panels.removeValue(forKey:key)?.close(); rendered.removeValue(forKey:key)}
        wasOpen=open
    }
}

final class AppDelegate:NSObject,NSApplicationDelegate {
    let store=Store()
    var window:NSWindow!
    var item:NSStatusItem!
    var overlay:OverlayController!
    var timer:Timer?
    func applicationDidFinishLaunching(_ notification:Notification) {
        NSApp.setActivationPolicy(.accessory)
        let menu=NSMenu(); let appMenuItem=NSMenuItem(); let appMenu=NSMenu()
        appMenu.addItem(withTitle:"Quit DeskNames",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q")
        appMenuItem.submenu=appMenu;menu.addItem(appMenuItem);NSApp.mainMenu=menu
        item=NSStatusBar.system.statusItem(withLength:NSStatusItem.variableLength)
        item.button?.image=NSImage(systemSymbolName:"rectangle.3.group",accessibilityDescription:"DeskNames")
        item.button?.imagePosition = .imageLeading
        item.button?.target=self;item.button?.action=#selector(showWindow)
        overlay=OverlayController(store)
        store.onChange = { [weak self] in self?.updateStatus() }
        updateStatus()
        window=NSWindow(contentRect:NSRect(x:0,y:0,width:860,height:720),styleMask:[.titled,.closable,.miniaturizable,.fullSizeContentView],backing:.buffered,defer:false)
        window.title="DeskNames";window.titleVisibility = .hidden;window.titlebarAppearsTransparent=true;window.isReleasedWhenClosed=false
        window.appearance=NSAppearance(named:.darkAqua)
        window.contentView=NSHostingView(rootView:MainView(store:store))
        window.center()
        timer=Timer(timeInterval:0.2,repeats:true) { [weak self] _ in self?.store.refresh();self?.overlay.tick() }
        RunLoop.main.add(timer!,forMode:.common)
        showWindow()
    }
    func updateStatus() { item?.button?.title="  "+store.desktops.filter(\.isCurrent).map{store.name($0)}.joined(separator:" · ") }
    @objc func showWindow() { NSApp.activate(ignoringOtherApps:true);window?.makeKeyAndOrderFront(nil) }
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows flag:Bool)->Bool { showWindow();return true }
}

if CommandLine.arguments.contains("--self-test") {
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
} else if let index=CommandLine.arguments.firstIndex(of:"--render-preview"),CommandLine.arguments.count>index+1 {
    let app=NSApplication.shared
    app.setActivationPolicy(.prohibited)
    let s=Store()
    let host=NSHostingView(rootView:MainView(store:s)); host.frame=NSRect(x:0,y:0,width:860,height:720)
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
