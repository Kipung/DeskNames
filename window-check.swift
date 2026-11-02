import AppKit
import Darwin
let h=dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",RTLD_NOW)!
typealias Conn = @convention(c)()->Int32
typealias Spaces = @convention(c)(Int32,Int32,CFArray)->Unmanaged<CFArray>?
let conn=unsafeBitCast(dlsym(h,"CGSMainConnectionID"),to:Conn.self)()
let spaces=unsafeBitCast(dlsym(h,"CGSCopySpacesForWindows"),to:Spaces.self)
let windows=CGWindowListCopyWindowInfo(.optionAll,0) as? [[String:Any]] ?? []
for w in windows where (w[kCGWindowOwnerName as String] as? String)=="DeskNames Test Windows" && (w[kCGWindowLayer as String] as? Int)==0 {
 let id=(w[kCGWindowNumber as String] as? NSNumber) ?? 0
 let membership=spaces(conn,7,[id] as CFArray)?.takeRetainedValue() as? [NSNumber] ?? []
 print(id,w[kCGWindowName as String] ?? "",w[kCGWindowBounds as String] ?? "", "spaces",membership)
}
