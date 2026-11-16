import AppKit
import SwiftUI
import Carbon

@MainActor func runControlCenterTests() {
    let domain = "local.desknames.control-center-test.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: domain)!
    defer { defaults.removePersistentDomain(forName: domain) }
    let before = defaults.persistentDomain(forName: domain) ?? [:]
    let preferences = GeneralPreferences(defaults: defaults)
    precondition(preferences.showMenuBarIcon && preferences.showDesktopNames && preferences.hideWhenInactive)
    precondition(NSDictionary(dictionary: before).isEqual(to: defaults.persistentDomain(forName: domain) ?? [:]),
                 "Reading appearance defaults must not write preferences or suppress first-run setup")
    defaults.set(Data([1, 2, 3]), forKey: "keyboardShortcuts.v1")
    preferences.setShowMenuBarIcon(false)
    preferences.setShowDesktopNames(false)
    preferences.setHideWhenInactive(false)
    let restored = GeneralPreferences(defaults: defaults)
    precondition(!restored.showMenuBarIcon && !restored.showDesktopNames && !restored.hideWhenInactive)
    precondition(defaults.data(forKey: "keyboardShortcuts.v1") == Data([1, 2, 3]))
    precondition(ControlCenter.shouldToggleClosed(visible: true, active: true, forceOpen: false))
    precondition(!ControlCenter.shouldToggleClosed(visible: true, active: false, forceOpen: false))
    precondition(!ControlCenter.shouldToggleClosed(visible: true, active: true, forceOpen: true),
                 "Reopening the app always opens controls even when a hidden window reports visible")
    let launch = NSAppleEventDescriptor(eventClass: AEEventClass(kCoreEventClass), eventID: AEEventID(kAEOpenApplication),
                                       targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
    precondition(!ControlCenter.isBackgroundLaunch(nil) && !ControlCenter.isBackgroundLaunch(launch))
    for reason in [keyAELaunchedAsLogInItem, keyAELaunchedAsServiceItem] {
        launch.setParam(NSAppleEventDescriptor(enumCode: OSType(reason)), forKeyword: AEKeyword(keyAEPropData))
        precondition(ControlCenter.isBackgroundLaunch(launch), "Background startup should not open hidden-icon controls")
    }
    let area = CGRect(x: -800, y: 50, width: 800, height: 600)
    for route in [ControlCenterRoute.controls, .settings(.general)] {
        let frame = ControlCenter.frame(size: route.size, within: area)
        precondition(area.contains(frame) && frame.midX == area.midX && frame.midY == area.midY)
    }
    print("PASS: control-center routes, forced reopen, bounded placement, read-only defaults and independent menu-bar preferences")
}

@MainActor func runControlCenterSessionTests() async throws {
    let domain = "local.desknames.control-center-session.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: domain)!
    defer { defaults.removePersistentDomain(forName: domain) }
    let preferences = GeneralPreferences(defaults: defaults)
    let shortcuts = ShortcutSettings(defaults: defaults)
    let center = ControlCenter()
    defer { center.dismiss(restoreFocus: false) }
    let native = NativeWindows(trustCheck: { true }, includeExternal: false)
    var closes = 0
    center.onClose = { closes += 1 }
    center.present(previousApplication: nil, screen: NSScreen.main, onboarding: false,
                   controls: { AnyView(Text("Control center fixture").frame(width: 560, height: 620)) },
                   settings: { _ in AnyView(Text("Settings fixture").frame(maxWidth: .infinity, maxHeight: .infinity)) })
    await NativeWindows.pause(0.08)
    let number = center.panel.windowNumber
    precondition(center.panel.isVisible && native.localSnapshot(center.panel) == nil,
                 "Quick controls are not ordinary windows eligible for capture")
    center.quickSection = 2
    center.navigate(to: .settings(.shortcuts))
    await NativeWindows.pause(0.08)
    precondition(center.panel.windowNumber == number && center.panel.level == .normal)
    precondition(native.localSnapshot(center.panel) != nil,
                 "The settings route remains an ordinary window that can be snapped and captured")
    center.navigate(to: .controls)
    await NativeWindows.pause(0.08)
    precondition(center.panel.windowNumber == number && center.quickSection == 2)
    precondition(native.localSnapshot(center.panel) == nil)
    preferences.setShowMenuBarIcon(false)
    center.panel.performClose(nil)
    precondition(!center.panel.isVisible && closes == 1)
    precondition(!shortcuts.enabled && !preferences.showMenuBarIcon)
    precondition(!ControlCenter.shouldToggleClosed(visible: center.panel.isVisible, active: NSApp.isActive, forceOpen: true))
    center.present(previousApplication: nil, screen: NSScreen.main, onboarding: false,
                   controls: { AnyView(Text("Reopened fixture")) }, settings: { _ in AnyView(Text("Settings fixture")) })
    precondition(center.panel.windowNumber == number && center.panel.isVisible,
                 "A hidden menu-bar icon and disabled shortcuts do not prevent reopening the same control center")
    print("PASS: one native window across controls/settings/back; settings stays snappable; quick controls excluded; close and hidden-icon reopen recover")
}
