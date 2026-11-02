import AppKit

struct DisplayProfile: Codable, Equatable {
    var model: String
    var name: String
    var slot: Int
    var peers: Int
}

struct ConnectedDisplay {
    var id: String
    var profile: DisplayProfile
    var area: CGRect
    var bounds: CGRect
    var screen: NSScreen
    @MainActor static func all() -> [ConnectedDisplay] {
        let screens=NSScreen.screens.sorted { a,b in a.frame.minX == b.frame.minX ? a.frame.maxY > b.frame.maxY : a.frame.minX < b.frame.minX }
        let keys=screens.map { screen -> String in
            let id=(screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
            let vendor=CGDisplayVendorNumber(id),model=CGDisplayModelNumber(id)
            if vendor != 0 && model != 0 { return "\(vendor):\(model):\(CGDisplayIsBuiltin(id))" }
            let size=CGDisplayScreenSize(id)
            return "\(screen.localizedName.lowercased()):\(Int(size.width.rounded()))x\(Int(size.height.rounded())):\(CGDisplayIsBuiltin(id))"
        }
        return screens.enumerated().map { i,screen in
            ConnectedDisplay(id:screenUUID(screen),profile:DisplayProfile(model:keys[i],name:screen.localizedName,slot:keys.prefix(i).filter{$0==keys[i]}.count,peers:keys.filter{$0==keys[i]}.count),area:screenArea(screen),bounds:CGRect(x:screen.frame.minX,y:(NSScreen.screens.first?.frame.maxY ?? 0)-screen.frame.maxY,width:screen.frame.width,height:screen.frame.height),screen:screen)
        }
    }
}

enum DisplayMatching {
    static func assignment(saved:[String:DisplayProfile?],ids:[String],profiles:[DisplayProfile]) -> [String:String] {
        var result:[String:String]=[:]
        for id in saved.keys where ids.contains(id) {result[id]=id}
        let missing=saved.keys.filter{result[$0]==nil}.sorted()
        for id in missing {
            guard let profile=saved[id] ?? nil else{continue}
            let peers=missing.filter{(saved[$0] ?? nil)?.model==profile.model}
            let available=profiles.indices.filter{profiles[$0].model==profile.model && !result.values.contains(ids[$0])}
            if peers.count==1,available.count==1 {result[id]=ids[available[0]];continue}
            if let index=available.first(where:{profiles[$0].slot==profile.slot && profiles[$0].peers==profile.peers}) {result[id]=ids[index]}
        }
        return result
    }
    /// Original unit first, otherwise equivalent model. Simultaneous copies retain their spatial slot.
    static func index(id: String, profile: DisplayProfile?, ids: [String], profiles: [DisplayProfile]) -> Int? {
        if let exact=ids.firstIndex(of:id) { return exact }
        guard let profile else {return nil}
        let matches=profiles.indices.filter{profiles[$0].model==profile.model}
        if matches.count==1 { return matches[0] }
        return matches.first {profiles[$0].slot==profile.slot && profiles[$0].peers==profile.peers}
    }
}

@MainActor final class MonitorPresets: ObservableObject {
    struct Preset: Codable {var enabled:Bool;var panes:PaneConfiguration}
    private let defaults:UserDefaults
    @Published private(set) var values:[String:Preset]
    @Published var generation=0
    init(defaults:UserDefaults) {
        self.defaults=defaults
        values=defaults.data(forKey:"monitorModelPresets.v1").flatMap{try? JSONDecoder().decode([String:Preset].self,from:$0)} ?? [:]
    }
    func set(_ profile:DisplayProfile, enabled:Bool, configuration:PaneConfiguration) {
        values[profile.model]=Preset(enabled:enabled,panes:configuration.sanitized)
        if let data=try? JSONEncoder().encode(values) {defaults.set(data,forKey:"monitorModelPresets.v1")}
        generation+=1
    }
    func configuration(on displayID:String) -> PaneConfiguration? {
        guard let display=ConnectedDisplay.all().first(where:{$0.id==displayID}),let preset=values[display.profile.model],preset.enabled else{return nil}
        return preset.panes.sanitized
    }
}

extension LayoutController {
    func paneConfiguration(for desktopID:String) -> PaneConfiguration {
        if let desktop=store.desktops.first(where:{$0.id==desktopID}),let config=monitorPresets.configuration(on:desktop.display) {return config}
        return panes.configuration(for:desktopID)
    }
}
