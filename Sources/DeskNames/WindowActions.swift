import AppKit
import SwiftUI
import Carbon

enum WindowAction: Int, CaseIterable, Identifiable {
    case left, right, top, bottom, topLeft, topRight, bottomLeft, bottomRight
    case leftThird, middleThird, rightThird, maximize, center, restore, smaller, larger, nextDisplay, previousDisplay
    case column1, column2, column3, column4
    var id: UInt32 { UInt32(200 + rawValue) }
    var name: String { ["Left half","Right half","Top half","Bottom half","Top left quarter","Top right quarter","Bottom left quarter","Bottom right quarter","Left third","Middle third","Right third","Maximize window","Center window","Restore previous size","Make smaller","Make larger","Next display","Previous display","Column 1 of 4","Column 2 of 4","Column 3 of 4","Column 4 of 4"][rawValue] }
    var suggestion: ShortcutBinding {
        let keys: [UInt32] = [123,124,126,125,32,34,38,40,18,19,20,36,8,51,27,24,124,123,18,19,20,21]
        var mods = UInt32(controlKey | optionKey)
        if (8...10).contains(rawValue) { mods |= UInt32(shiftKey) }
        if rawValue >= 16 { mods |= UInt32(cmdKey) }
        if rawValue >= 18 { mods |= UInt32(shiftKey) }
        return ShortcutBinding(key: keys[rawValue], modifiers: mods)
    }
    var partition: (preset: PanePreset, index: Int)? {
        switch self {
        case .left, .right: return (.halves, rawValue)
        case .top, .bottom: return (.rows, rawValue-2)
        case .topLeft, .topRight, .bottomLeft, .bottomRight: return (.quarters, rawValue-4)
        case .leftThird, .middleThird, .rightThird: return (.thirds, rawValue-8)
        case .column1, .column2, .column3, .column4: return (.fourColumns, rawValue-18)
        default: return nil
        }
    }
    func frame(in area: CGRect, current: CGRect, configuration: PaneConfiguration? = nil, pixelScale: CGFloat = 1) -> CGRect? {
        if let partition {
            let config = configuration?.preset == partition.preset ? configuration! : PaneConfiguration(preset: partition.preset, gap: configuration?.gap ?? 0)
            let cells = PaneGeometry(area: area, configuration: config, pixelScale: pixelScale).cells
            return cells.indices.contains(partition.index) ? cells[partition.index] : nil
        }
        switch self {
        case .maximize: return area
        case .center:
            let w = min(area.width, max(1/pixelScale, current.width))
            return CGRect(x: ((area.midX - w/2)*pixelScale).rounded()/pixelScale, y: area.minY, width: w, height: area.height)
        case .smaller, .larger:
            let scale: CGFloat = self == .smaller ? 0.9 : 1.1
            let w = min(area.width, max(1/pixelScale, current.width*scale))
            let h = min(area.height, max(1/pixelScale, current.height*scale))
            let x = current.midX-w/2, y = current.midY-h/2
            return CGRect(x: min(max(x, area.minX), area.maxX-w), y: min(max(y, area.minY), area.maxY-h), width: w, height: h)
        default: return nil
        }
    }
    static func movedFrame(_ current: CGRect, from source: CGRect, to destination: CGRect) -> CGRect {
        let w=min(current.width,destination.width).rounded(.down),h=min(current.height,destination.height).rounded(.down)
        let cx=destination.minX+(current.midX-source.minX)/source.width*destination.width
        let cy=destination.minY+(current.midY-source.minY)/source.height*destination.height
        return CGRect(x:min(max((cx-w/2).rounded(),destination.minX),destination.maxX-w),y:min(max((cy-h/2).rounded(),destination.minY),destination.maxY-h),width:w,height:h)
    }
    static func edge(at p: CGPoint, bounds: CGRect) -> WindowAction? {
        guard bounds.contains(p) else { return nil }
        let left=p.x-bounds.minX<=10, right=bounds.maxX-p.x<=10
        let top=p.y-bounds.minY<=32, bottom=bounds.maxY-p.y<=32
        if left && top { return .topLeft }; if right && top { return .topRight }
        if left && bottom { return .bottomLeft }; if right && bottom { return .bottomRight }
        if left { return .left }; if right { return .right }
        if p.y-bounds.minY<=10 { return .maximize }
        if bounds.maxY-p.y<=10 { return .bottom }
        return nil
    }
}

@MainActor final class WindowFrameHistory {
    private struct Entry { let pid: Int32; let bundle: String; let frame: CGRect; let area: CGRect; let display: String }
    private var entries: [UInt32:Entry] = [:]
    private var order: [UInt32] = []
    func remember(_ window: LiveWindow, frame: CGRect, screen: NSScreen) {
        if let old=entries[window.id], old.pid==window.pid && old.bundle==window.bundleID { return }
        order.removeAll { $0==window.id }; order.append(window.id)
        entries[window.id]=Entry(pid:window.pid,bundle:window.bundleID,frame:frame,area:screenArea(screen),display:screenUUID(screen))
        while order.count>128 { entries.removeValue(forKey:order.removeFirst()) }
    }
    func previous(_ window: LiveWindow, screen: NSScreen) -> CGRect? {
        guard let e=entries[window.id], e.pid==window.pid,e.bundle==window.bundleID else { return nil }
        let destination=NSScreen.screens.first(where:{screenUUID($0)==e.display}) ?? screen
        let area=screenArea(destination)
        if e.display==screenUUID(destination), area.contains(e.frame) { return e.frame }
        return SavedRect.normalized(e.frame,in:e.area).fitted(in:area)
    }
    func forget(_ window: LiveWindow) { entries.removeValue(forKey:window.id);order.removeAll{$0==window.id} }
}

extension NativeWindows {
    @MainActor func focusedWindow() -> LiveWindow? {
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == getpid(), let window=NSApp.keyWindow { return localSnapshot(window) }
        let system=AXUIElementCreateSystemWide();AXUIElementSetMessagingTimeout(system,0.2)
        guard let app=axValue(system,kAXFocusedApplicationAttribute),CFGetTypeID(app)==AXUIElementGetTypeID(),
              let value=axValue(app as! AXUIElement,kAXFocusedWindowAttribute),CFGetTypeID(value)==AXUIElementGetTypeID() else { return nil }
        return liveWindow(value as! AXUIElement)
    }
}

extension LayoutController {
    func performWindowAction(_ action: WindowAction, focused: Bool = false) {
        guard !busy || canRetargetPlacement else { message="A window operation is in progress. Try this shortcut again when it finishes.";return }
        let candidate=focused ? native.focusedWindow() : windows.first{$0.id==selectedWindow}
        guard let candidate else { message="Select an ordinary window first.";return }
        run(interruptible: action != .nextDisplay && action != .previousDisplay) {
            let refreshed=await self.native.refreshedForOperation(candidate)
            try Task.checkCancellation()
            guard let window=refreshed,let source=screenFor(window.frame) else { throw WindowIssue("Could not confirm this window's current state. Refresh and try again.") }
            var targetScreen=source
            let target: CGRect
            if action == .restore {
                guard let previous=self.frameHistory.previous(window,screen:source) else { return "No previous size recorded for this window." }
                target=previous
            } else if action == .nextDisplay || action == .previousDisplay {
                let screens=NSScreen.screens.sorted {a,b in a.frame.minX==b.frame.minX ? a.frame.minY>b.frame.minY : a.frame.minX<b.frame.minX}
                guard screens.count>1,let i=screens.firstIndex(where:{screenUUID($0)==screenUUID(source)}) else { return "Connect another display to move this window." }
                targetScreen=screens[(i+(action == .nextDisplay ? 1 : screens.count-1))%screens.count]
                target=WindowAction.movedFrame(window.frame,from:screenArea(source),to:screenArea(targetScreen))
            } else {
                let desktop = self.store.reader.read().first { $0.isCurrent && $0.display == screenUUID(source) && !$0.isFullScreen }
                let configuration = desktop.map { self.paneConfiguration(for: $0.id) } ?? PaneConfiguration()
                guard let rect=action.frame(in:screenArea(source),current:window.frame,configuration:configuration,pixelScale:source.backingScaleFactor) else { return "This action is unavailable." }
                target=rect
            }
            let old=window.frame
            if action != .restore { self.frameHistory.remember(window, frame: old, screen: source) }
            if action == .nextDisplay || action == .previousDisplay {
                let all=self.store.reader.read()
                guard let desktop=all.first(where:{$0.display==screenUUID(targetScreen) && $0.isCurrent && !$0.isFullScreen}) else {
                    throw WindowIssue("The destination display has no available ordinary desktop.")
                }
                try await self.native.transfer(window,to:desktop,reader:self.store.reader,frame:target)
            } else { try await self.native.animateFrames([(window, target)]) }
            guard self.native.verifyFrame(target,window:window) else { return "\(window.appName) constrained its window size or position." }
            if action == .restore { self.frameHistory.forget(window) }
            return "\(action.name): \(window.appName)."
        }
    }
}

struct WindowActionButtons: View {
    @ObservedObject var controller: LayoutController
    var body: some View {
        LazyVGrid(columns:[GridItem(.adaptive(minimum:130))],spacing:8) {
            ForEach(WindowAction.allCases) { action in
                Button(action.name) { controller.performWindowAction(action) }.frame(maxWidth:.infinity)
            }
        }.controlSize(.small).disabled(controller.busy || !controller.trusted || controller.selectedWindow==0)
    }
}
