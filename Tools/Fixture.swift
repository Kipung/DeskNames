import AppKit
final class Delegate:NSObject,NSApplicationDelegate {
 var windows:[NSWindow]=[]
 func applicationDidFinishLaunching(_ n:Notification){
  NSApp.setActivationPolicy(.regular)
  let m=NSMenu();let i=NSMenuItem();let sm=NSMenu();sm.addItem(withTitle:"Quit Test Windows",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q");i.submenu=sm;m.addItem(i);NSApp.mainMenu=m
  for i in 0..<2 {
   let w=NSWindow(contentRect:NSRect(x:1700+i*450,y:430+i*100,width:420,height:320),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
   w.title="DeskNames test \(i+1)";w.isReleasedWhenClosed=false
   let label=NSTextField(labelWithString:"Layout test window \(i+1)\n\nThis window has no documents.\nIt is safe to move and resize.")
   label.frame=NSRect(x:25,y:110,width:360,height:130);label.font = .systemFont(ofSize:18);w.contentView?.addSubview(label)
   w.makeKeyAndOrderFront(nil);windows.append(w)
  }
  NSApp.activate(ignoringOtherApps:true)
 }
}
let app=NSApplication.shared;let delegate=Delegate();app.delegate=delegate;app.run()
