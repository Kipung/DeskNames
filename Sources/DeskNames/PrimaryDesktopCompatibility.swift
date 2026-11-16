import Foundation

enum PrimaryDesktopCompatibility {
    static func primaryDesktops(in desktops: [Desktop]) -> [Desktop] {
        desktops.filter { !$0.isFullScreen && $0.id == "desknames:primary:\($0.display)" }
    }

    static func usesLegacyAppearance(_ desktop: Desktop, in desktops: [Desktop]) -> Bool {
        let primary = primaryDesktops(in: desktops)
        return primary.count == 1 && primary[0].id == desktop.id
    }

    static func layouts(_ saved: [String: DesktopLayout], desktops: [Desktop]) -> [String: DesktopLayout] {
        let primary = primaryDesktops(in: desktops)
        guard !primary.isEmpty else { return saved }
        var result = saved
        for (key, var layout) in saved {
            for index in layout.windows.indices where layout.windows[index].desktopID == "" {
                let matches = primary.filter { $0.display == layout.windows[index].displayID }
                if matches.count == 1 { layout.windows[index].desktopID = matches[0].id }
            }
            result[key] = layout
        }
        if primary.count == 1, let legacy = saved[""], legacy.id.isEmpty,
           saved[primary[0].id] == nil,
           legacy.windows.filter({ $0.desktopID == nil || $0.desktopID == "" }).allSatisfy({ $0.displayID == primary[0].display }),
           var resolved = result.removeValue(forKey: "") {
            resolved.id = primary[0].id
            result[resolved.id] = resolved
        }
        return result
    }
}
