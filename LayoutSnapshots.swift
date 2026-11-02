import AppKit
import SwiftUI

extension SavedWindow {
    func restoredFrame(in area:CGRect,bounds:CGRect?=nil) -> (CGRect,Bool) {
        if let exact=exactFrame?.cg,let old=savedDisplayBounds?.cg,let bounds,
           PaneGeometry.valid(exact),PaneGeometry.valid(old),abs(old.width-bounds.width)<1,abs(old.height-bounds.height)<1 {
            return (exact.offsetBy(dx:bounds.minX-old.minX,dy:bounds.minY-old.minY),true)
        }
        if let exact=exactFrame?.cg,let old=savedScreenArea?.cg,
           PaneGeometry.valid(exact),PaneGeometry.valid(old),abs(old.width-area.width)<1,abs(old.height-area.height)<1 {
            return (exact.offsetBy(dx:area.minX-old.minX,dy:area.minY-old.minY),true)
        }
        return (frame.fitted(in:area),false)
    }
    func destination(layoutDesktop:Desktop,desktops:[Desktop],screens:[ConnectedDisplay],displayMap:[String:String]?=nil) -> (Desktop,ConnectedDisplay)? {
        let index:Int?
        if let displayMap {index=displayMap[displayID].flatMap {id in screens.firstIndex(where:{$0.id==id})}}
        else {index=DisplayMatching.index(id:displayID,profile:displayProfile,ids:screens.map(\.id),profiles:screens.map(\.profile))}
        guard let i=index else{return nil}
        let screen=screens[i]
        if let destination=desktops.first(where:{$0.id==(desktopID ?? layoutDesktop.id) && $0.display==screen.id && !$0.isFullScreen}) {return (destination,screen)}
        // A different unit of the same monitor model may own different native Space IDs.
        if screen.id != displayID,let position=desktopPosition,
           let destination=desktops.first(where:{$0.display==screen.id && $0.position==position && !$0.isFullScreen}) {return (destination,screen)}
        return nil
    }
}

extension LayoutController {
    var restoreSelection:DesktopLayout? {layouts[selectedLayoutID.isEmpty ? (selectedDesktop?.id ?? ""):selectedLayoutID]}
    func save(_ desktop:Desktop?=nil) {
        guard !busy else {message="Wait for the window operation to finish before saving.";return}
        store.refresh();refresh()
        guard native.trusted else {message="Enable Accessibility before saving a layout.";return}
        guard let d=desktop ?? selectedDesktop,d.isCurrent else {message="Go to this desktop before saving its arrangement.";return}
        let topology=store.reader.read(),screens=ConnectedDisplay.all()
        let scope=topology.filter{!$0.isFullScreen && (saveAcrossScreens ? $0.isCurrent:$0.id==d.id)}
        let ids=Set(scope.map(\.spaceID))
        guard let infos=CGWindowListCopyWindowInfo(.optionAll,kCGNullWindowID) as? [[String:Any]] else {message="macOS could not read the window arrangement; the previous layout was kept.";return}
        let order=infos.compactMap{$0[kCGWindowNumber as String] as? UInt32}
        let ranks=Dictionary(order.enumerated().map{($0.element,$0.offset)},uniquingKeysWith:min)
        var counts:[String:Int]=[:]
        let saved=windows.compactMap {w->SavedWindow? in
            guard !w.minimized,w.spaceIDs.count==1,ids.contains(w.spaceIDs[0]),let rank=ranks[w.id],
                  let owner=scope.first(where:{$0.spaceID==w.spaceIDs[0]}),let screen=screens.first(where:{$0.id==owner.display}) else{return nil}
            let ordinal=counts[w.bundleID,default:0];counts[w.bundleID]=ordinal+1
            return SavedWindow(bundleID:w.bundleID,title:w.title,ordinal:ordinal,windowID:w.id,pid:w.pid,displayID:screen.id,frame:.normalized(w.frame,in:screen.area),desktopID:owner.id,exactFrame:SavedRect(w.frame),savedScreenArea:SavedRect(screen.area),stackingIndex:rank,displayProfile:screen.profile,desktopPosition:owner.position,savedDisplayBounds:SavedRect(screen.bounds))
        }
        guard !saved.isEmpty else {message="No ordinary visible windows found; the previous layout was kept.";return}
        guard MissionControlSlot.snapshot(topology)==MissionControlSlot.snapshot(store.reader.read()),screens.map(\.id)==ConnectedDisplay.all().map(\.id),screens.map(\.area)==ConnectedDisplay.all().map(\.area) else {message="The screen arrangement changed while saving; the previous layout was kept.";return}
        let old=layouts[d.id]
        var layout=DesktopLayout(id:d.id,savedAt:Date(),windows:saved)
        layout.name=store.name(d);layout.autoRestore=old?.autoRestore ?? false;layout.launchMissing=old?.launchMissing ?? true;layout.gatherWindows=old?.gatherWindows ?? false
        layouts[d.id]=layout
        guard persist() else {layouts[d.id]=old;return}
        selectedLayoutID=d.id
        message="Saved \(saved.count) windows, including overlap order, on \(Set(saved.map(\.displayID)).count) screen(s)."
    }
}

extension NativeWindows {
    @MainActor func restoreOrder(_ frontToBack:[LiveWindow],reader:SpaceReader) async -> Bool {
        guard !frontToBack.isEmpty else{return true}
        let active=Set(reader.read().filter(\.isCurrent).map(\.id))
        for window in frontToBack.reversed() {
            guard identityExists(window) else{return false}
            switch window.target {
            case .local(let local):local.orderFront(nil)
            case .accessibility(let element):
                if AXUIElementPerformAction(element,kAXRaiseAction as CFString) != .success {return false}
            }
            await Self.pause(0.04)
        }
        let ids=Set(frontToBack.map(\.id))
        let infos=CGWindowListCopyWindowInfo(.optionAll,kCGNullWindowID) as? [[String:Any]] ?? []
        let actual=infos.compactMap{$0[kCGWindowNumber as String] as? UInt32}.filter{ids.contains($0)}
        return actual==frontToBack.map(\.id) && Set(reader.read().filter(\.isCurrent).map(\.id))==active
    }
}

struct SavedLayoutPreview:View {
    let layout:DesktopLayout
    var groups:[String] {Array(Set(layout.windows.map(\.displayID))).sorted()}
    var body:some View {
        HStack(spacing:10) {
            ForEach(groups,id:\.self) { display in
                let windows=layout.windows.filter{$0.displayID==display}.sorted{($0.stackingIndex ?? 0)>($1.stackingIndex ?? 0)}
                VStack(alignment:.leading,spacing:5) {
                    Canvas {context,size in
                        for (i,w) in windows.enumerated() {
                            let r=w.frame.cg
                            let rect=CGRect(x:r.minX*size.width,y:r.minY*size.height,width:r.width*size.width,height:r.height*size.height)
                            context.fill(Path(roundedRect:rect,cornerRadius:3),with:.color(palette[i%palette.count].opacity(0.45)))
                            context.stroke(Path(roundedRect:rect,cornerRadius:3),with:.color(.white.opacity(0.6)),lineWidth:1)
                        }
                    }.aspectRatio(1.6,contentMode:.fit).frame(maxHeight:105).background(.black.opacity(0.25)).clipShape(RoundedRectangle(cornerRadius:5))
                    Text(windows.first?.displayProfile?.name ?? "Saved screen").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }.accessibilityLabel("Saved window arrangement on \(groups.count) screens")
    }
}
