import AppKit

struct WindowEligibilityMetadata {
    enum Use { case census, operation }
    var role: String?
    var subrole: String?
    var readFailure: String?
    var modal = false
    var fullScreen = false
    var minimized = false
    var positionSettable: Bool?
    var hasSheets = false

    func refusal(for use: Use) -> String? {
        if let readFailure { return readFailure }
        guard role == kAXWindowRole else { return "window-role \(role ?? "missing")" }
        if modal { return "modal-window" }
        if hasSheets { return "window-has-sheet" }
        if fullScreen { return "fullscreen-window" }
        if use == .operation && minimized { return "minimized-window" }
        if subrole == kAXStandardWindowSubrole { return nil }
        guard subrole == nil || subrole == "" || subrole == "AXUnknown" else { return "window-subrole \(subrole!)" }
        return positionSettable == true ? nil : "window-move-capability-unconfirmed"
    }
}

struct WindowIdentity: Hashable {
    let id: UInt32
    let pid: Int32
}

struct WindowServerCandidate {
    let identity: WindowIdentity
    let layer: Int
    let bounds: CGRect
    var onScreen = true
    var alpha: Double = 1
    var visible: Bool {
        onScreen && alpha > 0 && bounds.origin.x.isFinite && bounds.origin.y.isFinite &&
            bounds.width.isFinite && bounds.height.isFinite && bounds.width > 0 && bounds.height > 0
    }
}

enum WindowAttributeRead<Element> {
    case value(Element), absent, failure(String)
}

struct WindowDiscoveryFailure: Error, Equatable {
    let reason: String
    init(_ reason: String) { self.reason = reason }
}

enum WindowDiscovery {
    static func reconcile<Window>(cached: [UInt32: Window], observed: Set<WindowIdentity>, accepted: [Window],
                                  identity: (Window) -> WindowIdentity) -> [UInt32: Window] {
        var result = cached.filter { !observed.contains(identity($0.value)) }
        for window in accepted { result[identity(window).id] = window }
        return result
    }

    static func attributeFailure(_ error: AXError, name: String) -> String? {
        switch error {
        case .success, .noValue, .attributeUnsupported: return nil
        default: return "\(name)-error \(error.rawValue)"
        }
    }

    static func foremost(at point: CGPoint, in windows: [WindowServerCandidate]) -> WindowServerCandidate? {
        windows.first { $0.visible && $0.bounds.contains(point) }
    }

    static func foremost(for pid: Int32, in windows: [WindowServerCandidate]) -> WindowServerCandidate? {
        windows.first { $0.visible && $0.layer >= 0 && $0.identity.pid == pid }
    }

    static func message(for refusal: String) -> String {
        if refusal == "accessibility-off" { return "Enable Accessibility for DeskNames to use the focused window." }
        if refusal == "frontmost-app-changed" { return "The active app changed. Try the shortcut again." }
        if refusal.hasPrefix("modal-window") || refusal.hasPrefix("window-has-sheet") { return "Close the focused window's dialog or sheet before arranging it." }
        if refusal.hasPrefix("fullscreen-window") { return "Leave full screen before arranging this window." }
        if refusal.hasPrefix("minimized-window") { return "Restore the minimized window before arranging it." }
        if refusal.hasPrefix("window-subrole") || refusal.hasPrefix("front-window-layer") || refusal.hasPrefix("window-role") {
            return "This window does not expose a supported document-window type. Focus another window and try again."
        }
        if refusal.hasPrefix("window-move-capability") { return "The focused app does not confirm that this window can move." }
        if refusal.hasPrefix("AXFocusedWindow-error") { return "The focused app did not answer Accessibility. Try the shortcut again." }
        if refusal == "ineligible-local-window" || refusal.hasPrefix("desknames-window") { return "Focus an application document window before using this shortcut." }
        return "Could not safely identify the focused window. Focus a document window and try again."
    }

    static func exactWindow<Element>(for front: WindowServerCandidate, owner: Int32? = nil, main: Element? = nil,
                                     windows: () -> [Element], identity: (Element) -> WindowIdentity?) throws -> Element {
        guard front.layer == 0 else { throw WindowDiscoveryFailure("front-window-layer \(front.layer)") }
        if let owner, owner != front.identity.pid { throw WindowDiscoveryFailure("front-window-owner-mismatch") }
        if let main, identity(main) == front.identity { return main }
        let matches = windows().filter { identity($0) == front.identity }
        guard matches.count == 1 else {
            throw WindowDiscoveryFailure(matches.isEmpty ? "front-window-identity-unmatched" : "front-window-identity-ambiguous")
        }
        return matches[0]
    }

    static func focused<Element, Window>(pid: Int32, focused: WindowAttributeRead<Element>,
                                        front: () -> WindowServerCandidate?, main: () -> Element?, windows: () -> [Element],
                                        identity: (Element) -> WindowIdentity?, inspect: (Element) throws -> Window,
                                        currentPID: () -> Int32?) throws -> Window {
        let element: Element
        switch focused {
        case .value(let value):
            guard identity(value)?.pid == pid else { throw WindowDiscoveryFailure("focused-window-owner-mismatch") }
            element = value
        case .failure(let reason): throw WindowDiscoveryFailure(reason)
        case .absent:
            guard let candidate = front(), candidate.identity.pid == pid else { throw WindowDiscoveryFailure("front-window-unavailable") }
            element = try exactWindow(for: candidate, owner: pid, main: main(), windows: windows, identity: identity)
        }
        let window = try inspect(element)
        guard currentPID() == pid else { throw WindowDiscoveryFailure("frontmost-app-changed") }
        return window
    }
}
