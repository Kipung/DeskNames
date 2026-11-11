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
        // Captures cover visible desktops. The all-windows list also includes
        // inactive/hidden Space lists and can retain their old ordering; use the
        // compositor's on-screen list for the order the user actually sees.
        guard let infos=CGWindowListCopyWindowInfo(.optionOnScreenOnly,kCGNullWindowID) as? [[String:Any]] else {message="macOS could not read the window arrangement; the previous layout was kept.";return}
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
        layout.stackingSource=DesktopLayout.currentStackingSource
        layout.name=store.name(d);layout.autoRestore=old?.autoRestore ?? false;layout.launchMissing=old?.launchMissing ?? true;layout.gatherWindows=old?.gatherWindows ?? false
        layouts[d.id]=layout
        guard persist() else {layouts[d.id]=old;return}
        selectedLayoutID=d.id
        message="Saved \(saved.count) windows, including overlap order, on \(Set(saved.map(\.displayID)).count) screen(s)."
    }
}

/// AX success (or a timeout) can precede the compositor's order update. Require
/// consecutive complete observations, rather than trusting one immediate read.
@MainActor func awaitStableWindowOrder(_ expected: [UInt32], samples: Int = 12,
                                     snapshot: () -> [UInt32]?,
                                     pause: () async -> Void = { await NativeWindows.pause(0.08) }) async -> Bool {
    guard Set(expected).count == expected.count else { return false }
    if expected.isEmpty { return true }
    var matches = 0
    for _ in 0..<samples {
        guard !Task.isCancelled else { return false }
        matches = snapshot() == expected ? matches + 1 : 0
        if matches == 2 { return true }
        await pause()
    }
    return false
}

/// Separate visible desktops have independent stacks. Preserve every window's
/// order within its desktop without requiring an interleaving between screens.
struct DesktopWindowOrder {
    let spaceIDs:[UInt64]
    let groups:[[UInt32]]
    private let ids:Set<UInt32>
    var expected:[UInt32] {groups.flatMap{$0}}
    init?(_ frontToBack:[UInt32],spaceByWindow:[UInt32:UInt64]) {
        let unique=Set(frontToBack)
        guard unique.count==frontToBack.count,frontToBack.allSatisfy({spaceByWindow[$0] != nil}) else{return nil}
        var seen=Set<UInt64>()
        let desktops=frontToBack.compactMap{spaceByWindow[$0]}.filter{seen.insert($0).inserted}
        spaceIDs=desktops
        groups=desktops.map{space in frontToBack.filter{spaceByWindow[$0]==space}}
        ids=unique
    }
    func normalized(_ observed:[UInt32]?) -> [UInt32]? {
        guard let observed,observed.count==ids.count,Set(observed)==ids else{return nil}
        return groups.flatMap{group in let members=Set(group);return observed.filter{members.contains($0)}}
    }
    func raisePrefixes(_ observed:[UInt32]?) -> [[UInt32]] {
        guard let observed else{return groups}
        return groups.compactMap{group in
            let members=Set(group),actual=observed.filter{members.contains($0)}
            guard actual.count==group.count,Set(actual)==members else{return group}
            // Leave the longest already-correct suffix untouched. Raising the
            // remaining prefix back-to-front is sufficient, even when its lower
            // windows are interleaved with that suffix in the current list.
            var cursor=actual.endIndex,start=group.endIndex
            for id in group.reversed() {
                guard let index=actual[..<cursor].lastIndex(of:id) else{break}
                start-=1;cursor=index
            }
            return start==0 ? nil:Array(group[..<start])
        }
    }
}

extension NativeWindows {
    @MainActor func restoreOrder(_ frontToBack:[LiveWindow],reader:SpaceReader) async -> Bool {
        guard !frontToBack.isEmpty else{return true}
        let topology=reader.read(),active=Set(topology.filter(\.isCurrent).map(\.id))
        let activeSpaces=Set(topology.filter(\.isCurrent).map(\.spaceID))
        let expected=frontToBack.map(\.id),ids=Set(expected)
        var spaceByWindow:[UInt32:UInt64]=[:]
        for window in frontToBack {
            let membership=spaces(for:window.id)
            guard membership.count==1,activeSpaces.contains(membership[0]) else{return false}
            spaceByWindow[window.id]=membership[0]
        }
        guard let plan=DesktopWindowOrder(expected,spaceByWindow:spaceByWindow) else{return false}
        let windowsByID=Dictionary(uniqueKeysWithValues:frontToBack.map{($0.id,$0)})
        var replies:[[String:Any]]=[]
        func snapshot() -> [UInt32]? {
            guard Set(reader.read().filter(\.isCurrent).map(\.id))==active,
                  frontToBack.allSatisfy({identityExists($0) && spaces(for:$0.id)==[spaceByWindow[$0.id]!]}),
                  let infos=CGWindowListCopyWindowInfo(.optionOnScreenOnly,kCGNullWindowID) as? [[String:Any]] else{return nil}
            return infos.compactMap{$0[kCGWindowNumber as String] as? UInt32}.filter{ids.contains($0)}
        }
        func finish(_ success:Bool,_ attempts:Int) -> Bool {
            let observed=snapshot()
            let verified=success && plan.normalized(observed)==plan.expected
            recordWindowDiagnostic("layout-order-result.json",["success":verified,"attempts":attempts,
                "verification":"per-visible-desktop-v1","expected":plan.expected,"actual":plan.normalized(observed) ?? [],
                "capturedGlobalOrder":expected,"observedGlobalOrder":observed ?? [],
                "desktops":zip(plan.spaceIDs,plan.groups).map{space,group in ["spaceID":space,"expected":group,"actual":(observed ?? []).filter{group.contains($0)}] as [String:Any]},
                "activeDesktopsPreserved":Set(reader.read().filter(\.isCurrent).map(\.id))==active,"replies":replies])
            return verified
        }
        // AXRaise on one display can also raise that app's key window on another.
        // Repair only the necessary front prefixes. Re-raising an already-correct
        // lower app window can undo an inversion repair. Every window still counts.
        for attempt in 1...3 {
            for prefix in plan.raisePrefixes(snapshot()) {
                for id in prefix.reversed() {
                    guard let window=windowsByID[id],!Task.isCancelled,identityExists(window),
                          spaces(for:id)==[spaceByWindow[id]!],Set(reader.read().filter(\.isCurrent).map(\.id))==active else{return finish(false,attempt)}
                    let result:AXError
                    switch window.target {
                    case .local(let local):local.orderFrontRegardless();result = .success
                    case .accessibility:result=await accessibilityWrite(window,.raise)
                    }
                    let group=plan.groups.first{$0.contains(id)}!
                    let lower=Set(group.drop(while:{$0 != id}))
                    // AX replies can precede the composed result. Serialize the
                    // visible effects before asking another app to raise a window.
                    let observed=await awaitStableWindowOrder([id],samples:8,snapshot:{
                        guard let order=snapshot(),let top=order.first(where:{lower.contains($0)}) else{return nil}
                        return [top]
                    })
                    replies.append(["attempt":attempt,"windowID":window.id,"error":result.rawValue,"orderedAboveLowerWindows":observed])
                }
            }
            // A cannotComplete reply may still have raised the window. Observe
            // the result before deciding whether another bounded pass is needed.
            if await awaitStableWindowOrder(plan.expected,snapshot:{plan.normalized(snapshot())}) {return finish(true,attempt)}
        }
        return finish(false,3)
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
