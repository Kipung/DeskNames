import AppKit
import ApplicationServices
import Darwin

let arguments=Array(CommandLine.arguments.dropFirst())
let move=arguments.contains("--move-obsidian")
let bundles=arguments.filter{!$0.hasPrefix("--")}
let targets=bundles.isEmpty ? ["md.obsidian","com.microsoft.VSCode","com.spotify.client","com.hnc.Discord"] : bundles
print("trusted=\(AXIsProcessTrusted())")
guard AXIsProcessTrusted() else {
    print("REFUSED: Accessibility is unavailable to this probe host. No attributes or frames were changed.")
    exit(2)
}
typealias GetID = @convention(c)(AXUIElement,UnsafeMutablePointer<UInt32>)->Int32
guard let symbol=dlsym(dlopen(nil,RTLD_NOW),"_AXUIElementGetWindow") else {
    print("REFUSED: window identity API unavailable")
    exit(2)
}
let getID=unsafeBitCast(symbol,to:GetID.self)
func value(_ element:AXUIElement,_ attribute:String)->CFTypeRef? {
    var result:CFTypeRef?
    let error=AXUIElementCopyAttributeValue(element,attribute as CFString,&result)
    if error != .success {print("  \(attribute) error=\(error.rawValue)")}
    return result
}
func windowID(_ element:AXUIElement)->UInt32? {
    var id:UInt32=0
    let error=getID(element,&id)
    guard error==0,id>0 else {print("  windowID error=\(error)");return nil}
    return id
}
func frame(_ id:UInt32,_ pid:pid_t)->CGRect? {
    let infos=CGWindowListCopyWindowInfo(.optionIncludingWindow,id) as? [[String:Any]] ?? []
    guard let info=infos.first(where:{($0[kCGWindowNumber as String] as? UInt32)==id && ($0[kCGWindowOwnerPID as String] as? Int32)==pid}),
          info[kCGWindowLayer as String] as? Int == 0,
          let bounds=info[kCGWindowBounds as String] as? [String:Any] else{return nil}
    return CGRect(dictionaryRepresentation:bounds as CFDictionary)
}
func matches(_ actual:CGRect?,_ expected:CGRect)->Bool {
    guard let actual else{return false}
    return abs(actual.minX-expected.minX)<=1 && abs(actual.minY-expected.minY)<=1 && abs(actual.width-expected.width)<=1 && abs(actual.height-expected.height)<=1
}
func write(_ rect:CGRect,to window:AXUIElement)->[Int32] {
    var point=rect.origin,size=rect.size
    let position=AXValueCreate(.cgPoint,&point)!,dimensions=AXValueCreate(.cgSize,&size)!
    var errors:[Int32]=[]
    for (key,v) in [(kAXPositionAttribute,position),(kAXSizeAttribute,dimensions),(kAXPositionAttribute,position)] {
        errors.append(AXUIElementSetAttributeValue(window,key as CFString,v).rawValue)
        Thread.sleep(forTimeInterval:0.15)
    }
    return errors
}
func probeMove(_ window:AXUIElement,id:UInt32,pid:pid_t)->Bool {
    guard value(window,kAXMinimizedAttribute) as? Bool != true,
          value(window,"AXFullScreen") as? Bool != true,
          value(window,kAXSubroleAttribute) as? String == kAXStandardWindowSubrole,
          let original=frame(id,pid),original.width>640,original.height>480 else {
        print("MOVE REFUSED: need a non-minimized standard Obsidian window larger than 640 by 480")
        return false
    }
    let target=CGRect(x:original.minX+8,y:original.minY+8,width:original.width-16,height:original.height-16)
    print("MOVE original=\(original) target=\(target)")
    let errors=write(target,to:window)
    let moved=matches(frame(id,pid),target)
    print("MOVE errors=\(errors) actual=\(String(describing:frame(id,pid))) verified=\(moved)")
    var restored=false
    for _ in 0..<3 {
        let errors=write(original,to:window)
        restored=matches(frame(id,pid),original)
        print("RESTORE errors=\(errors) verified=\(restored)")
        if restored {break}
    }
    return moved && restored
}
var found=false,moved=false,success=true
for app in NSWorkspace.shared.runningApplications where targets.contains(app.bundleIdentifier ?? "") {
    found=true
    let bundle=app.bundleIdentifier!,pid=app.processIdentifier
    print("APP \(bundle) pid=\(pid) active=\(app.isActive)")
    let element=AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(element,0.5)
    for attribute in ["AXEnhancedUserInterface","AXManualAccessibility"] {
        print("  \(attribute)=\(String(describing:value(element,attribute)))")
    }
    var focusedID:UInt32?
    for attribute in [kAXFocusedWindowAttribute,kAXMainWindowAttribute] {
        if let v=value(element,attribute),CFGetTypeID(v)==AXUIElementGetTypeID() {
            let id=windowID(v as! AXUIElement)
            print("  \(attribute) id=\(String(describing:id))")
            if attribute==kAXFocusedWindowAttribute {focusedID=id}
        }
    }
    let windows=value(element,kAXWindowsAttribute) as? [AXUIElement] ?? []
    print("  windows=\(windows.count)")
    for window in windows {
        AXUIElementSetMessagingTimeout(window,0.5)
        var owner:pid_t=0
        guard AXUIElementGetPid(window,&owner) == .success,owner==pid,let id=windowID(window) else{continue}
        print("  WINDOW id=\(id) frame=\(String(describing:frame(id,pid)))")
        for attribute in [kAXRoleAttribute,kAXSubroleAttribute,kAXMinimizedAttribute,"AXFullScreen",kAXModalAttribute] {
            print("    \(attribute)=\(String(describing:value(window,attribute)))")
        }
        for attribute in [kAXPositionAttribute,kAXSizeAttribute] {
            var settable:DarwinBoolean=false
            let error=AXUIElementIsAttributeSettable(window,attribute as CFString,&settable)
            print("    \(attribute) settable=\(settable.boolValue) error=\(error.rawValue)")
        }
        print("    titleEmpty=\((value(window,kAXTitleAttribute) as? String ?? "").isEmpty)")
        if move,bundle=="md.obsidian",id==focusedID,!moved {
            moved=true
            success=probeMove(window,id:id,pid:pid) && success
        }
    }
}
if !found {print("No requested applications are running.")}
if move && !moved {print("MOVE REFUSED: no focused Obsidian window with a verified identity");success=false}
exit(success && found ? 0:1)
