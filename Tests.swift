import AppKit

@MainActor func runWorkspaceTests() throws {
    let areas=[CGRect(x:0,y:25,width:1440,height:875),CGRect(x:-1920,y:-1055,width:1920,height:1055),CGRect(x:0,y:25,width:5120,height:1375)]
    for area in areas {
        for c in 1...4 {for r in 1...4 {
            let frames=LayoutController.grid(area,columns:c,rows:r,gap:12)
            precondition(frames.count==c*r)
            for (i,f) in frames.enumerated() {
                precondition(area.contains(f) && f.width>0 && f.height>0)
                for other in frames.dropFirst(i+1) {precondition(!f.intersects(other))}
            }
        }}
        let original=CGRect(x:area.minX+30,y:area.minY+50,width:area.width*0.4,height:area.height*0.6)
        let roundtrip=SavedRect.normalized(original,in:area).fitted(in:area)
        precondition(abs(roundtrip.minX-original.minX)<0.001 && abs(roundtrip.width-original.width)<0.001)
        let offscreen=SavedRect(CGRect(x:-10,y:10,width:2,height:2)).fitted(in:area)
        precondition(area.contains(offscreen))
    }
    let ax=AXUIElementCreateApplication(getpid())
    func window(_ id:UInt32,_ title:String,_ pid:Int32=17)->LiveWindow {LiveWindow(id:id,target:.accessibility(ax),pid:pid,bundleID:"test.app",appName:"Test",title:title,frame:areas[0],spaceIDs:[1],minimized:false)}
    let saved=SavedWindow(bundleID:"test.app",title:"Notes",ordinal:0,windowID:3,pid:17,displayID:"A",frame:SavedRect(CGRect(x:0,y:0,width:0.5,height:1)))
    precondition(LayoutController.match(saved,in:[window(3,"Renamed"),window(4,"Notes")],used:[])?.id==3)
    precondition(LayoutController.match(saved,in:[window(3,"Other",20),window(4,"Notes",20)],used:[])?.id==4)
    precondition(LayoutController.match(saved,in:[window(5,"A"),window(6,"B")],used:[])==nil)
    precondition(LayoutController.match(saved,in:[window(3,"Notes")],used:[3])==nil)
    // An earlier saved window must not steal a later one's exact or title match.
    let a=SavedWindow(bundleID:"test.app",title:"Doc1",ordinal:0,windowID:90,pid:99,displayID:"A",frame:saved.frame)
    let b=SavedWindow(bundleID:"test.app",title:"Doc2",ordinal:1,windowID:91,pid:99,displayID:"A",frame:saved.frame)
    var m=LayoutController.matchAll([a,b],in:[window(7,"Doc2")])
    precondition(m[0]==nil && m[1]?.id==7)
    m=LayoutController.matchAll([a,b],in:[window(7,"Doc1"),window(91,"Renamed",99)])
    precondition(m[0]?.id==7 && m[1]?.id==91)
    m=LayoutController.matchAll([a,b],in:[window(8,"X")])
    precondition(m[0]==nil && m[1]==nil)
    precondition(LayoutController.matchAll([saved],in:[window(8,"Renamed")])[0]?.id==8)
    // Shared titles cannot identify which saved position belongs to a surviving window.
    var untitledA=a;untitledA.title="Untitled"
    var untitledB=b;untitledB.title="Untitled"
    for order in [[untitledA,untitledB],[untitledB,untitledA]] {
        precondition(LayoutController.matchAll(order,in:[window(7,"Untitled")]).allSatisfy{$0==nil})
        precondition(LayoutController.matchAll(order,in:[window(7,"Untitled"),window(8,"Untitled")]).allSatisfy{$0==nil})
    }
    // Exact identity resolves one of the duplicates, leaving an unambiguous title match.
    for candidates in [[window(7,"Untitled"),window(91,"Untitled",99)],[window(91,"Untitled",99),window(7,"Untitled")]] {
        let matches=LayoutController.matchAll([untitledA,untitledB],in:candidates)
        precondition(matches[0]?.id==7 && matches[1]?.id==91)
    }
    // Equal titles in different apps do not compete with one another.
    var otherApp=untitledB;otherApp.bundleID="other.app"
    let separate=LayoutController.matchAll([untitledA,otherApp],in:[window(7,"Untitled")])
    precondition(separate[0]?.id==7 && separate[1]==nil)
    let temp=FileManager.default.temporaryDirectory.appendingPathComponent("DeskNames-tests-\(UUID().uuidString)")
    defer {try? FileManager.default.removeItem(at:temp)}
    let c=LayoutController(store:Store(),file:temp.appendingPathComponent("layouts.json"))
    c.layouts["stable-desktop"]=DesktopLayout(id:"stable-desktop",savedAt:Date(),windows:[saved],autoRestore:true,launchMissing:false,gatherWindows:true)
    c.persist()
    let read=LayoutController(store:Store(),file:c.file)
    precondition(read.layouts["stable-desktop"]?.windows.count==1)
    precondition(read.layouts["stable-desktop"]?.autoRestore==true && read.layouts["stable-desktop"]?.launchMissing==false && read.layouts["stable-desktop"]?.gatherWindows==true)
    print("PASS: grid bounds/non-overlap across 48 layouts; display coordinate round-trip; offscreen clamping; stable window matching; ambiguous match rejection; multi-window match ordering; duplicate-title ambiguity and exact-identity resolution; layout JSON and automation option persistence")
}

func runShortcutTests() {
    let domain="local.desknames.shortcuts.test.\(UUID().uuidString)"
    let defaults=UserDefaults(suiteName:domain)!
    defer {defaults.removePersistentDomain(forName:domain)}
    defaults.set(true,forKey:"enabled")
    let settings=ShortcutSettings(defaults:defaults)
    precondition(!settings.enabled,"Existing label preferences must not enable shortcuts")
    precondition(settings.bindings.count==ShortcutAction.all.count)
    var installed:[UInt32:ShortcutBinding]=[:]
    var removals=0
    var manager:HotKeys?=HotKeys(action:{_ in},register:{id,binding in installed[id]=binding;return true},unregister:{installed.removeAll();removals+=1})
    settings.onChange={enabled,bindings in manager!.apply(enabled:enabled,bindings:bindings)}
    settings.apply()
    precondition(installed.isEmpty,"Startup must not register shortcuts")
    settings.setEnabled(true)
    precondition(installed.count==ShortcutAction.all.count && ShortcutSettings(defaults:defaults).enabled)
    let original=settings.bindings[100]!
    settings.set(settings.bindings[1],for:100)
    precondition(settings.bindings[100]==original && !settings.message.isEmpty,"Duplicate must be refused")
    settings.set(ShortcutBinding(key:49,modifiers:0),for:100)
    precondition(settings.bindings[100]==original,"Unmodified key must be refused")
    settings.set(ShortcutBinding(key:999,modifiers:original.modifiers),for:100)
    precondition(settings.bindings[100]==original,"Unsupported key must be refused")
    let changed=ShortcutBinding(key:0,modifiers:original.modifiers)
    let before=removals
    settings.set(changed,for:100)
    precondition(removals>before && installed[100]==changed && !installed.values.contains(original),"Editing must remove the old registration")
    settings.beginRecording(100)
    precondition(installed.isEmpty && settings.enabled && ShortcutSettings(defaults: defaults).enabled,
                 "Recording must pause shortcuts without changing the saved enabled setting")
    settings.record(key: 18, flags: [.control, .option])
    precondition(settings.recordingAction == 100 && settings.bindings[100] == changed && installed.isEmpty,
                 "An existing shortcut must be rejected without running it or replacing the edited shortcut")
    settings.record(key: 0, flags: [.shift])
    precondition(settings.bindings[100] == changed && settings.recordingAction == 100,
                 "Shift-only input must leave the recorder open")
    settings.record(key: 40, flags: [.command, .shift], isRepeat: true)
    precondition(settings.bindings[100] == changed && settings.recordingAction == 100,
                 "Holding a key must not save a repeated key-down")
    settings.record(key: 40, flags: [.command, .shift, .capsLock, .function, .numericPad])
    let recorded = settings.bindings[100]!
    precondition(recorded.key == 40 && recorded.modifiers == 768 && recorded.displayName == "⇧⌘K")
    precondition(settings.recordingAction == nil && installed[100] == recorded &&
                 ShortcutSettings(defaults: defaults).bindings[100] == recorded,
                 "A valid recorded shortcut must save, end recording, and replace the active binding")
    settings.beginRecording(100)
    settings.record(key: 53, flags: [])
    precondition(settings.bindings[100] == recorded && installed[100] == recorded && settings.recordingAction == nil,
                 "Escape must retain and reactivate the previous shortcut")
    settings.beginRecording(100)
    precondition(!settings.record(key: 48, flags: [.shift]) && settings.recordingAction == nil && installed[100] == recorded,
                 "Tab must cancel recording and pass through for keyboard navigation")
    settings.beginRecording(100)
    settings.beginRecording(1)
    settings.cancelRecording(100)
    precondition(settings.recordingAction == 1 && installed.isEmpty,
                 "Removing an old recorder must not cancel the newly focused recorder")
    settings.cancelRecording(1)
    precondition(installed[100] == recorded)
    settings.beginRecording(100)
    settings.record(key: 51, flags: [])
    precondition(settings.bindings[100] == nil && installed[100] == nil &&
                 ShortcutSettings(defaults: defaults).bindings[100] == nil && settings.recordingAction == nil,
                 "Delete must clear, persist, and end recording")
    settings.beginRecording(100)
    settings.record(key: 44, flags: [.command, .option])
    precondition(settings.bindings[100]?.displayName == "⌥⌘/", "Punctuation must be recordable")
    settings.beginRecording(100)
    settings.record(key: 111, flags: [.control])
    precondition(settings.bindings[100]?.displayName == "⌃F12", "Function keys must be recordable")
    settings.set(nil,for:100)
    precondition(installed[100]==nil && ShortcutSettings(defaults:defaults).bindings[100]==nil,"Clearing must persist and unregister")
    settings.setEnabled(false)
    precondition(installed.isEmpty && !ShortcutSettings(defaults:defaults).enabled,"Disabling must unregister and persist")
    settings.beginRecording(100)
    settings.record(key: 40, flags: [.command, .shift])
    precondition(!settings.enabled && installed.isEmpty && !ShortcutSettings(defaults: defaults).enabled,
                 "Recording while disabled must keep shortcuts disabled")
    settings.setEnabled(true)
    manager=nil
    precondition(installed.isEmpty,"Releasing the owner must unregister")
    defaults.set(Data("{invalid".utf8),forKey:"keyboardShortcuts.v1")
    let recovered=ShortcutSettings(defaults:defaults)
    precondition(!recovered.enabled && ShortcutSettings.validation(recovered.bindings)==nil,"Invalid stored configuration must recover disabled")
    let failed=HotKeys(action:{_ in},register:{_,_ in false},unregister:{})
    precondition(failed.apply(enabled:true,bindings:[1:original]).contains("Go to desktop 1"))
    precondition(failed.unavailable == [1],"Failed registration must identify the unavailable action")
    _=failed.apply(enabled:false,bindings:[1:original])
    precondition(failed.unavailable.isEmpty,"Disabled shortcuts clear stale conflict status")
    print("PASS: shortcuts default off, upgrade default off, opt-in persistence, duplicate/key validation, edit/clear/disable/deinit unregister, conflict reporting, recorded keys, cancellation, duplicate/repeat rejection, temporary suspension, persistence")
}
