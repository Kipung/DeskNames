import AppKit
import SwiftUI
import Darwin
import Carbon

struct Desktop: Identifiable, Equatable {
    let id: String
    let spaceID: UInt64
    let display: String
    let position: Int
    let number: Int
    let isCurrent: Bool
    let isFullScreen: Bool
}
struct Appearance: Codable, Equatable {
    var name: String
    var color: Int
}
let palette: [Color] = [.init(red:0.37,green:0.85,blue:0.73), .init(red:0.55,green:0.67,blue:1), .init(red:0.81,green:0.64,blue:1), .init(red:1,green:0.72,blue:0.43), .init(red:1,green:0.55,blue:0.65)]
let icons = ["briefcase", "sparkle.magnifyingglass", "curlybraces", "sun.max", "leaf"]

final class SpaceReader {
    typealias Connection = @convention(c) () -> Int32
    typealias CopySpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?
    private let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW)
    private let snapshot: (() -> [Desktop])?
    init(snapshot: (() -> [Desktop])? = nil) { self.snapshot = snapshot }
    func read() -> [Desktop] {
        if let snapshot { return snapshot() }
        guard let handle, let cp = dlsym(handle,"CGSMainConnectionID"), let sp = dlsym(handle,"CGSCopyManagedDisplaySpaces") else { return [] }
        let connection = unsafeBitCast(cp,to:Connection.self)()
        guard let raw = unsafeBitCast(sp,to:CopySpaces.self)(connection)?.takeRetainedValue() as? [[String:Any]] else { return [] }
        return Self.desktops(in: raw, screenIDs: NSScreen.screens.map(screenUUID))
    }
    static func desktops(in raw: [[String: Any]], screenIDs: [String]) -> [Desktop] {
        var result: [Desktop] = []; var number = 0
        for display in raw {
            let nativeDisplayID = display["Display Identifier"] as? String ?? "Main"
            let displayID = nativeDisplayID == "Main" && raw.count == 1 && screenIDs.count == 1
                ? screenIDs[0] : nativeDisplayID
            let current = (display["Current Space"] as? [String:Any])?["ManagedSpaceID"] as? NSNumber
            let spaces = display["Spaces"] as? [[String: Any]] ?? []
            let unnamedOrdinary = spaces.filter {
                ($0["type"] as? Int ?? 0) == 0 && ($0["uuid"] == nil || ($0["uuid"] as? String) == "")
            }
            let uniqueDisplay = raw.filter { ($0["Display Identifier"] as? String ?? "Main") == nativeDisplayID }.count == 1
            for (position,item) in spaces.enumerated() {
                guard let id = item["ManagedSpaceID"] as? NSNumber else { continue }
                let fullscreen = (item["type"] as? Int ?? 0) != 0
                let uuid: String
                if let value = item["uuid"] as? String, !value.isEmpty { uuid = value }
                else if (item["uuid"] == nil || (item["uuid"] as? String) == ""),
                        !fullscreen, unnamedOrdinary.count == 1, uniqueDisplay {
                    // The primary desktop can lack a UUID even after other desktops are added.
                    uuid = "desknames:primary:\(displayID)"
                } else { continue }
                number += 1
                result.append(Desktop(id:uuid,spaceID:id.uint64Value,display:displayID,position:position,number:number,isCurrent:id==current,isFullScreen:fullscreen))
            }
        }
        return result
    }
}

final class Store: ObservableObject {
    @Published var desktops: [Desktop] = []
    @Published var appearance: [String:Appearance] = [:]
    @Published var enabled = true { didSet { defaults.set(enabled,forKey:"labelsEnabled") } }
    @Published var vertical: Double = 0 { didSet { if !(-100...100).contains(vertical) { vertical=min(max(vertical.isFinite ? vertical : 0,-100),100) }; defaults.set(vertical,forKey:"vertical") } }
    @Published var horizontal: Double = 0 { didSet { if !(-600...600).contains(horizontal) { horizontal=min(max(horizontal.isFinite ? horizontal : 0,-600),600) }; defaults.set(horizontal,forKey:"horizontal") } }
    @Published var spacing: Double = 1 { didSet { if !(0.3...1.5).contains(spacing) { spacing=min(max(spacing.isFinite ? spacing : 1,0.3),1.5) }; defaults.set(spacing,forKey:"spacing") } }
    @Published var missionControl = false
    @Published var accessibilityGranted = AXIsProcessTrusted()
    let defaults: UserDefaults
    let reader: SpaceReader
    var onChange: (() -> Void)?
    init(defaults: UserDefaults = RuntimeStorage.current.defaults, reader: SpaceReader = SpaceReader()) {
        self.defaults = defaults
        self.reader = reader
        if let data = defaults.data(forKey:"desktopAppearance"), let saved = try? JSONDecoder().decode([String:Appearance].self,from:data) { appearance = saved }
        enabled = defaults.object(forKey:"labelsEnabled") as? Bool ?? true
        vertical = defaults.double(forKey:"vertical")
        horizontal = defaults.double(forKey:"horizontal")
        spacing = defaults.object(forKey:"spacing") as? Double ?? 1
        refresh()
    }
    func refresh() {
        let next = reader.read()
        if desktops != next { desktops = next; onChange?() }
    }
    func style(_ d:Desktop) -> Appearance {
        let legacy = PrimaryDesktopCompatibility.usesLegacyAppearance(d, in: desktops) ? appearance[""] : nil
        var value=appearance[d.id] ?? legacy ?? Appearance(name:d.isFullScreen ? "Full screen" : "Desktop \(d.number)",color:(d.number-1)%palette.count)
        // Saved preferences may hold a color index outside the palette; never index out of range.
        value.color=max(0,min(value.color,palette.count-1))
        return value
    }
    func name(_ d:Desktop) -> String { let n=style(d).name.trimmingCharacters(in:.whitespacesAndNewlines); return n.isEmpty ? "Desktop \(d.number)" : n }
    func update(_ d:Desktop,name:String?=nil,color:Int?=nil) {
        var value=style(d)
        if let name { value.name=String(name.prefix(40)) }
        if let color { value.color=max(0,min(color,palette.count-1)) }
        appearance[d.id]=value
        if let data=try? JSONEncoder().encode(appearance) { defaults.set(data,forKey:"desktopAppearance") }
        onChange?()
    }
}

struct NamePill: View {
    let number:Int; let name:String; let color:Color; let current:Bool
    var body: some View {
        HStack(spacing:8) {
            Text(String(format:"%02d",number)).font(.system(size:11,weight:.bold,design:.monospaced)).foregroundStyle(color)
            Text(name).font(.system(size:13,weight:.semibold)).lineLimit(1)
            if current { Circle().fill(color).frame(width:5,height:5) }
        }.padding(.horizontal,13).padding(.vertical,8)
        .background(Color(red:0.09,green:0.12,blue:0.15),in:Capsule())
        .overlay(Capsule().strokeBorder(color.opacity(current ? 0.9 : 0.4),lineWidth:1))
        .foregroundStyle(.white)
    }
}

final class LabelPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
@MainActor final class OverlayController {
    let store: Store
    var panels: [String: LabelPanel] = [:]
    var rendered: [String: String] = [:]
    var widths: [String: Double] = [:]
    private let queue = DispatchQueue(label: "local.desknames.mission-control", qos: .userInitiated)
    private let reader = MissionControlReader()
    private let diagnostics = AlignmentDiagnostics()
    private var inFlight = false
    private var epoch: UInt64 = 0
    private var generation: MissionControlGeneration?
    private var stability = MissionControlStability()
    private var visibleSampleTime: TimeInterval = 0

    init(_ store: Store) { self.store = store }

    static func isMissionControlOpen() -> Bool {
        let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, 0) as? [[String: Any]] ?? []
        return windows.contains { window in
            let owner = window[kCGWindowOwnerName as String] as? String ?? ""
            let layer = window[kCGWindowLayer as String] as? Int ?? 0
            return (owner == "Dock" && layer == 18) || (owner == "WindowManager" && layer == 19)
        }
    }

    private func currentGeneration() -> MissionControlGeneration? {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return nil }
        let screens = MissionControlScreen.current()
        guard !screens.isEmpty else { return nil }
        return MissionControlGeneration(dockPID: dock.processIdentifier, screens: screens, slots: MissionControlSlot.snapshot(store.desktops))
    }

    func tick() {
        let open = Self.isMissionControlOpen()
        if store.missionControl != open { store.missionControl = open }
        let trusted = AXIsProcessTrusted()
        if store.accessibilityGranted != trusted { store.accessibilityGranted = trusted }
        guard open, store.enabled, trusted, let current = currentGeneration() else {
            invalidate()
            if store.defaults.bool(forKey: "alignmentDiagnosticsEnabled") {
                diagnostics.record(enabled: true, open: open, labelsEnabled: store.enabled, trusted: trusted, generation: currentGeneration(), capture: nil, placements: [], panels: panels)
            }
            return
        }
        if generation != current {
            invalidate()
            generation = current
        }
        let now = ProcessInfo.processInfo.systemUptime
        if now - visibleSampleTime > MissionControlStability.maximumAge {
            reconcile([])
        }
        guard !inFlight else { return }
        inFlight = true
        let requestEpoch = epoch
        let reader = self.reader
        queue.async { [weak self] in
            let capture = reader.capture(current)
            DispatchQueue.main.async {
                guard let self else { return }
                self.inFlight = false
                guard requestEpoch == self.epoch else { return }
                self.store.refresh()
                let stillOpen = Self.isMissionControlOpen()
                let trusted = AXIsProcessTrusted()
                let latest = self.currentGeneration()
                guard stillOpen, self.store.enabled, trusted, latest == current, capture.orderMatches else {
                    self.invalidate()
                    self.diagnostics.record(enabled: self.store.defaults.bool(forKey: "alignmentDiagnosticsEnabled"), open: stillOpen, labelsEnabled: self.store.enabled, trusted: trusted, generation: latest, capture: capture, placements: [], panels: self.panels)
                    return
                }
                let candidates = MissionControlGeometry.placements(strips: capture.strips, generation: current)
                let accepted = self.stability.accept(candidates, generation: current, current: latest, sampledAt: capture.sampledAt, now: ProcessInfo.processInfo.systemUptime)
                self.reconcile(accepted)
                self.visibleSampleTime = accepted.isEmpty ? 0 : capture.sampledAt
                self.diagnostics.record(enabled: self.store.defaults.bool(forKey: "alignmentDiagnosticsEnabled"), open: stillOpen, labelsEnabled: self.store.enabled, trusted: trusted, generation: latest, capture: capture, placements: accepted, panels: self.panels)
            }
        }
    }

    private func invalidate() {
        epoch &+= 1
        generation = nil
        stability.reset()
        visibleSampleTime = 0
        reconcile([])
    }

    private func reconcile(_ placements: [MissionControlPlacement]) {
        let visible = Set(placements.map(\.desktopID))
        for (id, panel) in panels where panel.isVisible && !visible.contains(id) { panel.orderOut(nil) }
        for placement in placements {
            guard let desktop = store.desktops.first(where: { $0.id == placement.desktopID && !$0.isFullScreen }) else { continue }
            let style = store.style(desktop)
            let signature = "\(desktop.number)|\(store.name(desktop))|\(style.color)|\(desktop.isCurrent)"
            let panel: LabelPanel
            if let existing = panels[desktop.id] { panel = existing } else {
                panel = LabelPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                panel.isOpaque = false
                panel.backgroundColor = .clear
                panel.hasShadow = false
                panel.ignoresMouseEvents = true
                panel.level = .screenSaver
                panel.hidesOnDeactivate = false
                panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
                panels[desktop.id] = panel
            }
            if rendered[desktop.id] != signature {
                let view = NSHostingView(rootView: NamePill(number: desktop.number, name: store.name(desktop), color: palette[style.color], current: desktop.isCurrent))
                panel.contentView = view
                rendered[desktop.id] = signature
                widths[desktop.id] = view.fittingSize.width
            }
            panel.setFrame(placement.labelFrame(fittingWidth: widths[desktop.id] ?? 120), display: true)
            panel.orderFrontRegardless()
        }
        let live = Set(store.desktops.filter { !$0.isFullScreen }.map(\.id))
        for key in Array(panels.keys) where !live.contains(key) {
            panels.removeValue(forKey: key)?.close()
            rendered.removeValue(forKey: key)
            widths.removeValue(forKey: key)
        }
    }
}

@MainActor final class AppDelegate:NSObject,NSApplicationDelegate {
    let onboarding = FirstRunPreferences(defaults: RuntimeStorage.current.defaults, domainName: RuntimeStorage.current.preferencesDomainName)
    let store=Store()
    var item:NSStatusItem!
    var overlay:OverlayController!
    var timer:Timer?
    private var lastDesktopRefresh: TimeInterval = 0
    private var spaceObserver: NSObjectProtocol?
    var workspace:LayoutController!
    var hotkeys:HotKeys?
    var smartPanes:SmartPaneController!
    var linkedPanes:LinkedPaneController!
    let shortcuts=ShortcutSettings()
    let updater = AppUpdater(enabled: !RuntimeStorage.current.isIsolated)
    let loginItem = LoginItemController()
    let general = GeneralPreferences()
    lazy var controlCenter = ControlCenter()
    var switcher: NSWindow { controlCenter.panel }
    private var switcherTask: Task<Void, Never>?
    func applicationDidFinishLaunching(_ notification:Notification) {
        NSApp.setActivationPolicy(.accessory)
        let menu=NSMenu(); let appMenuItem=NSMenuItem(); let appMenu=NSMenu()
        let settingsItem = appMenu.addItem(withTitle: "Settings…", action: #selector(settingsFromMenu), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(withTitle:"Quit DeskNames",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q")
        appMenuItem.submenu=appMenu;menu.addItem(appMenuItem);NSApp.mainMenu=menu
        item=NSStatusBar.system.statusItem(withLength:NSStatusItem.variableLength)
        item.button?.image=NSImage(systemSymbolName:"rectangle.3.group",accessibilityDescription:"DeskNames")
        item.button?.imagePosition = .imageLeading
        item.button?.target=self;item.button?.action=#selector(statusItemClicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        general.onChange = { [weak self] in self?.updateStatus() }
        controlCenter.onClose = { [weak self] in self?.cancelShortcutRecording() }
        controlCenter.willNavigate = { [weak self] in self?.cancelShortcutRecording() }
        overlay=OverlayController(store)
        PreferenceMigrations.migratePaneSpacing(in: store.defaults)
        workspace=LayoutController(store:store)
        smartPanes=SmartPaneController(workspace:workspace)
        smartPanes.start()
        linkedPanes = LinkedPaneController(workspace: workspace)
        workspace.showSwitcher = { [weak self] in self?.controlCenter.navigate(to: .controls) }
        workspace.onSwitch = { [weak self] in self?.controlCenter.dismiss(restoreFocus: false) }
        hotkeys=HotKeys { [weak self] id in MainActor.assumeIsolated {self?.shortcut(id)} }
        hotkeys?.modifiersChanged = { [weak self] modifiers in
            MainActor.assumeIsolated { self?.workspace.paneRangeChord.modifiersChanged(modifiers) }
        }
        hotkeys?.chordInterrupted = { [weak self] in MainActor.assumeIsolated { self?.workspace.paneRangeChord.reset() } }
        shortcuts.onChange = { [weak self] enabled,bindings in
            guard let self else{return ""}
            let result=self.hotkeys?.apply(enabled:enabled,bindings:bindings) ?? ""
            self.shortcuts.unavailable=self.hotkeys?.unavailable ?? []
            self.refreshShortcutStatus()
            return result
        }
        shortcuts.onConflictCheck = { [weak self] bindings in
            self?.hotkeys?.checkConflicts(bindings) ?? ShortcutConflictReport(checkedCount: bindings.count, issues: [], systemCheckError: OSStatus(unimpErr))
        }
        shortcuts.apply()
        updater.start()
        store.onChange = { [weak self] in self?.updateStatus() }
        updateStatus()
        timer=Timer(timeInterval:0.2,repeats:true) { [weak self] _ in DispatchQueue.main.async {guard let self else { return };let now=ProcessInfo.processInfo.systemUptime;if self.store.missionControl || now-self.lastDesktopRefresh>=1 {self.store.refresh();self.lastDesktopRefresh=now};self.overlay.tick();self.workspace.tick();self.hotkeys?.refreshChordMonitors(trusted:self.workspace.trusted);self.refreshShortcutStatus();self.smartPanes.tick();self.linkedPanes.tick()} }
        timer?.tolerance=0.04
        RunLoop.main.add(timer!,forMode:.common)
        spaceObserver=NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.activeSpaceDidChangeNotification,object:nil,queue:.main) { [weak self] _ in
            MainActor.assumeIsolated { self?.workspace.paneRangeChord.reset();self?.store.refresh();self?.workspace.tick() }
        }
        if onboarding.isPresented {
            if workspace.layouts.isEmpty {
                DispatchQueue.main.async { [weak self] in self?.showSwitcher() }
            } else { onboarding.finish() }
        }
        if !general.showMenuBarIcon && !ControlCenter.isBackgroundLaunch(NSAppleEventManager.shared().currentAppleEvent) {
            DispatchQueue.main.async { [weak self] in self?.presentSwitcher(forceOpen: true) }
        }
    }
    private func refreshShortcutStatus() {
        let secureInput = IsSecureEventInputEnabled()
        let changed = shortcuts.updateAvailability(secureInput: secureInput)
        guard changed || RuntimeStorage.current.isIsolated else { return }
        workspace.native.recordWindowDiagnostic("hotkey-status.json", [
            "uptime": ProcessInfo.processInfo.systemUptime,
            "busy": workspace.busy,
            "userDrag": workspace.hasUserWindowDrag,
            "panelVisible": switcher.isVisible,
            "panelKey": switcher.isKeyWindow,
            "enabled": shortcuts.enabled,
            "recordingAction": shortcuts.recordingAction.map { $0 as Any } ?? NSNull(),
            "registeredCount": hotkeys?.registeredCount ?? 0,
            "secureInput": secureInput,
            "lastSequence": shortcuts.delivery.sequence,
            "cause": shortcuts.availability.cause,
            "status": shortcuts.availability.message
        ])
    }
    func shortcut(_ id:UInt32) {
        smartPanes?.prepareForShortcut(mouseDown: CGEventSource.buttonState(.combinedSessionState, button: .left))
        if !(320...323).contains(id) { workspace.paneRangeChord.reset() }
        let request = shortcuts.receive(id)
        let receivedUptime = ProcessInfo.processInfo.systemUptime
        let report: (String) -> Void = { [weak self] result in
            guard let self, self.shortcuts.complete(request, result: result) else { return }
            self.workspace.shortcutStatus = self.shortcuts.delivery.action + ": " + result
            let detail: [String: Any] = [
                "actionID": id, "action": self.shortcuts.delivery.action, "result": result,
                "sequence": request, "receivedUptime": receivedUptime,
                "updatedUptime": ProcessInfo.processInfo.systemUptime, "busy": self.workspace.busy,
                "updatedAt": ISO8601DateFormatter().string(from: Date())
            ]
            self.workspace.native.recordWindowDiagnostic("shortcut-result.json", detail)
            if RuntimeStorage.current.isIsolated, let data = try? JSONSerialization.data(withJSONObject: detail, options: [.sortedKeys]) {
                let file = RuntimeStorage.current.supportDirectory.appendingPathComponent("hotkey-events.jsonl")
                if !FileManager.default.fileExists(atPath: file.path) { FileManager.default.createFile(atPath: file.path, contents: nil) }
                if let handle = try? FileHandle(forWritingTo: file) {
                    defer { try? handle.close() }
                    try? handle.seekToEnd()
                    try? handle.write(contentsOf: data + Data([0x0A]))
                }
            }
        }
        report("Received.")
        guard let action = ShortcutAction.all.first(where: { $0.id == id }) else { report("Unknown shortcut action."); return }
        if let refusal = action.refusal(trusted: workspace.native.trusted, busy: workspace.busy) { report(refusal.message); return }
        if id == 100 { presentSwitcher(result: report); return }
        workspace.shortcutResult = report
        defer { workspace.shortcutResult = nil }
        if !workspace.busy { workspace.message = "Received." }
        if let windowAction=WindowAction.allCases.first(where:{$0.id==id}) {
            workspace.performWindowAction(windowAction,focused:true); report(workspace.message); return
        }
        if PaneShortcut.all.contains(where: { $0.id == id }) { workspace.performPaneShortcut(id, modifiers: shortcuts.bindings[id]?.modifiers ?? 0); report(workspace.message); return }
        store.refresh()
        if id<100 {
            guard let d=store.desktops.first(where:{$0.number==Int(id)}) else {report("Desktop \(id) does not exist. Create it in Mission Control first.");return}
            workspace.switchTo(d)
            report(workspace.message)
            return
        }
        report("Finding the focused window…")
        let focusedPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        Task { @MainActor [weak self] in
            guard let self else { return }
            let candidate = await self.workspace.native.focusedWindowForOperation()
            guard self.shortcuts.delivery.sequence == request else { return }
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == focusedPID else {
                report("The focused app changed. Try this shortcut again."); return
            }
            let desktop = self.workspace.native.activeDesktop(reader: self.store.reader, focusedWindow: candidate)
            if let refusal = action.refusal(trusted: self.workspace.native.trusted, busy: self.workspace.busy,
                                            hasWindow: candidate != nil, hasDesktop: desktop != nil,
                                            hasLayout: desktop.map { self.workspace.layouts[$0.id] != nil }) {
                report(refusal.message); return
            }
            self.workspace.shortcutResult = report
            defer { self.workspace.shortcutResult = nil }
            if id == ShortcutAction.pin.id {
                self.workspace.togglePin(candidate)
            } else if let desktop {
                self.workspace.targetDesktop = desktop.id
                if id == 101 { self.workspace.save(desktop) }
                if id == 102 { self.workspace.selectedLayoutID = ""; self.workspace.restore() }
            }
            report(self.workspace.message)
        }
    }
    @objc func showSwitcher() {
        presentSwitcher()
    }
    private func presentSwitcher(result: ((String) -> Void)? = nil, forceOpen: Bool = false, page: SettingsPage? = nil) {
        if let switcherTask {
            switcherTask.cancel(); self.switcherTask = nil
            if !forceOpen { result?("Control panel opening cancelled."); return }
        }
        if ControlCenter.shouldToggleClosed(visible: switcher.isVisible, active: NSApp.isActive, forceOpen: forceOpen) {closeSwitcher();result?("Control panel closed.");return}
        let previous = NSWorkspace.shared.frontmostApplication
        result?("Opening control panel…")
        switcherTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let candidate = await self.workspace.native.focusedWindowForOperation()
            guard !Task.isCancelled else { return }
            self.switcherTask = nil
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == previous?.processIdentifier else {
                result?("Focus changed before the control panel opened. Try again."); return
            }
            self.openSwitcher(previous: previous, candidate: candidate, page: page)
            result?("Control panel opened.")
        }
    }
    private func openSwitcher(previous: NSRunningApplication?, candidate: LiveWindow?, page: SettingsPage? = nil) {
        store.refresh()
        let desktop = workspace.native.activeDesktop(reader: store.reader, focusedWindow: candidate)
        let pinCandidate = previous?.processIdentifier == getpid() ? nil : candidate
        let screen = NSScreen.screens.first { screenUUID($0) == desktop?.display }
        controlCenter.present(previousApplication: previous, screen: screen, onboarding: onboarding.isPresented,
                              route: page.map(ControlCenterRoute.settings) ?? .controls,
            controls: { [weak self] in
                guard let self else { return AnyView(EmptyView()) }
                let content = SwitcherView(store:self.store,workspace:self.workspace,preferences:self.workspace.panes,models:self.workspace.monitorPresets,
                    desktop:desktop,pinCandidate:pinCandidate,
                    choose:{ [weak self] d in self?.workspace.switchTo(d) },
                    close:{ [weak self] in self?.closeSwitcher() },
                    openSettings:{ [weak self] page in self?.showWindow(page) },
                    section:self.controlCenter.quickSection,sectionChanged:{ [weak self] section in self?.controlCenter.quickSection = section })
                return AnyView(FirstRunPanel(onboarding:self.onboarding,store:self.store,workspace:self.workspace,shortcuts:self.shortcuts,
                    loginItem:self.loginItem,desktop:desktop,close:{ [weak self] in self?.closeSwitcher() },
                    openShortcutSettings:{ [weak self] in self?.showWindow(.shortcuts) }) {
                    VStack(alignment: .leading, spacing: 8) {
                        ShortcutAvailabilityView(settings: self.shortcuts)
                        content
                    }
                })
            }, settings: { [weak self] page in
                guard let self else { return AnyView(EmptyView()) }
                return AnyView(MainView(store:self.store,workspace:self.workspace,shortcuts:self.shortcuts,page:page,
                    general:self.general,loginItem:self.loginItem,updater:self.updater,
                    back:{ [weak self] in self?.controlCenter.navigate(to: .controls) },
                    close:{ [weak self] in self?.closeSwitcher() }))
            })
        updateStatus()
    }
    private func closeSwitcher() { controlCenter.dismiss() }
    private func cancelShortcutRecording() {
        if let id = shortcuts.recordingAction { shortcuts.cancelRecording(id) }
    }
    func updateStatus() {
        item?.isVisible = general.showMenuBarIcon
        item?.button?.title = general.showDesktopNames ? "  " + store.desktops.filter(\.isCurrent).map { store.name($0) }.joined(separator: " · ") : ""
        controlCenter.panel.hidesOnDeactivate = general.hideWhenInactive
    }
    private func showWindow(_ page: SettingsPage? = nil) {
        controlCenter.navigate(to: .settings(page ?? .general))
    }
    @objc private func statusItemClicked() {
        guard NSApp.currentEvent?.type == .rightMouseUp, let button = item?.button else { showSwitcher(); return }
        let menu = NSMenu()
        let open = menu.addItem(withTitle: "Open DeskNames", action: #selector(openFromMenu), keyEquivalent: "")
        open.target = self
        let settings = menu.addItem(withTitle: "Settings", action: #selector(settingsFromMenu), keyEquivalent: "")
        settings.target = self
        menu.addItem(.separator())
        let names = menu.addItem(withTitle: "Show desktop names", action: #selector(toggleDesktopNames), keyEquivalent: "")
        names.target = self; names.state = general.showDesktopNames ? .on : .off
        let hide = menu.addItem(withTitle: "Hide menu-bar icon", action: #selector(hideMenuBarIcon), keyEquivalent: "")
        hide.target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit DeskNames", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.popUp(positioning: nil, at: CGPoint(x: 0, y: button.bounds.minY), in: button)
    }
    @objc private func openFromMenu() { presentSwitcher(forceOpen: true) }
    @objc private func settingsFromMenu() {
        if switcher.isVisible && switcher.isKeyWindow { showWindow(.general) }
        else { presentSwitcher(forceOpen: true, page: .general) }
    }
    @objc private func toggleDesktopNames() { general.setShowDesktopNames(!general.showDesktopNames) }
    @objc private func hideMenuBarIcon() { general.setShowMenuBarIcon(false) }
    func applicationWillTerminate(_ notification:Notification) { switcherTask?.cancel();smartPanes?.stop();linkedPanes?.stop();timer?.invalidate();if let spaceObserver {NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver)} }
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows flag:Bool)->Bool {
        presentSwitcher(forceOpen: true)
        return false
    }
}

var storageArguments = CommandLine.arguments
if storageArguments.contains(where: { $0.hasPrefix("--hotkey-soak-") }) && !storageArguments.contains("--storage") {
    storageArguments += ["--storage", FileManager.default.temporaryDirectory.appendingPathComponent("desknames-hotkey-helper-\(UUID().uuidString)").path]
}
try RuntimeStorage.configure(arguments: storageArguments)

try MainActor.assumeIsolated {
if CommandLine.arguments.contains("--self-test") {
    NSApplication.shared.setActivationPolicy(.prohibited)
    Task { @MainActor in
        do {
            runControlCenterTests()
            runShortcutConflictTests()
            try runStorageTests()
            try runFirstRunTests()
            try runWorkspaceTests()
            runDesktopNavigationTests()
            try runScreenLayoutTests()
            runWindowRoutingTests()
            runShortcutTests()
            runShortcutDeliveryTests()
            runShortcutAvailabilityTests()
            runHotkeyInputTests()
            runGeometryTests()
            runPaneTests()
            runWindowActionTests()
            try runPaneInteractionTests()
            runMovementTests()
            try await runOperationRecoveryTests()
            await runAccessibilityRecoveryTests()
            try await runApplicationLaunchTests()
            let testDomain="local.desknames.test.\(UUID().uuidString)"
            let d=UserDefaults(suiteName:testDomain)!
            defer {d.removePersistentDomain(forName:testDomain)}
            let s=Store(defaults:d)
            let a=Desktop(id:"stable-id",spaceID:1,display:"test",position:0,number:1,isCurrent:true,isFullScreen:false)
            s.update(a,name:"Research",color:2)
            let moved=Desktop(id:"stable-id",spaceID:99,display:"test2",position:3,number:4,isCurrent:false,isFullScreen:false)
            let restored=Store(defaults:d)
            precondition(restored.name(moved)=="Research" && restored.style(moved).color==2)
            restored.update(moved,name:"   "); precondition(restored.name(moved)=="Desktop 4")
            restored.update(moved,name:String(repeating:"x",count:80),color:999)
            precondition(restored.style(moved).name.count==40 && restored.style(moved).color==4)
            print("PASS: persistence, desktop reordering, empty names, length/color bounds; live desktops: \(s.desktops.count)")
        } catch { print("FAIL: \(error.localizedDescription)"); exit(1) }
        exit(0)
    }
    NSApplication.shared.run()
} else if CommandLine.arguments.contains("--control-center-test") {
    NSApplication.shared.setActivationPolicy(.accessory)
    Task { @MainActor in
        do { try await runControlCenterSessionTests(); exit(0) }
        catch { print("FAIL: \(error.localizedDescription)"); exit(1) }
    }
    NSApplication.shared.run()
} else if CommandLine.arguments.contains("--hotkey-soak-fixture") {
    let fixtureDelegate = HotkeyFixtureDelegate()
    NSApplication.shared.delegate = fixtureDelegate
    NSApplication.shared.run()
} else if let index = CommandLine.arguments.firstIndex(of: "--hotkey-soak-cleanup"), CommandLine.arguments.indices.contains(index+1) {
    NSApplication.shared.setActivationPolicy(.accessory)
    Task { @MainActor in
        let passed = await recoverHotkeySoak(at: URL(fileURLWithPath: CommandLine.arguments[index+1]))
        exit(passed ? 0 : 1)
    }
    NSApplication.shared.run()
} else if CommandLine.arguments.contains("--hotkey-soak-test") {
    NSApplication.shared.setActivationPolicy(.accessory)
    let helperDelegate = HotkeySoakDelegate()
    NSApplication.shared.delegate = helperDelegate
    Task { @MainActor in
        let passed = await runHotkeySoakTest(arguments: CommandLine.arguments)
        exit(passed ? 0 : 1)
    }
    NSApplication.shared.run()
} else if CommandLine.arguments.contains("--external-divider-test") {
    NSApplication.shared.setActivationPolicy(.accessory)
    Task { @MainActor in
        do { try await runExternalDividerTest(arguments: CommandLine.arguments); exit(0) }
        catch { print("FAIL: \(error.localizedDescription)"); exit(1) }
    }
    NSApplication.shared.run()
} else if CommandLine.arguments.contains("--external-placement-test") {
    NSApplication.shared.setActivationPolicy(.accessory)
    Task { @MainActor in
        do { let passed = try await runExternalPlacementTests(arguments: CommandLine.arguments); exit(passed ? 0 : 1) }
        catch { print("FAIL: \(error.localizedDescription)"); exit(1) }
    }
    NSApplication.shared.run()
} else if CommandLine.arguments.contains("--movement-session-test") {
    NSApplication.shared.setActivationPolicy(.accessory)
    Task { @MainActor in
        do { try await runMovementSessionTests(); exit(0) } catch { print("FAIL: \(error.localizedDescription)"); exit(1) }
    }
    NSApplication.shared.run()
} else if CommandLine.arguments.contains("--pane-interaction-test") {
    NSApplication.shared.setActivationPolicy(.accessory)
    Task { @MainActor in
        do { try await runPaneInteractionSessionTests(); exit(0) } catch { print("FAIL: \(error.localizedDescription)"); exit(1) }
    }
    NSApplication.shared.run()
} else if CommandLine.arguments.contains("--window-refresh-test") {
    NSApplication.shared.setActivationPolicy(.prohibited)
    Task { @MainActor in
        do {try await runWindowRefreshSessionTest();exit(0)} catch {print("FAIL: \(error.localizedDescription)");exit(1)}
    }
    NSApplication.shared.run()
} else if CommandLine.arguments.contains("--layout-session-test") {
    NSApplication.shared.setActivationPolicy(.accessory)
    Task { @MainActor in
        do {try await runLayoutSessionTest();exit(0)} catch {print("FAIL: \(error.localizedDescription)");exit(1)}
    }
    NSApplication.shared.run()
} else if CommandLine.arguments.contains("--pane-session-test") {
    let app=NSApplication.shared
    app.setActivationPolicy(.prohibited)
    Task { @MainActor in await runPaneSessionTests(); exit(0) }
    app.run()
} else if let index = CommandLine.arguments.firstIndex(of: "--render-marketing"), CommandLine.arguments.count > index+1 {
    NSApplication.shared.setActivationPolicy(.prohibited)
    try renderMarketing(to: URL(fileURLWithPath: CommandLine.arguments[index+1], isDirectory: true))
} else if let index=CommandLine.arguments.firstIndex(of:"--render-preview"),CommandLine.arguments.count>index+1 {
    let app=NSApplication.shared
    app.setActivationPolicy(.prohibited)
    let s=Store()
    func previewDimension(_ flag:String,_ fallback:Double)->Double {
        guard let i=CommandLine.arguments.firstIndex(of:flag),CommandLine.arguments.count>i+1,
              let value=Double(CommandLine.arguments[i+1]),value.isFinite,value>0,value<=5000 else{return fallback}
        return value
    }
    let host=NSHostingView(rootView:MainView(store:s,workspace:LayoutController(store:s),page:CommandLine.arguments.contains("--panes") ? .panes : CommandLine.arguments.contains("--layouts") ? .layouts : .desktops)); host.frame=NSRect(x:0,y:0,width:previewDimension("--preview-width",1020),height:previewDimension("--preview-height",820))
    let window=NSWindow(contentRect:host.frame,styleMask:.borderless,backing:.buffered,defer:false)
    window.appearance=NSAppearance(named:.darkAqua);window.contentView=host
    host.layoutSubtreeIfNeeded()
    if let rep=host.bitmapImageRepForCachingDisplay(in:host.bounds) {
        host.cacheDisplay(in:host.bounds,to:rep)
        try rep.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:CommandLine.arguments[index+1]))
    }
} else {
    let app=NSApplication.shared
    let delegate=AppDelegate();app.delegate=delegate
    app.run()
}

}
