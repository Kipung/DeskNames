import SwiftUI
import AppKit

struct WindowRoutingView:View {
    @ObservedObject var controller:LayoutController
    @ObservedObject var store:Store
    @ObservedObject var settings:RoutingSettings
    @State private var selectedApp=""
    @State private var apps:[String:String]=[:]
    private func desktopLabel(_ desktop:Desktop) -> String {
        let displays=ConnectedDisplay.all()
        let screen=displays.first(where:{$0.id==desktop.display})?.profile.name ?? "Disconnected screen"
        return store.name(desktop)+" · "+screen
    }
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:18) {
                Toggle("Automatically send new windows",isOn:$settings.enabled)
                Text("Moves matching windows once after they open. Windows already open stay where they are. Moving a window yourself afterward keeps it there.").font(.system(size:12)).foregroundStyle(.secondary)
                if nativeSpaceMoveAvailable() != 1 {Text("Background window sending is unavailable on this macOS version.").font(.caption).foregroundStyle(.orange)}
                if !controller.trusted {Button("Open Accessibility settings") {controller.native.requestPermission()}}
                HStack {
                    Picker("App",selection:$selectedApp) {
                        Text("Choose a running app").tag("")
                        ForEach(apps.keys.sorted(),id:\.self) {key in Text(apps[key] ?? key).tag(key)}
                    }
                    Button("Add rule") {
                        guard !selectedApp.isEmpty,let desktop=controller.selectedDesktop ?? store.desktops.first(where:{$0.isCurrent && !$0.isFullScreen}) else{return}
                        settings.rules.append(WindowRule(bundleID:selectedApp,desktopID:desktop.id,displayID:desktop.display,appName:apps[selectedApp] ?? selectedApp,displayProfile:ConnectedDisplay.all().first(where:{$0.id==desktop.display})?.profile,desktopPosition:desktop.position))
                    }.disabled(selectedApp.isEmpty)
                }.controlSize(.small)
                ForEach($settings.rules) { $rule in
                    VStack(alignment:.leading,spacing:11) {
                        HStack {
                            Toggle(rule.appName,isOn:$rule.enabled).font(.headline)
                            Spacer()
                            Button("Remove") {settings.rules.removeAll{$0.id==rule.id}}.controlSize(.small)
                        }
                        TextField("Title contains (optional)",text:$rule.titleContains).textFieldStyle(.roundedBorder).font(.system(size:12))
                        Picker("Send to desktop",selection:Binding(get:{rule.destination(desktops:store.desktops,screens:ConnectedDisplay.all())?.id ?? rule.desktopID},set:{id in
                            rule.desktopID=id
                            if let desktop=store.desktops.first(where:{$0.id==id}) {rule.displayID=desktop.display;rule.displayProfile=ConnectedDisplay.all().first(where:{$0.id==desktop.display})?.profile;rule.desktopPosition=desktop.position}
                        })) {
                            if !store.desktops.contains(where:{$0.id==rule.desktopID}) {Text("Saved desktop unavailable").tag(rule.desktopID)}
                            ForEach(store.desktops.filter{!$0.isFullScreen}) {desktop in
                                Text(desktopLabel(desktop)).tag(desktop.id)
                            }
                        }.controlSize(.small)
                        if rule.destination(desktops:store.desktops,screens:ConnectedDisplay.all()) == nil {Text("This destination is unavailable. Choose its replacement before opening new windows.").font(.caption).foregroundStyle(.orange)}
                    }.padding(15).background(.white.opacity(0.035),in:RoundedRectangle(cornerRadius:10))
                }
                if settings.rules.isEmpty {Text("Add an app to send its next window to Work, Research, or another desktop.").foregroundStyle(.secondary).font(.system(size:12))}
                Text("First matching rule wins. Full-screen, minimized and all-desktop windows are excluded. Windows opened during another window operation are left alone.").font(.caption).foregroundStyle(.secondary)
                Text(controller.message).font(.system(size:12)).foregroundStyle(palette[0])
            }.padding(.trailing,8)
        }.onAppear {
            apps=Dictionary(NSWorkspace.shared.runningApplications.compactMap {app -> (String,String)? in
                guard app.activationPolicy == .regular,app.processIdentifier != getpid(),let bundle=app.bundleIdentifier else{return nil}
                return (bundle,app.localizedName ?? bundle)
            },uniquingKeysWith:{first,_ in first})
        }
    }
}
