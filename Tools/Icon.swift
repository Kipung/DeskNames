import AppKit
let out=CommandLine.arguments[1]
let fm=FileManager.default
try fm.createDirectory(atPath:out,withIntermediateDirectories:true)
func color(_ r:CGFloat,_ g:CGFloat,_ b:CGFloat)->NSColor {NSColor(srgbRed:r,green:g,blue:b,alpha:1)}
func drawIcon(_ size:Int)->Data {
 let image=NSImage(size:NSSize(width:size,height:size));image.lockFocus()
 let transform=NSAffineTransform();transform.scale(by:CGFloat(size)/1024);transform.concat()
 let outer=NSBezierPath(roundedRect:NSRect(x:64,y:64,width:896,height:896),xRadius:195,yRadius:195)
 let shadow=NSShadow();shadow.shadowColor=NSColor.black.withAlphaComponent(0.25);shadow.shadowBlurRadius=35;shadow.shadowOffset=NSSize(width:0,height:-12)
 NSGraphicsContext.saveGraphicsState();shadow.set()
 color(0.06,0.12,0.15).setFill();outer.fill();NSGraphicsContext.restoreGraphicsState()
 NSGradient(starting:color(0.13,0.24,0.27),ending:color(0.035,0.075,0.1))!.draw(in:outer,angle:270)
 color(0.32,0.55,0.55).withAlphaComponent(0.35).setStroke();outer.lineWidth=3;outer.stroke()
 func pane(_ r:NSRect,_ top:NSColor,_ bottom:NSColor) {
  let p=NSBezierPath(roundedRect:r,xRadius:40,yRadius:40)
  NSGraphicsContext.saveGraphicsState();let s=NSShadow();s.shadowBlurRadius=20;s.shadowOffset=NSSize(width:0,height:-12);s.shadowColor=NSColor.black.withAlphaComponent(0.22);s.set();bottom.setFill();p.fill();NSGraphicsContext.restoreGraphicsState()
  NSGradient(starting:bottom,ending:top)!.draw(in:p,angle:90)
  NSColor.white.withAlphaComponent(0.3).setStroke();p.lineWidth=2;p.stroke()
  let line=NSBezierPath();line.move(to:NSPoint(x:r.minX+22,y:r.maxY-55));line.line(to:NSPoint(x:r.maxX-22,y:r.maxY-55));color(0.03,0.23,0.2).withAlphaComponent(0.22).setStroke();line.lineWidth=3;line.stroke()
  for i in 0..<3 {color(0.04,0.3,0.25).withAlphaComponent(0.45).setFill();NSBezierPath(ovalIn:NSRect(x:r.minX+24+CGFloat(i)*19,y:r.maxY-34,width:9,height:9)).fill()}
 }
 pane(NSRect(x:190,y:220,width:245,height:584),color(0.64,0.97,0.86),color(0.24,0.71,0.58))
 pane(NSRect(x:475,y:510,width:359,height:294),color(0.49,0.88,0.78),color(0.17,0.58,0.5))
 pane(NSRect(x:475,y:220,width:359,height:250),color(0.31,0.72,0.65),color(0.12,0.43,0.4))
 image.unlockFocus()
 let rep=NSBitmapImageRep(data:image.tiffRepresentation!)!
 return rep.representation(using:.png,properties:[:])!
}
for size in [16,32,128,256,512] {
 try drawIcon(size).write(to:URL(fileURLWithPath:"\(out)/icon_\(size)x\(size).png"))
 try drawIcon(size*2).write(to:URL(fileURLWithPath:"\(out)/icon_\(size)x\(size)@2x.png"))
}
