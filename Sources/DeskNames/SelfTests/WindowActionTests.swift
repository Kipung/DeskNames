import AppKit

@MainActor func runWindowActionTests() {
    let areas=[CGRect(x:0,y:30,width:1440,height:870),CGRect(x:-1920,y:-1080,width:1920,height:1080),CGRect(x:0,y:0,width:5120,height:1440)]
    for area in areas {
        let current=CGRect(x:area.midX-250,y:area.midY-200,width:500,height:400)
        for action in WindowAction.allCases {
            if let target=action.frame(in:area,current:current) { precondition(area.contains(target) && PaneGeometry.valid(target)) }
        }
        let left=WindowAction.left.frame(in:area,current:current)!,right=WindowAction.right.frame(in:area,current:current)!
        precondition(left.maxX==right.minX && left.union(right)==area)
        precondition(WindowAction.edge(at:CGPoint(x:area.minX+1,y:area.minY+1),bounds:area) == .topLeft)
        precondition(WindowAction.edge(at:CGPoint(x:area.midX,y:area.minY+1),bounds:area) == .maximize)
        precondition(WindowAction.edge(at:CGPoint(x:area.maxX-1,y:area.midY),bounds:area) == .right)
        precondition(WindowAction.edge(at:CGPoint(x:area.midX,y:area.midY),bounds:area) == nil)
        precondition(WindowAction.edge(at:CGPoint(x:area.minX-1,y:area.midY),bounds:area) == nil)
        let bigger=WindowAction.larger.frame(in:area,current:current)!
        let smaller=WindowAction.smaller.frame(in:area,current:current)!
        precondition(bigger.width>current.width && smaller.width<current.width && bigger.midX==current.midX && smaller.midY==current.midY)
        let offCenter=CGRect(x:area.minX+40,y:area.minY+60,width:500,height:400)
        let centered=WindowAction.center.frame(in:area,current:offCenter)!
        precondition(centered.width==500 && centered.midX==area.midX && centered.minY==area.minY && centered.height==area.height,
                     "Center keeps the width, centers horizontally, and fills the usable height")
        let wide=WindowAction.center.frame(in:area,current:CGRect(x:area.minX,y:area.minY,width:area.width+300,height:200))!
        precondition(wide == area, "Center never exceeds the usable area")
    }
    let moved=WindowAction.movedFrame(CGRect(x:500,y:30,width:634,height:1040),from:CGRect(x:0,y:30,width:1920,height:1050),to:CGRect(x:263,y:1112,width:1470,height:924))
    precondition(moved.width==634 && moved.height==924 && CGRect(x:263,y:1112,width:1470,height:924).contains(moved),"Display movement preserves width instead of shrinking below app minimums")
    let domain="local.desknames.actions.test.\(UUID().uuidString)"
    let defaults=UserDefaults(suiteName:domain)!
    defer { defaults.removePersistentDomain(forName:domain) }
    let settings=ShortcutSettings(defaults:defaults)
    precondition(ShortcutSettings.validation(settings.bindings) == nil)
    let old=settings.bindings
    settings.set(nil,for:WindowAction.left.id)
    settings.addWindowSuggestions()
    precondition(settings.bindings==old && !settings.enabled)
    precondition(WindowAction.allCases.allSatisfy { a in ShortcutAction.all.contains{$0.id==a.id} })
    if let screen=NSScreen.screens.first {
        let area=screenArea(screen), ax=AXUIElementCreateApplication(getpid())
        let original=area.insetBy(dx:40,dy:50)
        func window(_ pid:Int32)->LiveWindow { LiveWindow(id:42,target:.accessibility(ax),pid:pid,bundleID:"test.app",appName:"Test",title:"",frame:original,spaceIDs:[],minimized:false) }
        let history=WindowFrameHistory(),w=window(99)
        history.remember(w,frame:original,screen:screen)
        history.remember(w,frame:area,screen:screen)
        precondition(history.previous(w,screen:screen)==original,"Repeated snaps retain the first original frame")
        precondition(history.previous(window(100),screen:screen) == nil,"Reused window IDs cannot restore another process's frame")
        history.forget(w);precondition(history.previous(w,screen:screen) == nil)
    }
    print("PASS: window-action bounds on translated displays, contiguous halves, edge/corner/interior targeting, resize anchoring; shortcut suggestions and IDs; restore retains first frame and rejects reused identities")
}
