import AppKit

/// Explicit read-only external integration check. Requires the existing disposable
/// TextEdit fixtures and approval for this app; never moves or creates a document.
@MainActor func runWindowRefreshSessionTest() async throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent("DeskNames-refresh-\(UUID().uuidString)")
    defer {try? FileManager.default.removeItem(at:directory)}
    let native=NativeWindows(diagnosticsDirectory:directory)
    guard native.trusted else {throw WindowIssue("Accessibility is required for the external refresh test.")}
    guard let original=native.windows().first(where:{$0.bundleID=="com.apple.TextEdit" && $0.title.hasPrefix("DeskNames Transfer ")}) else {
        throw WindowIssue("Open a disposable DeskNames Transfer TextEdit fixture before this read-only test.")
    }
    func candidate(id:UInt32?=nil,pid:pid_t?=nil,bundle:String?=nil) -> LiveWindow {
        // The app element deliberately is not an AX window, forcing recovery.
        LiveWindow(id:id ?? original.id,target:.accessibility(AXUIElementCreateApplication(original.pid)),
                   pid:pid ?? original.pid,bundleID:bundle ?? original.bundleID,appName:original.appName,
                   title:original.title,frame:original.frame,spaceIDs:original.spaceIDs,minimized:false)
    }
    guard let refreshed=await native.refreshedForOperation(candidate()) else {throw WindowIssue("Could not reacquire the fixture from a stale AX token.")}
    precondition(refreshed.id==original.id && refreshed.pid==original.pid && refreshed.bundleID==original.bundleID)
    precondition(native.currentFrame(original)==original.frame,"The refresh test must not change geometry")
    let data=try Data(contentsOf:directory.appendingPathComponent("window-refresh-result.json"))
    print(String(decoding:data,as:UTF8.self))
    let missing=await native.refreshedForOperation(candidate(id:UInt32.max))
    let wrongProcess=await native.refreshedForOperation(candidate(pid:getpid()))
    let wrongApp=await native.refreshedForOperation(candidate(bundle:"invalid.test.bundle"))
    precondition(missing==nil,"A missing identity must not select another window")
    precondition(wrongProcess==nil,"A mismatched process must not be accepted")
    precondition(wrongApp==nil,"A mismatched app must not be accepted")
    print("PASS: read-only external stale-token recovery reacquires the exact fixture; missing IDs, wrong processes and wrong apps are refused; geometry unchanged and diagnostics isolated")
}

@MainActor func runScreenLayoutTests() throws {
    let order=DesktopWindowOrder([21,11,22,12],spaceByWindow:[11:1,12:1,21:2,22:2])!
    precondition(order.normalized([11,21,12,22])==order.expected,"Independent screens do not share visible overlap")
    precondition(order.normalized([21,12,22,11]) != order.expected,"An inversion within either desktop must fail")
    precondition(order.raisePrefixes([21,12,22,11])==[[11]],"Repair only the necessary front window on the inverted desktop")
    let interleaved=DesktopWindowOrder([10,20,30,40,50,60],spaceByWindow:[10:1,20:1,30:1,40:1,50:1,60:1])!
    precondition(interleaved.raisePrefixes([10,30,20,40,50,60])==[[10,20]],"Do not re-raise the correctly ordered lower app window during inversion repair")
    precondition(interleaved.raisePrefixes(interleaved.expected).isEmpty,"An already-correct stack needs no raises")
    precondition(order.normalized([21,11,22])==nil && order.normalized([21,11,22,11])==nil,"Missing or duplicate windows cannot pass per-desktop verification")
    precondition(DesktopWindowOrder([11,11],spaceByWindow:[11:1])==nil && DesktopWindowOrder([11],spaceByWindow:[:])==nil)
    let area=CGRect(x:0,y:30,width:1470,height:900)
    let intentional=CGRect(x:-25,y:440,width:1000,height:700)
    var saved=SavedWindow(bundleID:"test",title:"Window",ordinal:0,windowID:1,pid:1,displayID:"one",frame:.normalized(intentional,in:area),desktopID:"space",exactFrame:SavedRect(intentional),savedScreenArea:SavedRect(area),stackingIndex:0,displayProfile:DisplayProfile(model:"model-a",name:"Lab",slot:0,peers:1),desktopPosition:0)
    let exact=saved.restoredFrame(in:area)
    precondition(exact.0==intentional && exact.1,"Intentional offscreen geometry must not be clamped")
    let translated=area.offsetBy(dx:-1920,dy:-1080)
    precondition(saved.restoredFrame(in:translated).0==intentional.offsetBy(dx:-1920,dy:-1080))
    let smaller=CGRect(x:-800,y:0,width:800,height:600)
    precondition(smaller.contains(saved.restoredFrame(in:smaller).0) && !saved.restoredFrame(in:smaller).1)
    saved.savedDisplayBounds=SavedRect(CGRect(x:0,y:0,width:1470,height:956))
    let full=CGRect(x:0,y:0,width:1470,height:956)
    precondition(saved.restoredFrame(in:full,bounds:full).0==intentional,"Dock/menu-bar changes must not rescale an unchanged-resolution screen")
    let copy=try JSONDecoder().decode(SavedWindow.self,from:JSONEncoder().encode(saved))
    precondition(copy.exactFrame==saved.exactFrame && copy.stackingIndex==0 && copy.desktopID=="space")
    let oldLayout=DesktopLayout(id:"legacy",savedAt:Date(),windows:[copy])
    let decodedLayout=try JSONDecoder().decode(DesktopLayout.self,from:JSONEncoder().encode(oldLayout))
    precondition(decodedLayout.stackingSource==nil && decodedLayout.windows.count==1,"Existing captures without ordering-source metadata must remain readable")
    saved.exactFrame=nil;saved.savedScreenArea=nil;saved.displayProfile=nil;saved.desktopID=nil;saved.desktopPosition=nil;saved.stackingIndex=nil;saved.savedDisplayBounds=nil
    let old=try JSONEncoder().encode(saved)
    let legacy=try JSONDecoder().decode(SavedWindow.self,from:old)
    precondition(!legacy.restoredFrame(in:area).1 && area.contains(legacy.restoredFrame(in:area).0))
    let model=DisplayProfile(model:"lab-27",name:"Lab 27",slot:0,peers:1)
    precondition(DisplayMatching.index(id:"old-serial",profile:model,ids:["replacement-serial"],profiles:[model])==0)
    precondition(DisplayMatching.index(id:"original",profile:model,ids:["original","new"],profiles:[model,model])==0)
    let eight=(0..<8).map{DisplayProfile(model:"lab-27",name:"Lab 27",slot:$0,peers:8)}
    for i in 0..<8 {precondition(DisplayMatching.index(id:"old-\(i)",profile:eight[i],ids:(0..<8).map{"new-\($0)"},profiles:eight)==i)}
    precondition(DisplayMatching.index(id:"old",profile:model,ids:(0..<8).map{"new-\($0)"},profiles:eight)==nil,"An ambiguous replacement must not silently choose a monitor")
    precondition(DisplayMatching.index(id:"old",profile:model,ids:["other"],profiles:[DisplayProfile(model:"other-model",name:"Other",slot:0,peers:1)])==nil)
    let collapsed=DisplayMatching.assignment(saved:["old-left":eight[0],"old-right":eight[1]],ids:["new"],profiles:[model])
    precondition(collapsed.isEmpty,"Two saved displays must not collapse onto one replacement")
    let retained=DisplayMatching.assignment(saved:["retained":eight[0],"missing":eight[1]],ids:["retained"],profiles:[model])
    precondition(retained==["retained":"retained"],"A missing display must not steal a retained display")
    if let physical=NSScreen.screens.first {
        let one=ConnectedDisplay(id:"new-a",profile:eight[0],area:area,bounds:area,screen:physical)
        let two=ConnectedDisplay(id:"new-b",profile:eight[1],area:translated,bounds:translated,screen:physical)
        let da=Desktop(id:"new-space-a",spaceID:101,display:one.id,position:0,number:1,isCurrent:true,isFullScreen:false)
        let db=Desktop(id:"new-space-b",spaceID:102,display:two.id,position:0,number:2,isCurrent:true,isFullScreen:false)
        var a=copy;a.displayID="old-a";a.displayProfile=eight[0];a.desktopPosition=0;a.desktopID="old-space-a"
        var b=a;b.displayID="old-b";b.displayProfile=eight[1];b.desktopID="old-space-b"
        let mapping=DisplayMatching.assignment(saved:[a.displayID:a.displayProfile,b.displayID:b.displayProfile],ids:[one.id,two.id],profiles:[one.profile,two.profile])
        precondition(a.destination(layoutDesktop:da,desktops:[da,db],screens:[one,two],displayMap:mapping)?.0.id==da.id)
        precondition(b.destination(layoutDesktop:da,desktops:[da,db],screens:[one,two],displayMap:mapping)?.0.id==db.id,"Each saved window must resolve its own monitor and desktop")
        let rule=WindowRule(bundleID:"test",desktopID:"old-space-a",displayID:"old-a",appName:"Test",displayProfile:eight[0],desktopPosition:0)
        precondition(rule.destination(desktops:[da,db],screens:[one,two])?.id==da.id,"Window rules must follow equivalent monitor models too")
        a.displayID=one.id
        precondition(a.destination(layoutDesktop:da,desktops:[da,db],screens:[one,two])==nil,"A deleted desktop on an original screen must not silently redirect by position")
    }
    let domain="local.desknames.monitors.test.\(UUID().uuidString)",defaults=UserDefaults(suiteName:domain)!
    defer {defaults.removePersistentDomain(forName:domain)}
    let presets=MonitorPresets(defaults:defaults)
    presets.set(model,enabled:true,configuration:PaneConfiguration(preset:.thirds,gap:0))
    precondition(MonitorPresets(defaults:defaults).values[model.model]?.panes.preset == .thirds)
    print("PASS: independent desktop order and selective repair, exact/offscreen layout geometry, translated/resized screens, old/new JSON, equivalent monitor replacements, eight identical monitors without collisions, ambiguous/missing models, shared monitor preset persistence")
}

@MainActor func runLayoutSessionTest() async throws {
    // A delayed AX raise must not be declared failed (or successful on a lone
    // transient sample) before WindowServer's complete order settles.
    var observations: [[UInt32]?] = [[3,2,1], [1,2,3], [3,2,1], [1,2,3], [1,2,3]]
    var reads = 0
    let delayed = await awaitStableWindowOrder([1,2,3], snapshot: {
        reads += 1
        return observations.isEmpty ? nil : observations.removeFirst()
    }, pause: {})
    precondition(delayed && reads == 5, "Order verification must wait through asynchronous and transient results")
    reads = 0
    let incomplete = await awaitStableWindowOrder([1,2,3], samples: 4, snapshot: {
        reads += 1; return [1,2]
    }, pause: {})
    precondition(!incomplete && reads == 4, "Missing windows must fail within a bounded number of observations")
    let reversed = await awaitStableWindowOrder([1,2,3], snapshot: { [2,1,3] }, pause: {})
    let duplicate = await awaitStableWindowOrder([1,1], snapshot: { [1,1] }, pause: {})
    precondition(!reversed, "Reversed overlap order must still fail")
    precondition(!duplicate, "Duplicate identities cannot pass")
    print("PASS: asynchronous stacking settles twice; transient order, missing windows, inversions and duplicate identities cannot produce an early success")
    let domain="local.desknames.scene.test.\(UUID().uuidString)",defaults=UserDefaults(suiteName:domain)!
    let file=FileManager.default.temporaryDirectory.appendingPathComponent("DeskNames-scene-\(UUID().uuidString).json")
    defer {defaults.removePersistentDomain(forName:domain);try? FileManager.default.removeItem(at:file)}
    var fixture:[NSWindow]=[]
    for i in 0..<3 {
        let window=NSWindow(contentRect:CGRect(x:100+i*160,y:180+i*70,width:480,height:320),styleMask:[.titled,.resizable],backing:.buffered,defer:false)
        window.title="DeskNames layout fixture \(i+1)";window.isReleasedWhenClosed=false
        window.contentMinSize=CGSize(width:100,height:100)
        window.makeKeyAndOrderFront(nil);window.orderFrontRegardless();fixture.append(window)
    }
    defer {fixture.forEach{$0.close()}}
    await NativeWindows.pause(0.2)
    let store=Store(defaults:defaults);store.refresh()
    let native=NativeWindows(trustCheck:{true},includeExternal:false)
    let controller=LayoutController(store:store,file:file,native:native)
    controller.saveAcrossScreens=true;controller.save()
    guard let desktop=controller.selectedDesktop,let capture=controller.layouts[desktop.id] else {throw WindowIssue("Fixture capture failed: "+controller.message)}
    precondition(capture.windows.count==3)
    precondition(capture.stackingSource==DesktopLayout.currentStackingSource)
    let decoded=try JSONDecoder().decode([String:DesktopLayout].self,from:Data(contentsOf:file))
    precondition(decoded[capture.id]?.stackingSource==DesktopLayout.currentStackingSource,"Visible-order capture metadata must persist")
    controller.option(\.launchMissing,false,layoutID:capture.id)
    for window in fixture {window.setFrame(CGRect(x:30,y:60,width:350,height:250),display:true)}
    let expectedIDs=capture.windows.sorted{($0.stackingIndex ?? 0)<($1.stackingIndex ?? 0)}.map(\.windowID)
    guard let backmost=expectedIDs.last,let window=fixture.first(where:{$0.windowNumber==Int(backmost)}) else {throw WindowIssue("Fixture order missing")}
    window.orderFrontRegardless()
    await NativeWindows.pause(0.2)
    let before=CGWindowListCopyWindowInfo(.optionOnScreenOnly,kCGNullWindowID) as? [[String:Any]] ?? []
    let fixtureIDs=Set(expectedIDs)
    let disturbed=before.compactMap{$0[kCGWindowNumber as String] as? UInt32}.filter{fixtureIDs.contains($0)}
    precondition(disturbed.count==3 && disturbed != expectedIDs,"The native test must actually disturb visible stacking before restoring")
    let result=try await controller.restoreLayout(desktop,automatic:false)
    for saved in capture.windows {
        guard let live=native.windows().first(where:{$0.id==saved.windowID}) else {throw WindowIssue("Fixture window missing")}
        precondition(native.verifyFrame(saved.exactFrame!.cg,window:live),"Native restore must return exact captured frame")
    }
    func visibleOrder() -> [UInt32] {
        let infos=CGWindowListCopyWindowInfo(.optionOnScreenOnly,kCGNullWindowID) as? [[String:Any]] ?? []
        return infos.compactMap{$0[kCGWindowNumber as String] as? UInt32}.filter{fixtureIDs.contains($0)}
    }
    precondition(result.contains("Overlap order restored.") && visibleOrder()==expectedIDs,"Restore itself must reproduce the captured visible order")
    print("PASS: three real overlapping fixture windows restore captured bounds and verified front-to-back stacking. "+result)
    guard let frontID=expectedIDs.first,let constrainedWindow=fixture.first(where:{$0.windowNumber==Int(frontID)}) else {throw WindowIssue("Front fixture missing")}
    constrainedWindow.contentMinSize=CGSize(width:600,height:400)
    window.orderFrontRegardless()
    await NativeWindows.pause(0.2)
    precondition(visibleOrder() != expectedIDs,"Constrained-window test must disturb stacking too")
    let constrained=try await controller.restoreLayout(desktop,automatic:false)
    precondition(constrained.contains("1 apps constrained their placement.") && constrained.contains("Overlap order restored.") && visibleOrder()==expectedIDs,"App size constraints must not exclude a surviving window from stacking restoration")
    print("PASS: constrained geometry is reported while all three windows still restore visible overlap order. "+constrained)
}
