import AppKit

@MainActor func runScreenLayoutTests() throws {
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
    print("PASS: exact/offscreen layout geometry, translated/resized screens, old/new JSON, equivalent monitor replacements, eight identical monitors without collisions, ambiguous/missing models, shared monitor preset persistence")
}

@MainActor func runLayoutSessionTest() async throws {
    let domain="local.desknames.scene.test.\(UUID().uuidString)",defaults=UserDefaults(suiteName:domain)!
    let file=FileManager.default.temporaryDirectory.appendingPathComponent("DeskNames-scene-\(UUID().uuidString).json")
    defer {defaults.removePersistentDomain(forName:domain);try? FileManager.default.removeItem(at:file)}
    var fixture:[NSWindow]=[]
    for i in 0..<3 {
        let window=NSWindow(contentRect:CGRect(x:100+i*160,y:180+i*70,width:480,height:320),styleMask:[.titled,.resizable],backing:.buffered,defer:false)
        window.title="DeskNames layout fixture \(i+1)";window.isReleasedWhenClosed=false
        window.contentMinSize=CGSize(width:100,height:100)
        window.makeKeyAndOrderFront(nil);fixture.append(window)
    }
    defer {fixture.forEach{$0.close()}}
    await NativeWindows.pause(0.2)
    let store=Store(defaults:defaults);store.refresh()
    let native=NativeWindows(trustCheck:{true},includeExternal:false)
    let controller=LayoutController(store:store,file:file,native:native)
    controller.saveAcrossScreens=true;controller.save()
    guard let desktop=controller.selectedDesktop,let capture=controller.layouts[desktop.id] else {throw WindowIssue("Fixture capture failed: "+controller.message)}
    precondition(capture.windows.count==3)
    controller.option(\.launchMissing,false,layoutID:capture.id)
    for window in fixture {window.setFrame(CGRect(x:30,y:60,width:350,height:250),display:true)}
    fixture[0].orderFront(nil)
    let result=try await controller.restoreLayout(desktop,automatic:false)
    for saved in capture.windows {
        guard let live=native.windows().first(where:{$0.id==saved.windowID}) else {throw WindowIssue("Fixture window missing")}
        precondition(native.verifyFrame(saved.exactFrame!.cg,window:live),"Native restore must return exact captured frame")
    }
    let live=native.windows()
    let ordered=capture.windows.sorted{($0.stackingIndex ?? 0)<($1.stackingIndex ?? 0)}.compactMap{s in live.first{$0.id==s.windowID}}
    let restoredOrder=await native.restoreOrder(ordered,reader:store.reader)
    precondition(restoredOrder,"Native ordering must match the captured front-to-back IDs")
    print("PASS: three real overlapping fixture windows restore captured bounds and verified front-to-back stacking. "+result)
}
