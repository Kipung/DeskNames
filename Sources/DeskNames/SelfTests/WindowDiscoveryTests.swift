import AppKit

func runWindowDiscoveryTests() {
    func metadata(_ subrole: String? = kAXStandardWindowSubrole, movable: Bool? = nil) -> WindowEligibilityMetadata {
        WindowEligibilityMetadata(role: kAXWindowRole, subrole: subrole, positionSettable: movable)
    }
    for subrole in [nil, "", "AXUnknown"] as [String?] {
        precondition(metadata(subrole, movable: true).refusal(for: .operation) == nil)
        for capability in [nil, false] as [Bool?] {
            precondition(metadata(subrole, movable: capability).refusal(for: .census) != nil)
            precondition(metadata(subrole, movable: capability).refusal(for: .operation) != nil)
        }
    }
    for error in [AXError.cannotComplete, .apiDisabled, .invalidUIElement, .failure] {
        var unreadable = metadata(nil, movable: true)
        unreadable.readFailure = WindowDiscovery.attributeFailure(error, name: kAXSubroleAttribute)
        precondition(unreadable.refusal(for: .operation) != nil, "An AX error must not admit an auxiliary window as an unknown subrole")
        precondition(unreadable.refusal(for: .census) != nil)
    }
    var malformed = metadata(nil, movable: true)
    malformed.readFailure = "AXSubrole-invalid-type"
    precondition(malformed.refusal(for: .operation) != nil)
    for error in [AXError.success, .noValue, .attributeUnsupported] {
        precondition(WindowDiscovery.attributeFailure(error, name: kAXSubroleAttribute) == nil)
    }
    for capability in [nil, false, true] as [Bool?] {
        precondition(metadata(movable: capability).refusal(for: .operation) == nil, "Standard windows retain existing eligibility")
    }
    for subrole in ["AXDialog", "AXSystemDialog", "AXSheet", "AXFloatingWindow", "AXPopover", "AXFutureAuxiliary"] {
        precondition(metadata(subrole, movable: true).refusal(for: .operation) != nil)
    }
    var state = metadata(movable: true)
    state.role = "AXSheet"
    precondition(state.refusal(for: .operation) != nil)
    state = metadata(); state.modal = true
    precondition(state.refusal(for: .operation) == "modal-window")
    state = metadata(); state.hasSheets = true
    precondition(state.refusal(for: .operation) == "window-has-sheet")
    state = metadata(); state.fullScreen = true
    precondition(state.refusal(for: .census) == "fullscreen-window" && state.refusal(for: .operation) == "fullscreen-window")
    state = metadata(); state.minimized = true
    precondition(state.refusal(for: .census) == nil && state.refusal(for: .operation) == "minimized-window")

    struct Fixture {
        var identity: WindowIdentity
        var metadata: WindowEligibilityMetadata
        var title = ""
    }
    let document = Fixture(identity: WindowIdentity(id: 10, pid: 100), metadata: metadata(nil, movable: true))
    let behind = Fixture(identity: WindowIdentity(id: 11, pid: 100), metadata: metadata(), title: "Document")
    let wrongOwner = Fixture(identity: WindowIdentity(id: 10, pid: 200), metadata: metadata())
    let cached = [document.identity.id: document, behind.identity.id: behind]
    let rejected = WindowDiscovery.reconcile(cached: cached, observed: [document.identity], accepted: [], identity: { $0.identity })
    precondition(rejected[document.identity.id] == nil, "A window refused by the current census must not return from cache")
    precondition(rejected[behind.identity.id]?.identity == behind.identity, "AXWindows omissions retain inactive-Space identities")
    var renamed = document; renamed.title = "Updated"
    let accepted = WindowDiscovery.reconcile(cached: cached, observed: [document.identity], accepted: [renamed], identity: { $0.identity })
    precondition(accepted[document.identity.id]?.title == "Updated")
    let reused = WindowDiscovery.reconcile(cached: cached, observed: [document.identity], accepted: [wrongOwner], identity: { $0.identity })
    precondition(reused[document.identity.id]?.identity == wrongOwner.identity)
    let bounds = CGRect(x: 0, y: 0, width: 600, height: 400)
    let front = WindowServerCandidate(identity: document.identity, layer: 0, bounds: bounds)
    let blocker = WindowServerCandidate(identity: behind.identity, layer: 3, bounds: bounds)
    let point = CGPoint(x: 50, y: 50)
    precondition(WindowDiscovery.foremost(at: point, in: [blocker, front])?.identity == blocker.identity,
                 "A higher-layer visible window blocks pointer fallback")
    precondition(WindowDiscovery.foremost(for: 100, in: [blocker, front])?.identity == blocker.identity,
                 "A same-app floating window blocks focused fallback before eligibility filtering")
    var hidden = blocker; hidden.onScreen = false
    var transparent = blocker; transparent.alpha = 0
    precondition(WindowDiscovery.foremost(at: point, in: [hidden, transparent, front])?.identity == document.identity)
    precondition(WindowDiscovery.foremost(at: CGPoint(x: 700, y: 50), in: [front]) == nil)
    precondition(WindowDiscovery.foremost(for: 200, in: [front]) == nil)

    func expect(_ reason: String, _ body: () throws -> Void) {
        do { try body(); preconditionFailure("Expected \(reason)") }
        catch let failure as WindowDiscoveryFailure { precondition(failure.reason == reason, failure.reason) }
        catch { preconditionFailure("Unexpected discovery error \(error)") }
    }
    func inspect(_ fixture: Fixture) throws -> Fixture {
        if let refusal = fixture.metadata.refusal(for: .operation) { throw WindowDiscoveryFailure(refusal) }
        return fixture
    }
    func resolve(_ focused: WindowAttributeRead<Fixture> = .absent, main: Fixture? = nil,
                 windows: [Fixture] = [document], currentPID: Int32 = 100) throws -> Fixture {
        try WindowDiscovery.focused(pid: 100, focused: focused, front: { front }, main: { main }, windows: { windows },
            identity: { $0.identity }, inspect: inspect, currentPID: { currentPID })
    }
    precondition(try! resolve(.value(document)).identity == document.identity, "A titleless movable unknown-subrole window is eligible")
    precondition(try! resolve(main: behind).identity == document.identity, "A main-window mismatch must resolve the foremost CG identity")
    precondition(try! resolve(main: document, windows: []).identity == document.identity)
    expect("front-window-identity-unmatched") { _ = try resolve(main: behind, windows: [behind]) }
    expect("front-window-identity-unmatched") { _ = try resolve(windows: [wrongOwner]) }
    expect("front-window-identity-ambiguous") { _ = try resolve(windows: [document, document]) }
    expect("focused-window-owner-mismatch") { _ = try resolve(.value(wrongOwner)) }
    expect("frontmost-app-changed") { _ = try resolve(currentPID: 200) }
    expect("front-window-layer 3") {
        _ = try WindowDiscovery.exactWindow(for: blocker, windows: { [behind, document] }, identity: { $0.identity })
    }
    expect("front-window-owner-mismatch") {
        _ = try WindowDiscovery.exactWindow(for: front, owner: 200, windows: { [document] }, identity: { $0.identity })
    }
    for attribute in [WindowAttributeRead<Fixture>.failure("AXFocusedWindow-error -25204"), .value(Fixture(identity: document.identity, metadata: state))] {
        let reason: String
        if case .failure(let error) = attribute { reason = error } else { reason = "minimized-window" }
        expect(reason) {
            _ = try WindowDiscovery.focused(pid: 100, focused: attribute,
                front: { preconditionFailure("An explicit focused window or AX read error must not fall back") },
                main: { preconditionFailure("No main-window fallback") }, windows: { preconditionFailure("No AXWindows fallback") },
                identity: { $0.identity }, inspect: inspect, currentPID: { 100 })
        }
    }
    var sheetBlocked = document; sheetBlocked.metadata.hasSheets = true
    expect("window-has-sheet") { _ = try resolve(.value(sheetBlocked), main: document) }
    var modal = document; modal.metadata.modal = true
    expect("modal-window") { _ = try resolve(.value(modal), main: document) }
    var auxiliary = document; auxiliary.metadata.subrole = "AXFloatingWindow"
    expect("window-subrole AXFloatingWindow") { _ = try resolve(windows: [auxiliary, behind]) }
    expect("front-window-layer 3") {
        _ = try WindowDiscovery.focused(pid: 100, focused: WindowAttributeRead<Fixture>.absent,
            front: { WindowDiscovery.foremost(for: 100, in: [blocker, front]) }, main: { document },
            windows: { [document] }, identity: { $0.identity }, inspect: inspect, currentPID: { 100 })
    }
    var sameTitle = behind; sameTitle.title = document.title
    expect("front-window-identity-unmatched") { _ = try resolve(main: sameTitle, windows: [sameTitle]) }
    precondition(WindowDiscovery.message(for: "modal-window pid=100 app=test.app").contains("dialog or sheet"))
    precondition(WindowDiscovery.message(for: "AXFocusedWindow-error -25204").contains("did not answer Accessibility"))
    print("PASS: shared window eligibility, titleless move-capable discovery, conservative CG identity fallback, focused refusal and frontmost-owner recheck")
}
