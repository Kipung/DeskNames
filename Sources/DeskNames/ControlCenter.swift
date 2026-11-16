import AppKit
import SwiftUI
import Carbon

enum ControlCenterRoute: Equatable {
    case controls, settings(SettingsPage)

    var size: CGSize {
        switch self {
        case .controls: return CGSize(width: 560, height: 620)
        case .settings: return CGSize(width: 1020, height: 820)
        }
    }
}

@MainActor final class ControlCenter: NSObject, NSWindowDelegate {
    let panel: NSWindow
    private(set) var route = ControlCenterRoute.controls
    var quickSection = 0
    private(set) var previousApplication: NSRunningApplication?
    private var controls: (() -> AnyView)?
    private var settings: ((SettingsPage) -> AnyView)?
    private var onboarding = false
    var onClose: (() -> Void)?
    var willNavigate: (() -> Void)?

    override init() {
        panel = NSWindow(contentRect: CGRect(origin: .zero, size: ControlCenterRoute.controls.size),
                        styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        super.init()
        panel.title = "DeskNames control panel"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
        panel.isRestorable = false
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.collectionBehavior.insert(.moveToActiveSpace)
        panel.delegate = self
    }

    func present(previousApplication: NSRunningApplication?, screen: NSScreen?, onboarding: Bool,
                 route: ControlCenterRoute = .controls, controls: @escaping () -> AnyView,
                 settings: @escaping (SettingsPage) -> AnyView) {
        if previousApplication?.processIdentifier != getpid() { self.previousApplication = previousApplication }
        self.controls = controls; self.settings = settings; self.onboarding = onboarding
        navigate(to: route, screen: screen)
    }

    func navigate(to route: ControlCenterRoute, screen: NSScreen? = nil) {
        willNavigate?()
        self.route = route
        let content: AnyView?
        switch route {
        case .controls: content = controls?()
        case .settings(let page): content = settings?(page)
        }
        guard let content else { return }
        panel.contentView = NSHostingView(rootView: content.onExitCommand { [weak self] in self?.dismiss() })
        panel.styleMask = route == .controls ? [.titled, .closable, .fullSizeContentView] : [.titled, .closable, .resizable, .fullSizeContentView]
        panel.level = route == .controls ? .floating : .normal
        panel.contentMinSize = route == .controls ? NSSize(width: 560, height: 520) : NSSize(width: 640, height: 520)
        let targetScreen = screen ?? panel.screen ?? NSScreen.main
        let size = route == .controls && onboarding ? CGSize(width: 560, height: 690) : route.size
        if let area = targetScreen?.visibleFrame {
            panel.setFrame(Self.frame(size: size, within: area), display: true)
        } else { panel.setContentSize(size); panel.center() }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    static func frame(size: CGSize, within area: CGRect) -> CGRect {
        let size = CGSize(width: min(size.width, area.width), height: min(size.height, area.height))
        return CGRect(x: area.midX-size.width/2, y: area.midY-size.height/2, width: size.width, height: size.height)
    }

    static func isBackgroundLaunch(_ event: NSAppleEventDescriptor?) -> Bool {
        guard let event, event.eventID == AEEventID(kAEOpenApplication) else { return false }
        let reason = event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue
        return reason == OSType(keyAELaunchedAsLogInItem) || reason == OSType(keyAELaunchedAsServiceItem)
    }

    static func shouldToggleClosed(visible: Bool, active: Bool, forceOpen: Bool) -> Bool {
        !forceOpen && visible && active
    }

    func dismiss(restoreFocus: Bool = true) {
        panel.orderOut(nil)
        onClose?()
        if restoreFocus, let previousApplication, previousApplication.processIdentifier != getpid() {
            previousApplication.activate(options: [])
        }
        previousApplication = nil
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        dismiss()
        return false
    }
}
