import AppKit
import SwiftUI

enum SettingsPage: CaseIterable {
    case general, desktops, layouts, panes, routing, shortcuts, labels
    var title: String {
        switch self {
        case .general: "General"
        case .desktops: "Your desktops"
        case .layouts: "Layouts & windows"
        case .panes: "Smart panes"
        case .routing: "Window routing"
        case .shortcuts: "Keyboard shortcuts"
        case .labels: "Label settings"
        }
    }
    var icon: String {
        switch self {
        case .general: "gearshape"
        case .desktops: "rectangle.3.group"
        case .layouts: "square.grid.2x2"
        case .panes: "rectangle.split.2x2"
        case .routing: "arrow.up.forward.app"
        case .shortcuts: "keyboard"
        case .labels: "slider.horizontal.3"
        }
    }
    var headline: String { title }
    var summary: String {
        switch self {
        case .general: "Menu bar, startup and updates."
        case .desktops: "Name and color each desktop."
        case .layouts: "Save each desktop's windows and put them back."
        case .panes: "Pick your panes. Hold Command. Drop into place."
        case .routing: "Send newly opened windows to the desktop you choose."
        case .shortcuts: "Set shortcuts for your everyday actions."
        case .labels: "Fine-tune your Mission Control labels."
        }
    }
}

struct MainView: View {
    @ObservedObject var store:Store
    @ObservedObject var workspace:LayoutController
    @ObservedObject var shortcuts:ShortcutSettings = ShortcutSettings()
    @State var page=SettingsPage.general
    var general: GeneralPreferences? = nil
    var loginItem: LoginItemController? = nil
    var updater: AppUpdater? = nil
    var back: (() -> Void)? = nil
    var close: (() -> Void)? = nil
    var body: some View {
        GeometryReader { geometry in
        let compact = geometry.size.width < 850
        HStack(spacing:0) {
            VStack(alignment:.leading,spacing:0) {
                if let back {
                    Button(action: back) { Label("Back", systemImage: "chevron.left") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                        .accessibilityLabel("Back to control panel").padding(.top, 24).padding(.bottom, 20)
                } else {
                    Text("Settings").font(.headline).padding(.top, 24).padding(.bottom, 20)
                }
                VStack(spacing:7) {
                    ForEach(SettingsPage.allCases, id: \.self) { item in
                        nav(item.title,icon:item.icon,selected:page==item,compact:compact) { page=item }
                    }
                }
                Spacer()
                if !compact { Text("DeskNames").font(.caption).foregroundStyle(.secondary).padding(.vertical, 20) }
            }.padding(.horizontal,compact ? 12 : 24).frame(width:compact ? 72 : 212).background(Color(red:0.065,green:0.085,blue:0.105))
            VStack(alignment:.leading,spacing:20) {
                HStack {
                    VStack(alignment:.leading,spacing:8) {
                        Text(page.headline).font(.system(size:22,weight:.semibold))
                        Text(page.summary).font(.system(size:13)).foregroundStyle(.white.opacity(0.48))
                    }
                    Spacer()
                    if let close {
                        Button(action: close) { Image(systemName: "xmark").padding(6) }
                            .buttonStyle(.plain).accessibilityLabel("Close control panel")
                    }
                }
                switch page {
                case .general:
                    if let general { GeneralSettingsView(preferences: general, loginItem: loginItem, updater: updater) }
                case .desktops: desktopsView
                case .layouts: LayoutView(controller:workspace,store:store)
                case .panes: SmartPanesView(workspace:workspace,store:store,preferences:workspace.panes,models:workspace.monitorPresets)
                case .routing: WindowRoutingView(controller:workspace,store:store,settings:workspace.routing)
                case .shortcuts: ShortcutSettingsView(settings:shortcuts,workspace:workspace)
                case .labels: settingsView
                }
                Spacer(minLength:0)
                HStack(spacing:7) {
                    Image(systemName:"checkmark.circle.fill").foregroundStyle(palette[0])
                    Text("Saved automatically").foregroundStyle(.white.opacity(0.45))
                    Spacer()
                    Text(store.missionControl ? "Mission Control is open" : "Names follow your desktops").foregroundStyle(.white.opacity(0.3))
                }.font(.system(size:11))
            }.padding(24)
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
