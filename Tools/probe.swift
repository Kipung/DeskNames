import AppKit
import Darwin
let h = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW)!
typealias Conn = @convention(c) () -> Int32
typealias Spaces = @convention(c) (Int32) -> Unmanaged<CFArray>?
let conn = unsafeBitCast(dlsym(h, "CGSMainConnectionID"), to: Conn.self)
let spaces = unsafeBitCast(dlsym(h, "CGSCopyManagedDisplaySpaces"), to: Spaces.self)
print(spaces(conn())!.takeRetainedValue())
for screen in NSScreen.screens { print("SCREEN",screen.frame, screen.deviceDescription) }
let windows=CGWindowListCopyWindowInfo([.optionOnScreenOnly],0) as? [[String:Any]] ?? []
for w in windows where (w[kCGWindowOwnerName as String] as? String)=="Dock" { print("DOCK",w) }
print("POINTER",NSEvent.mouseLocation)
for w in windows where (w[kCGWindowOwnerName as String] as? String)=="DeskNames" { print("DESKNAMES",w) }
