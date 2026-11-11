import AppKit
import Carbon
import Darwin
let h=dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",RTLD_NOW)!
func sym<T>(_ name:String,_ t:T.Type)->T {unsafeBitCast(dlsym(h,name),to:t)}
let conn=sym("CGSMainConnectionID",(@convention(c)()->Int32).self)()
let owner=sym("CGSGetConnectionIDForPSN",(@convention(c)(Int32,UnsafePointer<ProcessSerialNumber>,UnsafeMutablePointer<Int32>)->Int32).self)
let list=sym("CGSGetWindowList",(@convention(c)(Int32,Int32,Int32,UnsafeMutablePointer<UInt32>,UnsafeMutablePointer<Int32>)->Int32).self)
let bounds=sym("CGSGetWindowBounds",(@convention(c)(Int32,UInt32,UnsafeMutablePointer<CGRect>)->Int32).self)
let level=sym("CGSGetWindowLevel",(@convention(c)(Int32,UInt32,UnsafeMutablePointer<Int32>)->Int32).self)
if let dock=NSRunningApplication.runningApplications(withBundleIdentifier:"com.apple.dock").first {
 var psn=ProcessSerialNumber();var dockConn:Int32=0
 let getPSN=unsafeBitCast(dlsym(dlopen(nil,RTLD_NOW),"GetProcessForPID"),to:(@convention(c)(Int32,UnsafeMutablePointer<ProcessSerialNumber>)->Int32).self)
 _=getPSN(dock.processIdentifier,&psn)
 print("OWNER",owner(conn,&psn,&dockConn),dockConn)
 var ids=[UInt32](repeating:0,count:4096);var count:Int32=0
 print("LIST",list(conn,dockConn,4096,&ids,&count),count)
 for id in ids.prefix(Int(count)) {var r=CGRect.zero;var l:Int32=0; _=bounds(conn,id,&r);_=level(conn,id,&l);print(id,l,r)}
}
