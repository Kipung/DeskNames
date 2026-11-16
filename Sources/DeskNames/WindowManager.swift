import AppKit
import SwiftUI
import Carbon
import Darwin

struct WindowIssue: LocalizedError {
    let message:String
    var errorDescription:String? { message }
    init(_ message:String) {self.message=message}
}
struct SavedRect: Codable, Equatable {
    var x:Double;var y:Double;var width:Double;var height:Double
    init(_ r:CGRect) { x=r.minX;y=r.minY;width=r.width;height=r.height }
    var cg:CGRect {CGRect(x:x,y:y,width:width,height:height)}
    static func normalized(_ rect:CGRect,in area:CGRect)->SavedRect {SavedRect(CGRect(x:(rect.minX-area.minX)/area.width,y:(rect.minY-area.minY)/area.height,width:rect.width/area.width,height:rect.height/area.height))}
    func fitted(in area:CGRect)->CGRect {
        let w=min(area.width,max(160,width*area.width));let h=min(area.height,max(100,height*area.height))
        return CGRect(x:min(max(area.minX+x*area.width,area.minX),area.maxX-w),y:min(max(area.minY+y*area.height,area.minY),area.maxY-h),width:w,height:h)
    }
}
struct SavedWindow:Codable,Identifiable {
    var id:UUID=UUID();var bundleID:String;var title:String;var ordinal:Int;var windowID:UInt32;var pid:Int32
    var displayID:String;var frame:SavedRect
    var desktopID:String?
    var exactFrame:SavedRect?
    var savedScreenArea:SavedRect?
    var stackingIndex:Int?
    var displayProfile:DisplayProfile?
    var desktopPosition:Int?
    var savedDisplayBounds:SavedRect?
}
struct DesktopLayout:Codable,Identifiable {
    var id:String;var savedAt:Date;var windows:[SavedWindow]
    var autoRestore=false;var launchMissing=true;var gatherWindows=false
    var name:String?
    var stackingSource:String?
    static let currentStackingSource="visible-v1"
}
enum WindowTarget {
    case accessibility(AXUIElement)
    case local(NSWindow)
}
struct LiveWindow:Identifiable {
    let id:UInt32;let target:WindowTarget;let pid:Int32;let bundleID:String;let appName:String;let title:String
    let frame:CGRect;let spaceIDs:[UInt64];let minimized:Bool
    var label:String {title.isEmpty ? appName : "\(appName) — \(title)"}
}
func axValue(_ e:AXUIElement,_ name:String)->CFTypeRef? {var v:CFTypeRef?;guard AXUIElementCopyAttributeValue(e,name as CFString,&v) == .success else{return nil};return v}
func axRect(_ e:AXUIElement)->CGRect? {
    guard let p=axValue(e,kAXPositionAttribute),let s=axValue(e,kAXSizeAttribute),CFGetTypeID(p)==AXValueGetTypeID(),CFGetTypeID(s)==AXValueGetTypeID() else{return nil}
    var point=CGPoint.zero;var size=CGSize.zero
    guard AXValueGetValue(p as! AXValue,.cgPoint,&point),AXValueGetValue(s as! AXValue,.cgSize,&size) else{return nil}
    return CGRect(origin:point,size:size)
}
func screenUUID(_ screen:NSScreen)->String {
    let id=(screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    guard let uuid=CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else{return "Main"}
    return CFUUIDCreateString(nil,uuid)! as String
}
func screenArea(_ screen:NSScreen)->CGRect {
    let primaryTop=NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
    let r=screen.visibleFrame
    return CGRect(x:r.minX,y:primaryTop-r.maxY,width:r.width,height:r.height)
}
func screenFor(_ rect:CGRect)->NSScreen? {
    let screens=NSScreen.screens
    if let hit=screens.max(by:{a,b in
        let ar=screenArea(a).intersection(rect),br=screenArea(b).intersection(rect)
        return (ar.isNull ? 0:ar.width*ar.height)<(br.isNull ? 0:br.width*br.height)
    }),screenArea(hit).intersects(rect) {return hit}
    return screens.min {a,b in
        let aa=screenArea(a),bb=screenArea(b)
        return hypot(aa.midX-rect.midX,aa.midY-rect.midY)<hypot(bb.midX-rect.midX,bb.midY-rect.midY)
    }
}

enum AccessibilityWindowWrite: Sendable {
    case position(CGPoint), size(CGSize), frame(CGRect), minimized(Bool), raise
    static func frameSteps(to target: CGRect, from current: CGRect?) -> [Self] {
        guard let current else { return [.position(target.origin), .size(target.size)] }
        let movingSize = CGSize(width: min(current.width, target.width), height: min(current.height, target.height))
        var steps: [Self] = []
        if movingSize != current.size { steps.append(.size(movingSize)) }
        if target.origin != current.origin { steps.append(.position(target.origin)) }
        if target.size != movingSize { steps.append(.size(target.size)) }
        return steps
    }
    func apply(to element: AXUIElement, currentFrame: CGRect? = nil) -> AXError {
        switch self {
        case .position(var point):
            guard let value=AXValueCreate(.cgPoint,&point) else{return .illegalArgument}
            return AXUIElementSetAttributeValue(element,kAXPositionAttribute as CFString,value)
        case .size(var size):
            guard let value=AXValueCreate(.cgSize,&size) else{return .illegalArgument}
            return AXUIElementSetAttributeValue(element,kAXSizeAttribute as CFString,value)
        case .frame(let rect):
            var result = AXError.success
            for step in Self.frameSteps(to: rect, from: currentFrame) {
                let error = step.apply(to: element)
                if result == .success { result = error }
            }
            return result
        case .minimized(let value):return AXUIElementSetAttributeValue(element,kAXMinimizedAttribute as CFString,value ? kCFBooleanTrue:kCFBooleanFalse)
        case .raise:return AXUIElementPerformAction(element,kAXRaiseAction as CFString)
        }
    }
}

// The CF accessibility reference is an immutable identity token. Only the serial
// AX worker writes through it; no AppKit window or mutable NativeWindows state
// crosses queues. Cancellation is the sole mutable field and is lock protected.
private final class AccessibilityWriteRequest: @unchecked Sendable {
    let id:UInt32;let pid:pid_t;let fallback:AXUIElement;let operation:AccessibilityWindowWrite
    private let lock=NSLock()
    private var cancelled=false
    init(id:UInt32,pid:pid_t,fallback:AXUIElement,operation:AccessibilityWindowWrite) {
        self.id=id;self.pid=pid;self.fallback=fallback;self.operation=operation
    }
    func cancel() {lock.lock();cancelled=true;lock.unlock()}
    var isCancelled:Bool {lock.lock();defer{lock.unlock()};return cancelled}
}

private struct AccessibilitySnapshot: @unchecked Sendable {
    let element:AXUIElement
    let id:UInt32;let pid:pid_t;let bundle:String;let appName:String;let frame:CGRect
}
private struct AccessibilityReadRequest: @unchecked Sendable {
    let element:AXUIElement;let id:UInt32;let pid:pid_t;let bundle:String
}
private struct AccessibilityReadResult: Sendable {
    let snapshot:AccessibilitySnapshot?;let cachedFailure:String;let freshFound:Bool
}

struct AccessibilityReadBudget {
    let deadline: TimeInterval
    init(now: TimeInterval, duration: TimeInterval = 1) { deadline = now + duration }
    func permitsRead(now: TimeInterval, cancelled: Bool) -> Bool { !cancelled && now < deadline }
}

enum AccessibilityWorker {
    static func read<Value: Sendable>(on queue: DispatchQueue, _ body: @escaping @Sendable () -> Value) async -> Value {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: body()) }
        }
    }
    static func cancellableRead<Value: Sendable>(on queue: DispatchQueue, cancelledValue: Value,
                                                _ body: @escaping @Sendable (AccessibilityReadCancellation) -> Value) async -> Value {
        let cancellation = AccessibilityReadCancellation()
        return await withTaskCancellationHandler(operation: {
            await read(on: queue) { cancellation.isCancelled ? cancelledValue : body(cancellation) }
        }, onCancel: { cancellation.cancel() })
    }
}

struct FocusedWindowRequest {
    let pid: pid_t
    func accepts(currentPID: pid_t?, trusted: Bool, cancelled: Bool) -> Bool {
        trusted && !cancelled && currentPID == pid
    }
}

struct AccessibilityCensusStatus {
    private(set) var complete = true
    mutating func observe(_ error: AXError) {
        switch error {
        case .success, .noValue, .attributeUnsupported, .notImplemented, .invalidUIElement: break
        default: complete = false
        }
    }
}

struct WindowCensus {
    let windows: [LiveWindow]
    let complete: Bool
    func forLayout() throws -> [LiveWindow] {
        guard complete else { throw WindowIssue("Window discovery was incomplete. Try again when the other apps respond; saved layouts were kept.") }
        return windows
    }
}

enum WindowCapture {
    case local(LiveWindow)
    case external(id: UInt32, pid: pid_t, frame: CGRect)
    var frame: CGRect {
        switch self {
        case .local(let window): return window.frame
        case .external(_, _, let frame): return frame
        }
    }
}

final class AccessibilityReadCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
}

private struct AccessibilityApplication: Sendable {
    let pid: pid_t; let bundle: String; let name: String
}
private struct AccessibilityListedWindow: @unchecked Sendable {
    let element: AXUIElement; let id: UInt32; let app: AccessibilityApplication
    let frame: CGRect; let title: String; let minimized: Bool
}
private struct AccessibilityWindowCensus: Sendable {
    var windows: [AccessibilityListedWindow] = []
    var observed: Set<WindowIdentity> = []
    var complete = true
}

final class NativeWindows {
    private static let configureTimeout: Void = {
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.2)
    }()
    private static let accessibilityWrites = DispatchQueue(label: "local.desknames.accessibility-writes", qos: .userInitiated)
    private static let accessibilityDiscovery = DispatchQueue(label: "local.desknames.accessibility-discovery", qos: .userInitiated)
    @MainActor private static var processQueues: [pid_t: DispatchQueue] = [:]
    @MainActor private static func accessibilityQueue(for pid: pid_t) -> DispatchQueue {
        if let queue = processQueues[pid] { return queue }
        let queue = DispatchQueue(label: "local.desknames.accessibility.\(pid)", qos: .userInteractive)
        processQueues[pid] = queue
        return queue
    }
    private typealias GetWindowID = @convention(c) (AXUIElement, UnsafeMutablePointer<UInt32>) -> Int32
    private static let windowIDFunction: GetWindowID? = {
        guard let symbol = dlsym(dlopen(nil, RTLD_NOW), "_AXUIElementGetWindow") else { return nil }
        return unsafeBitCast(symbol, to: GetWindowID.self)
    }()
    let handle=dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",RTLD_NOW)
    private var knownWindows:[UInt32:LiveWindow]=[:]
    private let trustCheck: () -> Bool
    private let includeExternal:Bool
    private let diagnosticsDirectory:URL?
    init(trustCheck: @escaping () -> Bool = { AXIsProcessTrusted() },includeExternal:Bool=true,diagnosticsDirectory:URL?=nil) {
        _ = Self.configureTimeout
        self.trustCheck=trustCheck;self.includeExternal=includeExternal;self.diagnosticsDirectory=diagnosticsDirectory
    }
    var trusted:Bool {trustCheck()}
    @MainActor func focusedWindowForOperation(onFailure: (String) -> Void = { _ in }) async -> LiveWindow? {
        func refuse(_ reason: String) -> LiveWindow? {
            recordWindowDiagnostic("focused-window-result.json", ["refusal": reason])
            onFailure(reason)
            return nil
        }
        guard trusted else { return refuse("accessibility-off") }
        guard !Task.isCancelled, let frontmost = NSWorkspace.shared.frontmostApplication else { return nil }
        let pid = frontmost.processIdentifier
        let request = FocusedWindowRequest(pid: pid)
        if pid == getpid() { return NSApp.keyWindow.flatMap(localSnapshot) }
        guard includeExternal else { return nil }
        let result: (AccessibilitySnapshot?, String) = await AccessibilityWorker.cancellableRead(
            on: Self.accessibilityQueue(for: pid), cancelledValue: (nil, "cancelled")) { cancellation in
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, 0.2)
            let budget = AccessibilityReadBudget(now: ProcessInfo.processInfo.systemUptime)
            func permitted() -> Bool {
                budget.permitsRead(now: ProcessInfo.processInfo.systemUptime, cancelled: cancellation.isCancelled)
            }
            do {
                let snapshot = try WindowDiscovery.focused(pid: pid, focused: Self.windowAttribute(app, kAXFocusedWindowAttribute),
                    front: { permitted() ? WindowDiscovery.foremost(for: pid, in: Self.onScreenWindows()) : nil },
                    main: {
                        guard permitted(), case .value(let value) = Self.windowAttribute(app, kAXMainWindowAttribute) else { return nil }
                        return value
                    },
                    windows: { permitted() ? axValue(app, kAXWindowsAttribute) as? [AXUIElement] ?? [] : [] },
                    identity: { element in
                        guard permitted() else { return nil }
                        AXUIElementSetMessagingTimeout(element, 0.1)
                        return Self.accessibilityIdentity(element)
                    }, inspect: { element in
                        guard permitted() else { throw WindowDiscoveryFailure("discovery-timeout") }
                        var reason = "focused-window-ineligible"
                        guard let snapshot = Self.inspectAccessibilityWindow(element, messagingTimeout: 0.1, onFailure: { reason = $0 }) else {
                            throw WindowDiscoveryFailure(reason)
                        }
                        return snapshot
                    }, currentPID: { pid })
                return (snapshot, "")
            } catch let failure as WindowDiscoveryFailure { return (nil, failure.reason) }
            catch { return (nil, "window-discovery-failed") }
        }
        guard request.accepts(currentPID: NSWorkspace.shared.frontmostApplication?.processIdentifier, trusted: trusted, cancelled: Task.isCancelled) else {
            return refuse("frontmost-app-changed")
        }
        guard let snapshot = result.0 else { return refuse(result.1) }
        guard snapshot.pid == pid, let frame = Self.windowServerFrame(id: snapshot.id, pid: pid) else { return refuse("front-window-unavailable") }
        return LiveWindow(id: snapshot.id, target: .accessibility(snapshot.element), pid: pid, bundleID: snapshot.bundle,
                          appName: snapshot.appName, title: "", frame: frame, spaceIDs: spaces(for: snapshot.id), minimized: false)
    }
    func requestPermission() {
        // An approval saved for an older signature still shows as on in System Settings,
        // but macOS refuses it and won't prompt again. Clearing only DeskNames' own entry
        // lets the prompt below appear.
        if !trusted, let bundleID = Bundle.main.bundleIdentifier {
            let reset = Process()
            reset.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            reset.arguments = ["reset", "Accessibility", bundleID]
            reset.standardOutput = FileHandle.nullDevice
            reset.standardError = FileHandle.nullDevice
            if (try? reset.run()) != nil { reset.waitUntilExit() }
        }
        _=AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String:true] as CFDictionary)
        NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    func spaces(for id:UInt32)->[UInt64] {
        typealias Conn = @convention(c)()->Int32
        typealias Copy = @convention(c)(Int32,Int32,CFArray)->Unmanaged<CFArray>?
        guard let handle,let c=dlsym(handle,"CGSMainConnectionID"),let f=dlsym(handle,"CGSCopySpacesForWindows") else{return []}
        let a=unsafeBitCast(f,to:Copy.self)(unsafeBitCast(c,to:Conn.self)(),7,[NSNumber(value:id)] as CFArray)?.takeRetainedValue() as? [NSNumber] ?? []
        return a.map(\.uint64Value)
    }
    @MainActor func window(at point: CGPoint, localWindow: NSWindow? = nil, onFailure: (String) -> Void = { _ in }) -> LiveWindow? {
        guard trusted else { onFailure("accessibility-off"); return nil }
        if let localWindow {
            guard Self.isLocalTitlebarPoint(point, in: localWindow) else { onFailure("local-content"); return nil }
            guard let window = localSnapshot(localWindow), window.frame.contains(point) else { onFailure("ineligible-local-window"); return nil }
            return window
        }
        guard includeExternal else { onFailure("external-windows-disabled"); return nil }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.1)
        var hit: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hit)
        var owner: pid_t?
        if result == .success, let hit {
            var pid: pid_t = 0
            if AXUIElementGetPid(hit, &pid) == .success, pid > 0 { owner = pid }
            if axValue(hit, kAXRoleAttribute) as? String == kAXWindowRole { return liveWindow(hit, onFailure: onFailure) }
            if let value = axValue(hit, kAXWindowAttribute), CFGetTypeID(value) == AXUIElementGetTypeID() {
                let element = value as! AXUIElement
                if axValue(element, kAXRoleAttribute) as? String == kAXWindowRole { return liveWindow(element, onFailure: onFailure) }
            }
        }
        guard let front = WindowDiscovery.foremost(at: point, in: Self.onScreenWindows()) else { onFailure("front-window-unavailable"); return nil }
        let app = AXUIElementCreateApplication(front.identity.pid)
        AXUIElementSetMessagingTimeout(app, 0.1)
        do {
            let element = try WindowDiscovery.exactWindow(for: front, owner: owner,
                windows: { axValue(app, kAXWindowsAttribute) as? [AXUIElement] ?? [] }, identity: Self.accessibilityIdentity)
            return liveWindow(element, onFailure: onFailure)
        } catch let failure as WindowDiscoveryFailure { onFailure(failure.reason); return nil }
        catch { onFailure("window-discovery-failed"); return nil }
    }
    private static func accessibilityIdentity(_ element: AXUIElement) -> WindowIdentity? {
        var pid: pid_t = 0
        var id: UInt32 = 0
        guard AXUIElementGetPid(element, &pid) == .success, let getID = windowIDFunction,
              getID(element, &id) == 0, id > 0 else { return nil }
        return WindowIdentity(id: id, pid: pid)
    }
    private static func eligibilityMetadata(_ element: AXUIElement) -> WindowEligibilityMetadata {
        var subroleValue: CFTypeRef?
        let subroleError = AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleValue)
        let subrole = subroleValue as? String
        let subroleFailure = WindowDiscovery.attributeFailure(subroleError, name: kAXSubroleAttribute) ??
            (subroleError == .success && subroleValue != nil && subrole == nil ? "AXSubrole-invalid-type" : nil)
        var settable = DarwinBoolean(false)
        var positionSettable: Bool?
        if subrole == nil || subrole == "" || subrole == "AXUnknown" {
            if AXUIElementIsAttributeSettable(element, kAXPositionAttribute as CFString, &settable) == .success {
                positionSettable = settable.boolValue
            }
        }
        return WindowEligibilityMetadata(role: axValue(element, kAXRoleAttribute) as? String,
            subrole: subrole, subroleReadFailure: subroleFailure,
            modal: axValue(element, kAXModalAttribute) as? Bool ?? false,
            fullScreen: axValue(element, "AXFullScreen") as? Bool ?? false,
            minimized: axValue(element, kAXMinimizedAttribute) as? Bool ?? false,
            positionSettable: positionSettable,
            hasSheets: (axValue(element, kAXChildrenAttribute) as? [AXUIElement] ?? []).contains {
                axValue($0, kAXRoleAttribute) as? String == kAXSheetRole
            })
    }
    private static func onScreenWindows() -> [WindowServerCandidate] {
        let infos = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        return infos.compactMap { info in
            guard let id = info[kCGWindowNumber as String] as? UInt32,
                  let pid = info[kCGWindowOwnerPID as String] as? Int32,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return nil }
            return WindowServerCandidate(identity: WindowIdentity(id: id, pid: pid), layer: layer, bounds: frame,
                onScreen: info[kCGWindowIsOnscreen as String] as? Bool ?? false,
                alpha: info[kCGWindowAlpha as String] as? Double ?? 1)
        }
    }
    private static func windowAttribute(_ app: AXUIElement, _ name: String) -> WindowAttributeRead<AXUIElement> {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(app, name as CFString, &value)
        if error == .noValue || error == .attributeUnsupported { return .absent }
        guard error == .success else { return .failure("\(name)-error \(error.rawValue)") }
        guard let value else { return .absent }
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return .failure("\(name)-invalid-type") }
        return .value(value as! AXUIElement)
    }
    @MainActor func focusedWindow(onFailure: (String) -> Void = { _ in }) -> LiveWindow? {
        func refuse(_ reason: String) -> LiveWindow? {
            recordWindowDiagnostic("focused-window-result.json", ["refusal": reason])
            onFailure(reason)
            return nil
        }
        guard trusted else { return refuse("accessibility-off") }
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return refuse("frontmost-app-unavailable") }
        if pid == getpid() {
            guard let window = NSApp.keyWindow, let snapshot = localSnapshot(window) else { return refuse("ineligible-local-window") }
            return snapshot
        }
        guard includeExternal else { return refuse("external-windows-disabled") }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.2)
        do {
            return try WindowDiscovery.focused(pid: pid, focused: Self.windowAttribute(app, kAXFocusedWindowAttribute),
                front: { WindowDiscovery.foremost(for: pid, in: Self.onScreenWindows()) },
                main: { if case .value(let value) = Self.windowAttribute(app, kAXMainWindowAttribute) { return value }; return nil },
                windows: { axValue(app, kAXWindowsAttribute) as? [AXUIElement] ?? [] }, identity: Self.accessibilityIdentity,
                inspect: { element in
                    var reason = "focused-window-ineligible"
                    guard let window = self.liveWindow(element, onFailure: { reason = $0 }) else { throw WindowDiscoveryFailure(reason) }
                    return window
                }, currentPID: { NSWorkspace.shared.frontmostApplication?.processIdentifier })
        } catch let failure as WindowDiscoveryFailure { return refuse(failure.reason) }
        catch { return refuse("window-discovery-failed") }
    }
    @MainActor func captureWindow(at point: CGPoint, localWindow: NSWindow? = nil) -> WindowCapture? {
        guard trusted else { return nil }
        if let localWindow { return window(at: point, localWindow: localWindow).map(WindowCapture.local) }
        guard includeExternal, let front = WindowDiscovery.foremost(at: point, in: Self.onScreenWindows()),
              front.layer == 0, front.identity.pid != getpid() else { return nil }
        return .external(id: front.identity.id, pid: front.identity.pid, frame: front.bounds)
    }
    @MainActor func windowForOperation(_ capture: WindowCapture) async -> LiveWindow? {
        guard trusted, !Task.isCancelled else { return nil }
        guard case .external(let id, let pid, let originalFrame) = capture else {
            if case .local(let window) = capture, refreshed(window) != nil { return window }
            return nil
        }
        let snapshot: AccessibilitySnapshot? = await AccessibilityWorker.cancellableRead(on: Self.accessibilityQueue(for: pid), cancelledValue: nil) { cancellation in
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, 0.2)
            let budget = AccessibilityReadBudget(now: ProcessInfo.processInfo.systemUptime)
            guard let getID = Self.windowIDFunction, let candidates = axValue(app, kAXWindowsAttribute) as? [AXUIElement] else { return nil }
            for candidate in candidates {
                guard budget.permitsRead(now: ProcessInfo.processInfo.systemUptime, cancelled: cancellation.isCancelled) else { break }
                AXUIElementSetMessagingTimeout(candidate, 0.1)
                var candidateID: UInt32 = 0
                if getID(candidate, &candidateID) == 0 && candidateID == id {
                    return Self.inspectAccessibilityWindow(candidate, messagingTimeout: 0.1)
                }
            }
            return nil
        }
        guard trusted, !Task.isCancelled, let snapshot, snapshot.id == id, snapshot.pid == pid,
              Self.windowServerFrame(id: id, pid: pid) != nil else { return nil }
        return LiveWindow(id: id, target: .accessibility(snapshot.element), pid: pid, bundleID: snapshot.bundle,
                          appName: snapshot.appName, title: "", frame: originalFrame, spaceIDs: spaces(for: id), minimized: false)
    }
    func currentFrame(_ capture: WindowCapture) -> CGRect? {
        switch capture {
        case .local(let window): return currentFrame(window)
        case .external(let id, let pid, _): return Self.windowServerFrame(id: id, pid: pid)
        }
    }
    func liveWindow(_ element: AXUIElement, messagingTimeout:Float=0.1, onFailure: (String) -> Void = { _ in }) -> LiveWindow? {
        guard let value=Self.inspectAccessibilityWindow(element,messagingTimeout:messagingTimeout,onFailure:onFailure) else{return nil}
        return LiveWindow(id:value.id,target:.accessibility(value.element),pid:value.pid,bundleID:value.bundle,appName:value.appName,
                          title:"",frame:value.frame,spaceIDs:spaces(for:value.id),minimized:false)
    }
    private static func inspectAccessibilityWindow(_ element:AXUIElement,messagingTimeout:Float,onFailure:(String)->Void={_ in}) -> AccessibilitySnapshot? {
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else { onFailure("window-owner-unavailable"); return nil }
        guard pid != getpid() else { onFailure("desknames-window"); return nil }
        guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated,
              app.activationPolicy == .regular, let bundle = app.bundleIdentifier else { onFailure("ineligible-app pid=\(pid)"); return nil }
        if let refusal = eligibilityMetadata(element).refusal(for: .operation) { onFailure("\(refusal) pid=\(pid) app=\(bundle)"); return nil }
        typealias GetID = @convention(c)(AXUIElement, UnsafeMutablePointer<UInt32>) -> Int32
        guard let fn = dlsym(dlopen(nil, RTLD_NOW), "_AXUIElementGetWindow") else { onFailure("window-identity-api-unavailable"); return nil }
        var id: UInt32 = 0
        guard unsafeBitCast(fn, to: GetID.self)(element, &id) == 0, id > 0 else { onFailure("window-identity-unavailable app=\(bundle)"); return nil }
        guard let frame = Self.windowServerFrame(id: id, pid: pid), frame.width > 80, frame.height > 50 else { onFailure("window-bounds-unavailable app=\(bundle) id=\(id)"); return nil }
        return AccessibilitySnapshot(element:element,id:id,pid:pid,bundle:bundle,appName:app.localizedName ?? bundle,frame:frame)
    }
    @MainActor static func isLocalTitlebarPoint(_ point: CGPoint, in window: NSWindow) -> Bool {
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        let local = window.convertPoint(fromScreen: CGPoint(x: point.x, y: primaryTop - point.y))
        return CGRect(origin: .zero, size: window.frame.size).contains(local) && !window.contentLayoutRect.contains(local)
    }
    @MainActor func localSnapshot(_ window: NSWindow) -> LiveWindow? {
        guard !(window is NSPanel), window.styleMask.contains([.titled, .resizable]),
              window.isVisible, !window.isMiniaturized, !window.styleMask.contains(.fullScreen),
              window.windowNumber > 0, let bundle = Bundle.main.bundleIdentifier else { return nil }
        let id = UInt32(window.windowNumber)
        guard let frame = Self.windowServerFrame(id: id, pid: getpid()) else { return nil }
        return LiveWindow(id: id, target: .local(window), pid: getpid(), bundleID: bundle, appName: "DeskNames",
                          title: window.title, frame: frame, spaceIDs: spaces(for: id), minimized: false)
    }
    @MainActor func refreshed(_ window: LiveWindow) -> LiveWindow? {
        func verified(_ value:LiveWindow?) -> LiveWindow? {
            guard let current=value,current.id==window.id,current.pid==window.pid,current.bundleID==window.bundleID else{return nil}
            return current
        }
        switch window.target {
        case .local(let local):return verified(localSnapshot(local))
        case .accessibility(let element):
            var failure=""
            if let current=verified(liveWindow(element,onFailure:{failure=$0})) {return current}
            if failure.isEmpty {failure="window-identity-changed"}
            // A cached AX token can stop answering after a sequence of raises or
            // display moves. WindowServer existence alone does not establish AX
            // eligibility: reacquire by exact identity and repeat every check.
            guard Self.windowServerFrame(id:window.id,pid:window.pid) != nil,
                  NSRunningApplication(processIdentifier:window.pid)?.bundleIdentifier==window.bundleID else{return nil}
            let app=AXUIElementCreateApplication(window.pid);AXUIElementSetMessagingTimeout(app,0.3)
            typealias GetID = @convention(c)(AXUIElement,UnsafeMutablePointer<UInt32>) -> Int32
            guard let symbol=dlsym(dlopen(nil,RTLD_NOW),"_AXUIElementGetWindow") else{return nil}
            let getID=unsafeBitCast(symbol,to:GetID.self)
            let fresh=(axValue(app,kAXWindowsAttribute) as? [AXUIElement])?.first {candidate in
                AXUIElementSetMessagingTimeout(candidate,0.1)
                var id:UInt32=0;var pid:pid_t=0
                return AXUIElementGetPid(candidate,&pid) == .success && pid==window.pid && getID(candidate,&id)==0 && id==window.id
            }
            let current=fresh.flatMap{verified(liveWindow($0,messagingTimeout:0.3))}
            recordWindowDiagnostic("window-refresh-result.json",["windowID":window.id,"pid":window.pid,"bundle":window.bundleID,
                "cachedFailure":failure,"freshIdentityFound":fresh != nil,"eligibilityConfirmed":current != nil])
            return current
        }
    }
    @MainActor func refreshedForOperation(_ window:LiveWindow) async -> LiveWindow? {
        guard trusted else { return nil }
        guard case .accessibility(let element)=window.target else{return refreshed(window)}
        guard !Task.isCancelled else{return nil}
        let request=AccessibilityReadRequest(element:element,id:window.id,pid:window.pid,bundle:window.bundleID)
        let result:AccessibilityReadResult=await withCheckedContinuation { continuation in
            Self.accessibilityWrites.async {
                func verified(_ value:AccessibilitySnapshot?) -> AccessibilitySnapshot? {
                    guard let value,value.id==request.id,value.pid==request.pid,value.bundle==request.bundle else{return nil}
                    return value
                }
                var failure=""
                if let value=verified(Self.inspectAccessibilityWindow(request.element,messagingTimeout:0.3,onFailure:{failure=$0})) {
                    continuation.resume(returning:AccessibilityReadResult(snapshot:value,cachedFailure:"",freshFound:false));return
                }
                guard Self.windowServerFrame(id:request.id,pid:request.pid) != nil else {
                    continuation.resume(returning:AccessibilityReadResult(snapshot:nil,cachedFailure:failure,freshFound:false));return
                }
                let app=AXUIElementCreateApplication(request.pid);AXUIElementSetMessagingTimeout(app,0.3)
                typealias GetID = @convention(c)(AXUIElement,UnsafeMutablePointer<UInt32>) -> Int32
                guard let symbol=dlsym(dlopen(nil,RTLD_NOW),"_AXUIElementGetWindow") else {
                    continuation.resume(returning:AccessibilityReadResult(snapshot:nil,cachedFailure:failure,freshFound:false));return
                }
                let getID=unsafeBitCast(symbol,to:GetID.self)
                let budget = AccessibilityReadBudget(now: ProcessInfo.processInfo.systemUptime)
                let fresh=(axValue(app,kAXWindowsAttribute) as? [AXUIElement])?.first {candidate in
                    guard budget.permitsRead(now: ProcessInfo.processInfo.systemUptime, cancelled: false) else { return false }
                    AXUIElementSetMessagingTimeout(candidate,0.1)
                    var id:UInt32=0;var pid:pid_t=0
                    return AXUIElementGetPid(candidate,&pid) == .success && pid==request.pid && getID(candidate,&id)==0 && id==request.id
                }
                let value=fresh.flatMap{verified(Self.inspectAccessibilityWindow($0,messagingTimeout:0.3))}
                continuation.resume(returning:AccessibilityReadResult(snapshot:value,cachedFailure:failure,freshFound:fresh != nil))
            }
        }
        guard !Task.isCancelled, trusted else{return nil}
        if !result.cachedFailure.isEmpty || result.snapshot==nil {
            recordWindowDiagnostic("window-refresh-result.json",["executor":"serial-worker","windowID":window.id,"pid":window.pid,
                "bundle":window.bundleID,"cachedFailure":result.cachedFailure,"freshIdentityFound":result.freshFound,"eligibilityConfirmed":result.snapshot != nil])
        }
        guard let value=result.snapshot,let frame=Self.windowServerFrame(id:value.id,pid:value.pid),
              NSRunningApplication(processIdentifier:value.pid)?.bundleIdentifier==value.bundle else{return nil}
        let current = LiveWindow(id:value.id,target:.accessibility(value.element),pid:value.pid,bundleID:value.bundle,appName:value.appName,
                          title:window.title,frame:frame,spaceIDs:spaces(for:value.id),minimized:false)
        knownWindows[current.id] = current
        return current
    }
    func currentFrame(_ window: LiveWindow) -> CGRect? { Self.windowServerFrame(id: window.id, pid: window.pid) }
    private static func windowServerFrame(id: UInt32, pid: pid_t) -> CGRect? {
        let windows = CGWindowListCopyWindowInfo(.optionIncludingWindow, id) as? [[String: Any]] ?? []
        guard let info = windows.first(where: { ($0[kCGWindowNumber as String] as? UInt32) == id && ($0[kCGWindowOwnerPID as String] as? Int32) == pid }),
              info[kCGWindowLayer as String] as? Int == 0,
              let bounds = info[kCGWindowBounds as String] as? [String: Any],
              let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary), PaneGeometry.valid(frame) else { return nil }
        return frame
    }
    /// Keep synchronous cross-process AX messaging off the app's event loop. A
    /// display/Space transfer can invalidate an old AX reference; reacquire by
    /// window ID, never by title or whichever window happens to have focus.
    @MainActor func accessibilityWrite(_ window: LiveWindow, _ operation: AccessibilityWindowWrite, reuseValidatedElement: Bool = false) async -> AXError {
        guard case .accessibility(let fallback) = window.target else { return .illegalArgument }
        let request=AccessibilityWriteRequest(id:window.id,pid:window.pid,fallback:fallback,operation:operation)
        return await withTaskCancellationHandler(operation: { await withCheckedContinuation { continuation in
            Self.accessibilityQueue(for: window.pid).async {
                guard !request.isCancelled else {continuation.resume(returning:.failure);return}
                guard let currentFrame = Self.windowServerFrame(id: request.id, pid: request.pid) else {
                    continuation.resume(returning: .invalidUIElement); return
                }
                let app = AXUIElementCreateApplication(request.pid)
                AXUIElementSetMessagingTimeout(app, 0.5)
                guard let getID = Self.windowIDFunction else {
                    continuation.resume(returning: .notImplemented); return
                }
                let budget = AccessibilityReadBudget(now: ProcessInfo.processInfo.systemUptime)
                func matches(_ element: AXUIElement) -> Bool {
                    guard budget.permitsRead(now: ProcessInfo.processInfo.systemUptime, cancelled: request.isCancelled) else { return false }
                    AXUIElementSetMessagingTimeout(element, 0.5)
                    var id: UInt32 = 0; var pid: pid_t = 0
                    return AXUIElementGetPid(element, &pid) == .success && pid == request.pid &&
                        getID(element, &id) == 0 && id == request.id
                }
                let retained = reuseValidatedElement && matches(request.fallback) ? request.fallback : nil
                let fresh = retained ?? (axValue(app, kAXWindowsAttribute) as? [AXUIElement])?.first(where: matches)
                // AXWindows can omit inactive-Space windows. A retained reference
                // is usable only while both AX and WindowServer identities agree.
                guard let element = fresh ?? (matches(request.fallback) ? request.fallback : nil) else {
                    continuation.resume(returning: .invalidUIElement); return
                }
                guard !request.isCancelled else {continuation.resume(returning:.failure);return}
                AXUIElementSetMessagingTimeout(element, 0.5)
                let result = request.operation.apply(to:element, currentFrame: currentFrame)
                AXUIElementSetMessagingTimeout(element, 0.1)
                continuation.resume(returning: result)
            }
        } }, onCancel: {request.cancel()})
    }
    @MainActor func withImmediateFrames<T>(_ windows: [LiveWindow], operation: @MainActor () async throws -> T) async rethrows -> T {
        let started = ProcessInfo.processInfo.systemUptime
        let pids = Set(windows.compactMap { window -> pid_t? in
            if case .accessibility = window.target { return window.pid }
            return nil
        })
        let changed: [pid_t] = await withCheckedContinuation { continuation in
            Self.accessibilityWrites.async {
                let changed = pids.filter { pid in
                    let app = AXUIElementCreateApplication(pid)
                    AXUIElementSetMessagingTimeout(app, 0.1)
                    return (axValue(app, "AXEnhancedUserInterface") as? Bool) == true &&
                        AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanFalse) == .success
                }
                continuation.resume(returning: Array(changed))
            }
        }
        // One scope covers the whole transition/drag. Re-enabling between frames
        // is expensive and can restart the receiving app's own resize animation.
        func restore() async {
            let restored: Int = await withCheckedContinuation { continuation in
                Self.accessibilityWrites.async {
                    var restored = 0
                    for pid in changed {
                        let app = AXUIElementCreateApplication(pid)
                        AXUIElementSetMessagingTimeout(app, 0.1)
                        _ = AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
                        if (axValue(app, "AXEnhancedUserInterface") as? Bool) == true { restored += 1 }
                    }
                    continuation.resume(returning: restored)
                }
            }
            recordWindowDiagnostic("frame-session-result.json", ["elapsedSeconds": ProcessInfo.processInfo.systemUptime-started,
                "adjustedApplications": changed.count, "restoredApplications": restored, "cancelled": Task.isCancelled])
        }
        do {
            let result = try await operation()
            await restore()
            return result
        } catch {
            // Cleanup is awaited even when the movement task was cancelled.
            await restore()
            throw error
        }
    }
    func recordWindowDiagnostic(_ name: String, _ detail: [String: Any]) {
        guard includeExternal, let data = try? JSONSerialization.data(withJSONObject: detail, options: [.prettyPrinted, .sortedKeys]) else { return }
        let directory = diagnosticsDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("DeskNames")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: directory.appendingPathComponent(name), options: .atomic)
    }
    @MainActor private func accessibilityApplications() -> [AccessibilityApplication] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard includeExternal, app.activationPolicy == .regular, app.processIdentifier != getpid(),
                  let bundle = app.bundleIdentifier else { return nil }
            return AccessibilityApplication(pid: app.processIdentifier, bundle: bundle, name: app.localizedName ?? bundle)
        }
    }
    private static func listWindows(_ apps: [AccessibilityApplication], cancellation: AccessibilityReadCancellation = AccessibilityReadCancellation()) -> AccessibilityWindowCensus {
        guard let getID = windowIDFunction else { return AccessibilityWindowCensus(complete: false) }
        var result = AccessibilityWindowCensus()
        var status = AccessibilityCensusStatus()
        func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
            var value: CFTypeRef?
            let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
            status.observe(error)
            return error == .success ? value : nil
        }
        for app in apps {
            guard !cancellation.isCancelled else { result.complete = false; break }
            let budget = AccessibilityReadBudget(now: ProcessInfo.processInfo.systemUptime)
            let element = AXUIElementCreateApplication(app.pid)
            AXUIElementSetMessagingTimeout(element, 0.2)
            guard let windows = value(element, kAXWindowsAttribute) as? [AXUIElement] else { continue }
            for window in windows {
                guard budget.permitsRead(now: ProcessInfo.processInfo.systemUptime, cancelled: cancellation.isCancelled) else { result.complete = false; break }
                // An application's timeout does not apply to the window objects it returns.
                AXUIElementSetMessagingTimeout(window, 0.1)
                var id: UInt32 = 0
                let identityError = AXError(rawValue: getID(window, &id)) ?? .failure
                status.observe(identityError)
                guard identityError == .success, id > 0,
                      accessibilityIdentity(window)?.pid == app.pid else { continue }
                result.observed.insert(WindowIdentity(id: id, pid: app.pid))
                guard eligibilityMetadata(window).refusal(for: .census) == nil,
                      let frame = windowServerFrame(id: id, pid: app.pid), frame.width > 80, frame.height > 50 else { continue }
                result.windows.append(AccessibilityListedWindow(element: window, id: id, app: app, frame: frame,
                    title: value(window, kAXTitleAttribute) as? String ?? "",
                    minimized: value(window, kAXMinimizedAttribute) as? Bool ?? false))
            }
        }
        result.complete = result.complete && status.complete
        return result
    }
    @MainActor func windowsForOperation() async -> [LiveWindow] {
        await windowCensus().windows
    }
    @MainActor func windowsForLayout() async throws -> [LiveWindow] {
        let census = await windowCensus()
        try Task.checkCancellation()
        guard trusted else { throw WindowIssue("Enable Accessibility before arranging windows.") }
        return try census.forLayout()
    }
    @MainActor private func windowCensus() async -> WindowCensus {
        guard trusted, !Task.isCancelled else { return WindowCensus(windows: [], complete: false) }
        let apps = accessibilityApplications()
        let cancellation = AccessibilityReadCancellation()
        let census: AccessibilityWindowCensus = await withTaskCancellationHandler(operation: {
            await AccessibilityWorker.read(on: Self.accessibilityDiscovery) { Self.listWindows(apps, cancellation: cancellation) }
        }, onCancel: { cancellation.cancel() })
        guard trusted, !Task.isCancelled else { return WindowCensus(windows: [], complete: false) }
        return WindowCensus(windows: mergeWindows(census.windows, observed: census.observed), complete: census.complete)
    }
    @MainActor func windows() -> [LiveWindow] {
        guard trusted else { knownWindows = [:]; return [] }
        let census = Self.listWindows(accessibilityApplications())
        return mergeWindows(census.windows, observed: census.observed)
    }
    @MainActor private func mergeWindows(_ snapshots: [AccessibilityListedWindow], observed: Set<WindowIdentity>) -> [LiveWindow] {
        var result = snapshots.compactMap { value -> LiveWindow? in
            guard NSRunningApplication(processIdentifier: value.app.pid)?.bundleIdentifier == value.app.bundle,
                  let frame = Self.windowServerFrame(id: value.id, pid: value.app.pid) else { return nil }
            return LiveWindow(id: value.id, target: .accessibility(value.element), pid: value.app.pid,
                bundleID: value.app.bundle, appName: value.app.name, title: value.title, frame: frame,
                spaceIDs: spaces(for: value.id), minimized: value.minimized)
        }
        result.append(contentsOf:NSApp.windows.compactMap {localSnapshot($0)})
        // AXWindows can omit windows on inactive Spaces. Retain windows already seen,
        // but validate their owner and geometry against WindowServer on every refresh.
        knownWindows=WindowDiscovery.reconcile(cached:knownWindows,observed:observed,accepted:result,
            identity:{WindowIdentity(id:$0.id,pid:$0.pid)})
        let infos=CGWindowListCopyWindowInfo(.optionAll,kCGNullWindowID) as? [[String:Any]] ?? []
        var current:[UInt32:LiveWindow]=[:]
        for info in infos {
            guard let id=info[kCGWindowNumber as String] as? UInt32,let w=knownWindows[id],
                  (info[kCGWindowOwnerPID as String] as? Int32)==w.pid,
                  let bounds=info[kCGWindowBounds as String] as? [String:Any],
                  let frame=CGRect(dictionaryRepresentation:bounds as CFDictionary) else{continue}
            current[id]=LiveWindow(id:id,target:w.target,pid:w.pid,bundleID:w.bundleID,appName:w.appName,title:w.title,frame:frame,spaceIDs:spaces(for:id),minimized:w.minimized)
        }
        knownWindows=current
        return current.values.sorted { ($0.bundleID,$0.id)<($1.bundleID,$1.id) }
    }
    @MainActor func trackedPaneWindows() -> [LiveWindow] {
        guard trusted else { knownWindows = [:]; return [] }
        var current = knownWindows
        for window in NSApp.windows.compactMap({ localSnapshot($0) }) { current[window.id] = window }
        return current.values.compactMap { window in
            guard let frame = currentFrame(window) else { return nil }
            return LiveWindow(id: window.id, target: window.target, pid: window.pid, bundleID: window.bundleID,
                appName: window.appName, title: window.title, frame: frame, spaceIDs: spaces(for: window.id), minimized: window.minimized)
        }
    }

    @MainActor func setFrame(_ rect:CGRect,window:LiveWindow) async throws {
        guard trusted else{throw WindowIssue("Enable Accessibility for DeskNames to move windows.")}
        try Task.checkCancellation()
        guard PaneGeometry.valid(rect) else{throw WindowIssue("Could not prepare window coordinates.")}
        switch window.target {
        case .local(let local):
            guard let current = localSnapshot(local), current.id == window.id else { throw WindowIssue("The window closed before it could move.") }
            let minimum = local.frameRect(forContentRect: CGRect(origin: .zero, size: local.contentMinSize)).size
            guard rect.width >= minimum.width, rect.height >= minimum.height else { throw WindowIssue("This pane is too small for DeskNames. Choose a larger pane.") }
            let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
            local.setFrame(CGRect(x: rect.minX, y: primaryTop - rect.maxY, width: rect.width, height: rect.height), display: true)
            return
        case .accessibility: break
        }
        if window.minimized { _ = await accessibilityWrite(window,.minimized(false)) }
        // AX success means the request was accepted. AppKit may apply it asynchronously;
        // wait between requests so a resize cannot overwrite a later position update.
        for attempt in 0..<3 {
            try Task.checkCancellation()
            guard identityExists(window) else { throw WindowIssue("The window closed before it could move.") }
            if verifyFrame(rect,window:window) {return}
            let firstPosition = await accessibilityWrite(window,.position(rect.origin))
            await Self.pause(0.12)
            try Task.checkCancellation()
            if verifyFrame(rect,window:window) {return}
            let se = await accessibilityWrite(window,.size(rect.size))
            await Self.pause(0.15)
            try Task.checkCancellation()
            if verifyFrame(rect,window:window) {return}
            let pe = await accessibilityWrite(window,.position(rect.origin))
            await Self.pause(0.15)
            try Task.checkCancellation()
            if verifyFrame(rect,window:window) { return }
            // A messaging failure does not establish that the operation failed.
            // Verify through WindowServer, then retry with a fresh AX reference.
            let errors = [firstPosition, se, pe]
            if attempt < 2, errors.allSatisfy({ $0 == .success || $0 == .cannotComplete || $0 == .invalidUIElement }) {
                await Self.pause(0.2)
                continue
            }
            guard pe == .success,se == .success else {
                let detail:[String:Any] = ["positionError":pe.rawValue,"firstPositionError":firstPosition.rawValue,"sizeError":se.rawValue,"attempt":attempt+1,"windowID":window.id,"pid":window.pid,"bundle":window.bundleID,"trusted":trusted,"actual":actualFrame(window).map { ["x":$0.minX,"y":$0.minY,"width":$0.width,"height":$0.height] } ?? [:]]
                recordWindowDiagnostic("window-operation-error.json", detail)
                if errors.contains(.cannotComplete) { throw WindowIssue("Could not confirm a response from \(window.appName). Its window may have moved; refresh before trying again.") }
                throw WindowIssue("\(window.appName) refused a window move or resize.")
            }
        }
    }
    @MainActor func actualFrame(_ window: LiveWindow) -> CGRect? {
        switch window.target {
        // An AX reply can time out after applying a change. WindowServer is also
        // the source used by discovery/capture and validates window ID and PID.
        case .accessibility: return currentFrame(window)
        case .local(let local):
            guard local.isVisible, local.windowNumber == Int(window.id) else { return nil }
            let rect = local.frame, primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
            return CGRect(x: rect.minX, y: primaryTop - rect.maxY, width: rect.width, height: rect.height)
        }
    }
    @MainActor func verifyFrame(_ expected:CGRect,window:LiveWindow)->Bool {
        guard let actual=actualFrame(window) else{return false}
        return abs(actual.minX-expected.minX)<=1 && abs(actual.minY-expected.minY)<=1 && abs(actual.width-expected.width)<=1 && abs(actual.height-expected.height)<=1
    }
    static func pause(_ seconds:Double) async {try? await Task.sleep(nanoseconds:UInt64(seconds*1_000_000_000))}
    @MainActor func arrow(_ right:Bool) async {
        let source=CGEventSource(stateID:.hidSystemState)
        // Arrow keys carry these hardware flags. Replacing them with Control alone
        // causes Mission Control to ignore the synthesized shortcut on current macOS.
        let arrowFlags:CGEventFlags=[.maskControl,.maskSecondaryFn,.maskNumericPad]
        for (key,down,flags) in [(CGKeyCode(59),true,CGEventFlags.maskControl),(CGKeyCode(right ? 124:123),true,arrowFlags),(CGKeyCode(right ? 124:123),false,arrowFlags),(CGKeyCode(59),false,CGEventFlags())] {
            let e=CGEvent(keyboardEventSource:source,virtualKey:key,keyDown:down);e?.flags=flags;e?.post(tap:.cghidEventTap)
            await Self.pause(0.06)
        }
    }
    @MainActor private func carryWindowToSpace(_ target:Desktop,reader:SpaceReader) async throws {
        guard trusted else{throw WindowIssue("Enable Accessibility to use desktop shortcuts.")}
        for _ in 0..<20 {
            try Task.checkCancellation()
            let all=reader.read()
            guard let targetNow=all.first(where:{$0.id==target.id}),let current=all.first(where:{$0.display==target.display && $0.isCurrent}) else{throw WindowIssue("This desktop is no longer available.")}
            if current.id==target.id{return}
            let previous=current.id
            await arrow(targetNow.position>current.position)
            var changed=false
            for _ in 0..<25 {
                await Self.pause(0.1)
                try Task.checkCancellation()
                if reader.read().first(where:{$0.display==target.display && $0.isCurrent})?.id != previous {changed=true;break}
            }
            guard changed else{throw WindowIssue("macOS did not switch desktops. Enable Control–Left/Right in System Settings → Keyboard → Keyboard Shortcuts → Mission Control. Place the pointer on the target display.")}
            await Self.pause(0.35)
        }
        throw WindowIssue("Desktop switching did not reach the requested desktop.")
    }
    @MainActor func move(_ window:LiveWindow,to target:Desktop,reader:SpaceReader) async throws {
        if nativeSpaceMoveAvailable()==1 {try await transfer(window,to:target,reader:reader);return}
        guard trusted else{throw WindowIssue("Enable Accessibility to move windows.")}
        guard case .accessibility(let element) = window.target else { throw WindowIssue("Use Mission Control to move DeskNames to another desktop.") }
        if spaces(for:window.id).contains(target.spaceID){return}
        let all=reader.read()
        guard let source=all.first(where:{window.spaceIDs.contains($0.spaceID)}),!source.isFullScreen,!target.isFullScreen else{throw WindowIssue("Only regular desktop windows can move between Spaces.")}
        guard source.display==target.display else{throw WindowIssue("Move this window onto the target display first, then retry the desktop move.")}
        try await switchSpace(source,reader:reader)
        NSRunningApplication(processIdentifier:window.pid)?.activate(options:[])
        _=AXUIElementPerformAction(element,kAXRaiseAction as CFString)
        await Self.pause(0.3)
        guard let rect=axRect(element) else{throw WindowIssue("The window closed before it could move.")}
        var point=CGPoint(x:rect.midX,y:rect.minY+12)
        if let title=axValue(element,kAXTitleUIElementAttribute),CFGetTypeID(title)==AXUIElementGetTypeID(),let r=axRect(title as! AXUIElement) {point=CGPoint(x:r.midX,y:r.midY)}
        let original=CGEvent(source:nil)?.location ?? point
        let sourceEvent=CGEventSource(stateID:.hidSystemState)
        func mouse(_ type:CGEventType,_ p:CGPoint) {CGEvent(mouseEventSource:sourceEvent,mouseType:type,mouseCursorPosition:p,mouseButton:.left)?.post(tap:.cghidEventTap)}
        mouse(.mouseMoved,point);mouse(.leftMouseDown,point)
        var dragging=true
        defer {if dragging {mouse(.leftMouseUp,point)};mouse(.mouseMoved,original)}
        await Self.pause(0.12);point.x+=10;mouse(.leftMouseDragged,point)
        try await carryWindowToSpace(target,reader:reader)
        mouse(.leftMouseUp,point);dragging=false
        await Self.pause(0.3)
        guard spaces(for:window.id).contains(target.spaceID) else{throw WindowIssue("macOS did not move \(window.appName) to that desktop. Drag its window to the desktop in Mission Control, then restore again.")}
    }
}

@MainActor final class LayoutController:ObservableObject {
    private enum Interaction { case idle, userDrag, writing }
    private struct Operation {
        let interruptible: Bool
        let refreshWindows: Bool
        let completion: ((String) -> Void)?
        let body: @MainActor () async throws -> String
    }
    @Published private var interaction = Interaction.idle
    @Published var layouts:[String:DesktopLayout]=[:]
    @Published var windows:[LiveWindow]=[]
    @Published var selectedWindow:UInt32=0
    @Published var targetDesktop=""
    @Published var selectedLayoutID=""
    @Published var saveAcrossScreens=true {didSet{store.defaults.set(saveAcrossScreens,forKey:"saveAcrossScreens")}}
    @Published var message="Save a desktop’s windows, then restore them whenever you need."
    var busy: Bool { interaction != .idle }
    var hasUserWindowDrag: Bool { interaction == .userDrag }
    @Published var trusted=false
    @Published var columns=2
    @Published var rows=2
    @Published var gap:Double=12
    @Published var shortcutStatus=""
    let native:NativeWindows
    let frameHistory = WindowFrameHistory()
    var paneRangeChord = PaneRangeChord()
    let panes: PanePreferences
    let monitorPresets: MonitorPresets
    let routing: RoutingSettings
    var births=WindowBirthTracker()
    var lastBirthScan:Double=0
    var routingScanTask: Task<Void, Never>?
    var previewPanes: ((String) -> Void)?
    let store:Store
    let file:URL
    var lastActive:Set<String>=[]
    var pending:Task<Void,Never>?
    @Published var pinnedWindows:[UInt32:LiveWindow]=[:]
    var pinTracking=PinTracking()
    private var queuedDesktop: (desktop: Desktop, completion: ((String) -> Void)?)?
    var operationTask:Task<Void,Never>?
    private var refreshTask: Task<Void, Never>?
    var shortcutResult: ((String) -> Void)?
    private var interactivePlacement = false
    private var queuedPlacement: Operation?
    var canRetargetPlacement: Bool { interactivePlacement && interaction == .writing }
    var showSwitcher:(()->Void)?
    var onSwitch: (() -> Void)?
    init(store:Store,file:URL?=nil,native:NativeWindows=NativeWindows()) {
        self.store=store
        self.native=native
        self.panes=PanePreferences(defaults:store.defaults)
        self.monitorPresets=MonitorPresets(defaults:store.defaults)
        self.routing=RoutingSettings(defaults:store.defaults)
        self.saveAcrossScreens=store.defaults.object(forKey:"saveAcrossScreens") as? Bool ?? true
        self.file=file ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("DeskNames/layouts-v1.json")
        if let data=try? Data(contentsOf:self.file),let saved=try? JSONDecoder().decode([String:DesktopLayout].self,from:data) {layouts=saved}
        trusted=native.trusted;lastActive=Set(store.desktops.filter(\.isCurrent).map(\.id));targetDesktop=store.desktops.first(where:{$0.isCurrent})?.id ?? ""
    }
    var selectedDesktop:Desktop? {store.desktops.first(where:{$0.id==targetDesktop}) ?? store.desktops.first(where:{$0.isCurrent})}
    @discardableResult func persist()->Bool {
        do {try FileManager.default.createDirectory(at:file.deletingLastPathComponent(),withIntermediateDirectories:true);try JSONEncoder().encode(layouts).write(to:file,options:.atomic);return true} catch {message="Could not save layouts: \(error.localizedDescription)";return false}
    }
    func refresh() {
        setTrusted()
        guard refreshTask == nil else { return }
        refreshTask = Task {
            defer { refreshTask = nil }
            let live = await native.windowsForOperation()
            setTrusted()
            guard !Task.isCancelled else { return }
            guard trusted else { windows = []; selectedWindow = 0; return }
            windows = live
            if !windows.contains(where: { $0.id == selectedWindow }) { selectedWindow = windows.first?.id ?? 0 }
        }
    }
    func option(_ key:WritableKeyPath<DesktopLayout,Bool>,_ value:Bool,layoutID:String?=nil) {guard let id=layoutID ?? selectedDesktop?.id,var l=layouts[id] else{return};let old=l;l[keyPath:key]=value;layouts[id]=l;if !persist(){layouts[id]=old}}
    static func match(_ saved:SavedWindow,in candidates:[LiveWindow],used:Set<UInt32>)->LiveWindow? {
        let pool=candidates.filter{$0.bundleID==saved.bundleID && !used.contains($0.id)}
        if let exact=pool.first(where:{$0.id==saved.windowID && $0.pid==saved.pid}) {return exact}
        let titles=pool.filter{!saved.title.isEmpty && $0.title==saved.title}
        if titles.count==1{return titles[0]}
        // Do not guess when multiple documents have changed titles.
        if pool.count==1{return pool[0]}
        return nil
    }
    /// Matches every saved window at once: exact window identity first, then unique titles,
    /// then a lone remaining window of the app. Doing this per-window in order could let an
    /// earlier saved window claim a window that belongs to a later one.
    static func matchAll(_ saved:[SavedWindow],in candidates:[LiveWindow])->[LiveWindow?] {
        var result=[LiveWindow?](repeating:nil,count:saved.count);var used=Set<UInt32>()
        for (i,s) in saved.enumerated() {
            if let w=candidates.first(where:{$0.bundleID==s.bundleID && $0.id==s.windowID && $0.pid==s.pid && !used.contains($0.id)}) {result[i]=w;used.insert(w.id)}
        }
        for (i,s) in saved.enumerated() where result[i]==nil && !s.title.isEmpty {
            let titles=candidates.filter{$0.bundleID==s.bundleID && !used.contains($0.id) && $0.title==s.title}
            // A title must identify one unmatched saved window as well as one live
            // window. Otherwise duplicate saved titles make the choice arbitrary.
            let rivals=saved.indices.filter{result[$0]==nil && saved[$0].bundleID==s.bundleID && saved[$0].title==s.title}
            if titles.count==1 && rivals.count==1 {result[i]=titles[0];used.insert(titles[0].id)}
        }
        for (i,s) in saved.enumerated() where result[i]==nil {
            // A lone window is only used when no other unmatched saved window of this app could claim it.
            let pool=candidates.filter{$0.bundleID==s.bundleID && !used.contains($0.id)}
            let rivals=saved.indices.filter{result[$0]==nil && saved[$0].bundleID==s.bundleID}
            if pool.count==1 && rivals.count==1 {result[i]=pool[0];used.insert(pool[0].id)}
        }
        return result
    }
    func run(interruptible: Bool = false, refreshWindows: Bool = true, completion: ((String) -> Void)? = nil,
             _ operation: @escaping @MainActor () async throws -> String) {
        let shortcut = shortcutResult
        run(Operation(interruptible: interruptible, refreshWindows: refreshWindows,
                      completion: { text in completion?(text); shortcut?(text) }, body: operation))
    }
    private func run(_ operation: Operation) {
        if busy {
            if operation.interruptible && canRetargetPlacement {
                queuedPlacement?.completion?("Placement replaced by a newer request.")
                queuedPlacement = operation
                operationTask?.cancel()
            } else { message = "A window operation is in progress. Try again when it finishes."; operation.completion?(message) }
            return
        }
        interaction = .writing; interactivePlacement = operation.interruptible; pending?.cancel()
        message = "Working…"
        operationTask = Task {
            var result = "Operation cancelled."
            defer {
                interaction = .idle; interactivePlacement = false; operationTask = nil
                message = result
                operation.completion?(result)
                if let next = queuedPlacement {
                    queuedPlacement = nil
                    run(next)
                } else {
                    store.refresh(); lastActive = Set(store.desktops.filter(\.isCurrent).map(\.id))
                    if operation.interruptible || !operation.refreshWindows {
                        setTrusted(); windows = native.trackedPaneWindows()
                        if !windows.contains(where: { $0.id == selectedWindow }) { selectedWindow = windows.first?.id ?? 0 }
                    } else { refresh() }
                    births.reset(); drainDesktopRequest()
                }
            }
            do { try Task.checkCancellation(); result = try await operation.body(); try Task.checkCancellation() }
            catch is CancellationError { result = "Operation cancelled." }
            catch { result = error.localizedDescription }
        }
    }
    func cancel() {
        queuedPlacement?.completion?("Operation cancelled."); queuedPlacement = nil
        queuedDesktop?.completion?("Operation cancelled."); queuedDesktop = nil
        operationTask?.cancel(); pending?.cancel(); routingScanTask?.cancel(); refreshTask?.cancel(); endUserWindowDrag()
    }
    func beginUserWindowDrag() -> Bool {
        guard !busy, native.trusted else { return false }
        pending?.cancel()
        interaction = .userDrag
        return true
    }
    func endUserWindowDrag() { if interaction == .userDrag { interaction = .idle;births.reset();drainDesktopRequest() } }
    func finishUserWindowDrag(_ window: LiveWindow, frame: CGRect, displayID: String, desktopID: String, originalFrame: CGRect? = nil,
                              completion: @escaping (String, Bool) -> Void) {
        guard hasUserWindowDrag else { completion("The window operation was cancelled.", false); return }
        interaction = .idle
        var matched = false
        run(interruptible: true, completion: { completion($0, matched) }) {
            try Task.checkCancellation()
            let refreshed=await self.native.refreshedForOperation(window)
            try Task.checkCancellation()
            self.store.refresh()
            guard !OverlayController.isMissionControlOpen(),
                  let desktop = self.store.desktops.first(where: { $0.id == desktopID && $0.isCurrent && !$0.isFullScreen }),
                  let screen = NSScreen.screens.first(where: { screenUUID($0) == displayID }),
                  screenArea(screen).contains(frame),
                  let current = refreshed, current.spaceIDs.contains(desktop.spaceID),
                  abs(current.frame.width - window.frame.width) <= 2, abs(current.frame.height - window.frame.height) <= 2 else {
                return "Window or desktop changed. Nothing was snapped."
            }
            try await self.native.animateFrames([(current, frame)])
            matched = self.native.verifyFrame(frame, window: current)
            if matched, let source=screenFor(originalFrame ?? window.frame) { self.frameHistory.remember(window,frame:originalFrame ?? window.frame,screen:source) }
            return matched ? "Placed \(current.appName) in its pane." : "\(current.appName) needs a different window size."
        }
    }
    func restore() {
        guard let selected=selectedDesktop,let layout=restoreSelection else{message="Save a layout for this desktop before restoring windows.";return}
        let desktop=store.desktops.first(where:{$0.id==layout.id}) ?? selected
        run {try await self.restoreLayout(desktop,automatic:false,layoutID:layout.id)}
    }
    func restoreLayout(_ desktop:Desktop,automatic:Bool,layoutID:String?=nil) async throws->String {
        try Task.checkCancellation()
        guard native.trusted else{throw WindowIssue("Enable Accessibility before restoring windows.")}
        guard let layout=layouts[layoutID ?? desktop.id] else{throw WindowIssue("Save a layout for this desktop first.")}
        if automatic && !store.reader.read().contains(where:{$0.id==desktop.id && $0.isCurrent}) {return "Automatic restore cancelled because you changed desktops."}
        func activateSavedDesktops() async throws {
            let all=store.reader.read(),screens=ConnectedDisplay.all()
            let savedDisplays=Dictionary(layout.windows.map{($0.displayID,$0.displayProfile)},uniquingKeysWith:{$0 ?? $1})
            let mapping=DisplayMatching.assignment(saved:savedDisplays,ids:screens.map(\.id),profiles:screens.map(\.profile))
            let targets=layout.windows.compactMap{$0.destination(layoutDesktop:desktop,desktops:all,screens:screens,displayMap:mapping)?.0}
            for screen in screens {
                try Task.checkCancellation()
                let candidates=targets.filter{$0.display==screen.id}
                guard Set(candidates.map(\.id)).count==1,let target=candidates.first else{continue}
                try await native.switchSpace(target,reader:store.reader)
            }
        }
        if !automatic {try await activateSavedDesktops()}
        if layout.launchMissing {
            var launched=Set<String>()
            for bundle in Set(layout.windows.map(\.bundleID)) where NSRunningApplication.runningApplications(withBundleIdentifier:bundle).isEmpty {
                try Task.checkCancellation()
                guard let url=NSWorkspace.shared.urlForApplication(withBundleIdentifier:bundle) else{continue}
                do { try await launchLayoutApplication(at: url); launched.insert(bundle) }
                catch is CancellationError { throw CancellationError() }
                catch ApplicationLaunchIssue.timedOut { throw ApplicationLaunchIssue.timedOut }
                catch { continue }
            }
            // Wait only for apps launched just now, so a running app with no open window
            // (or an uninstalled one) does not add a 3-second delay to every restore.
            for _ in 0..<(launched.isEmpty ? 0:10) {
                try Task.checkCancellation()
                if Set(await native.windowsForOperation().map(\.bundleID)).isSuperset(of:launched) {break}
                await NativeWindows.pause(0.3)
            }
        }
        try Task.checkCancellation()
        var available=try await native.windowsForLayout()
        try Task.checkCancellation()
        if layout.gatherWindows && !automatic {
            // After a DeskNames restart, discover surviving saved windows on other
            // Spaces before falling back to title matching on the destination.
            let infos=CGWindowListCopyWindowInfo(.optionAll,kCGNullWindowID) as? [[String:Any]] ?? []
            var sourceIDs=Set<UInt64>()
            for saved in layout.windows where !available.contains(where:{$0.id==saved.windowID && $0.pid==saved.pid}) {
                if infos.contains(where:{($0[kCGWindowNumber as String] as? UInt32)==saved.windowID && ($0[kCGWindowOwnerPID as String] as? Int32)==saved.pid}) {
                    sourceIDs.formUnion(native.spaces(for:saved.windowID))
                }
            }
            for source in store.reader.read() where sourceIDs.contains(source.spaceID) && source.id != desktop.id && !source.isFullScreen {
                try Task.checkCancellation()
                try await native.switchSpace(source,reader:store.reader)
                available=try await native.windowsForLayout()
            }
            try await activateSavedDesktops()
            available=try await native.windowsForLayout()
        }
        var restored=0;var skipped=0;var limited=0;var adapted=0;var unavailable=0
        var ordered:[(Int,LiveWindow)]=[]
        let screens=ConnectedDisplay.all(),topology=store.reader.read()
        let savedDisplays=Dictionary(layout.windows.map{($0.displayID,$0.displayProfile)},uniquingKeysWith:{$0 ?? $1})
        let displayMap=DisplayMatching.assignment(saved:savedDisplays,ids:screens.map(\.id),profiles:screens.map(\.profile))
        for (saved,match) in zip(layout.windows,Self.matchAll(layout.windows,in:available)) {
            try Task.checkCancellation()
            guard let (destination,screen)=saved.destination(layoutDesktop:desktop,desktops:topology,screens:screens,displayMap:displayMap) else {unavailable+=1;continue}
            if automatic && !store.reader.read().contains(where:{$0.id==destination.id && $0.isCurrent}) {skipped+=1;continue}
            guard let w=match else{skipped+=1;continue}
            if !native.spaces(for:w.id).contains(destination.spaceID) {
                guard layout.gatherWindows && !automatic else{skipped+=1;continue}
                do {try await native.move(w,to:destination,reader:store.reader)} catch is CancellationError {throw CancellationError()} catch {skipped+=1;continue}
            }
            guard native.identityExists(w),ConnectedDisplay.all().contains(where:{$0.id==screen.id && $0.area==screen.area}),store.reader.read().contains(where:{$0.id==destination.id && $0.display==screen.id}) else {unavailable+=1;continue}
            let (frame,exact)=saved.restoredFrame(in:screen.area,bounds:screen.bounds)
            do {
                try await native.setFrame(frame,window:w)
                if native.verifyFrame(frame,window:w) {
                    restored+=1;if !exact || screen.id != saved.displayID {adapted+=1}
                } else {limited+=1}
            } catch is CancellationError {throw CancellationError()} catch {limited+=1}
            // An app's minimum size can prevent exact geometry without preventing
            // overlap restoration. Keep every surviving window on its destination.
            if let rank=saved.stackingIndex,native.identityExists(w),native.spaces(for:w.id)==[destination.spaceID],
               topology.contains(where:{$0.id==destination.id && $0.isCurrent}) {ordered.append((rank,w))}
        }
        var orderMessage=""
        try Task.checkCancellation()
        if !automatic,!ordered.isEmpty {
            let success=await native.restoreOrder(ordered.sorted{$0.0<$1.0}.map(\.1),reader:store.reader)
            try Task.checkCancellation()
            orderMessage=success ? " Overlap order restored." : " Window order could not be fully restored."
        }
        return "Restored \(restored) windows.\(adapted>0 ? " \(adapted) adapted to the current screen/model.":"")\(limited>0 ? " \(limited) apps constrained their placement.":"")\(unavailable>0 ? " \(unavailable) skipped: saved screen/desktop unavailable or ambiguous.":"")\(skipped>0 ? " \(skipped) missing, ambiguous or on another desktop.":"")"+orderMessage
    }
    // @Published fires on every assignment, so only write when the value changes;
    // otherwise the 0.2 s timer redraws the whole editor five times a second.
    func setTrusted() {let t=native.trusted;if trusted != t {trusted=t}}
    func tick() {
        updatePaneRangeChord()
        setTrusted()
        scanNewWindows()
        followPinnedWindows()
        let active=Set(store.desktops.filter(\.isCurrent).map(\.id))
        guard active != lastActive else{return}
        let entered=active.subtracting(lastActive);lastActive=active
        guard !busy else{return};pending?.cancel()
        pending=Task {await NativeWindows.pause(0.7);guard !Task.isCancelled,!self.busy else{return}
            self.pending = nil
            let desktops = self.store.desktops.filter { entered.contains($0.id) && $0.isCurrent && self.layouts[$0.id]?.autoRestore == true }
            guard !desktops.isEmpty else { return }
            self.runAutomaticRestores(desktops) { try await self.restoreLayout($0, automatic: true) }
        }
    }
    func runAutomaticRestores(_ desktops: [Desktop], restoring: @escaping @MainActor (Desktop) async throws -> String) {
        run(Operation(interruptible: false, refreshWindows: false, completion: nil) {
            var result = "No saved desktop needed restoring."
            for desktop in desktops {
                try Task.checkCancellation()
                do { result = try await restoring(desktop) }
                catch is CancellationError { throw CancellationError() }
                catch ApplicationLaunchIssue.timedOut { throw ApplicationLaunchIssue.timedOut }
                catch { result = error.localizedDescription }
            }
            return result
        })
    }
    func switchTo(_ d:Desktop) {
        onSwitch?()
        queuedDesktop?.completion?("Desktop jump replaced by a newer request.")
        queuedDesktop=(d, shortcutResult)
        if busy { message="Desktop jump queued until the current window operation finishes." }
        drainDesktopRequest()
    }
    private func drainDesktopRequest() {
        guard !busy,let request=queuedDesktop else{return}
        queuedDesktop=nil
        let d = request.desktop
        run(Operation(interruptible: false, refreshWindows: true, completion: request.completion) {
            try await self.native.switchSpace(d,reader:self.store.reader)
            if self.layouts[d.id]?.autoRestore == true {return try await self.restoreLayout(d,automatic:true)}
            return "Switched to \(self.store.name(d))."
        })
    }
    func moveSelected() {guard let w=windows.first(where:{$0.id==selectedWindow}),let d=selectedDesktop else{return};run {try await self.native.move(w,to:d,reader:self.store.reader);return "Moved \(w.appName) to \(self.store.name(d))."}}
    static func grid(_ area:CGRect,columns:Int,rows:Int,gap:Double)->[CGRect] {
        let c=max(1,min(4,columns)),r=max(1,min(4,rows));let g=max(0,min(40,gap))
        let w=(area.width-g*Double(c+1))/Double(c),h=(area.height-g*Double(r+1))/Double(r)
        return (0..<(c*r)).map {i in CGRect(x:area.minX+g+Double(i%c)*(w+g),y:area.minY+g+Double(i/c)*(h+g),width:w,height:h)}
    }
    func snap(_ cell:Int,columns:Int,rows:Int) {
        guard let w=windows.first(where:{$0.id==selectedWindow}),let screen=screenFor(w.frame) else{return}
        run {let frames=Self.grid(screenArea(screen),columns:columns,rows:rows,gap:self.gap);guard frames.indices.contains(cell) else{throw WindowIssue("Select a valid grid cell.")};try await self.native.animateFrames([(w, frames[cell])]);if self.native.verifyFrame(frames[cell],window:w) {self.frameHistory.remember(w,frame:w.frame,screen:screen)};return self.native.verifyFrame(frames[cell],window:w) ? "Placed \(w.appName)." : "\(w.appName) kept a different size or position."}
    }
    func tile() {
        guard let d=selectedDesktop,d.isCurrent else{message="Switch to the selected desktop before arranging its windows.";return}
        run {
            self.windows=await self.native.windowsForOperation()
            try Task.checkCancellation()
            let live=self.windows.filter{$0.spaceIDs.contains(d.spaceID) && !$0.minimized};var moved=0;var failed=0;var limited=0
            for screen in NSScreen.screens {
                let id=screenUUID(screen);let list=live.filter{screenFor($0.frame).map(screenUUID)==id}
                let frames=Self.grid(screenArea(screen),columns:self.columns,rows:self.rows,gap:self.gap)
                for (w,r) in zip(list,frames) {
                    try Task.checkCancellation()
                    do {try await self.native.setFrame(r,window:w);if self.native.verifyFrame(r,window:w){moved+=1}else{limited+=1}}catch is CancellationError {throw CancellationError()}catch{failed+=1}
                }
                failed+=max(0,list.count-frames.count)
            }
            return "Arranged \(moved) windows.\(limited>0 ? " \(limited) apps constrained their size.":"")\(failed>0 ? " \(failed) windows did not fit or refused resizing.":"")"
        }
    }
}
