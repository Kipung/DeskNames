import AppKit
import SwiftUI

private struct PaneScreen: Equatable {
    let id: String
    let panelFrame: CGRect
    let area: CGRect
    let bounds: CGRect
    let pixelScale: CGFloat
    let frameInterval: TimeInterval
    @MainActor static var current: [PaneScreen] {
        NSScreen.screens.map { PaneScreen(id: screenUUID($0), panelFrame: $0.visibleFrame, area: screenArea($0), bounds: CGRect(x:$0.frame.minX,y:(NSScreen.screens.first?.frame.maxY ?? 0)-$0.frame.maxY,width:$0.frame.width,height:$0.frame.height), pixelScale: $0.backingScaleFactor, frameInterval: 1.0/Double(($0.maximumFramesPerSecond > 0 ? $0.maximumFramesPerSecond : 60))) }
    }
}

private struct PanePresentation: Equatable {
    let screen: PaneScreen
    let desktopID: String
    let title: String
    let configuration: PaneConfiguration
    let geometry: PaneGeometry
    let hovered: Int?
    let previewOnly: Bool
    let edgeAction: WindowAction?
}

private final class PaneOverlayState: ObservableObject {
    @Published var presentation: PanePresentation?
}
private struct PaneOverlayHost: View {
    @ObservedObject var state: PaneOverlayState
    var body: some View {
        if let p=state.presentation {
            PaneOverlayView(geometry:p.geometry,hovered:p.hovered,title:p.title,previewOnly:p.previewOnly,edgeSnap:p.edgeAction != nil)
        }
    }
}

@MainActor final class SmartPaneController {
    private struct Session {
        let window: LiveWindow
        let screens: [PaneScreen]
        let desktops: [Desktop]
        var evidence: PaneMoveEvidence
        var presentation: PanePresentation?
        var missingMouseUpSince: TimeInterval?
        var diagnosticSamples = 0
    }
    private let workspace: LayoutController
    private var session: Session?
    private var deferredPointerWindow: LiveWindow?
    private var monitor: Any?
    private var localMonitor: Any?
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var panel: LabelPanel?
    private let overlayState = PaneOverlayState()
    private var overlayHost: NSHostingView<PaneOverlayHost>?
    private var presentation: PanePresentation?
    private var previewTask: Task<Void, Never>?
    private var placementInProgress = false
    private var started = false
    private var monitoringTrusted = false
    private var diagnosticEvents: [[String: Any]] = []
    private let diagnosticQueue = DispatchQueue(label: "local.desknames.pane-diagnostics")

    init(workspace: LayoutController) { self.workspace = workspace }

    func start() {
        guard !started else { return }
        started = true
        updateMonitors()
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.environmentChanged() }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.environmentChanged() }
        })
        workspace.panes.onChange = { [weak self] in self?.environmentChanged() }
        workspace.previewPanes = { [weak self] id in self?.preview(desktopID: id) }
    }

    private func updateMonitors() {
        let trusted = workspace.native.trusted
        guard trusted != monitoringTrusted else { return }
        monitoringTrusted = trusted
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        if let localMonitor { NSEvent.removeMonitor(localMonitor); self.localMonitor = nil }
        guard trusted else { environmentChanged(); return }
        let events: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseUp, .leftMouseDragged, .flagsChanged, .keyDown]
        monitor = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] event in
            MainActor.assumeIsolated { self?.receive(event) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
            MainActor.assumeIsolated { self?.receive(event) }
            return event
        }
        trace("monitor", ["trusted": trusted, "global": monitor != nil, "local": localMonitor != nil])
    }

    func stop() {
        environmentChanged()
        started = false; monitoringTrusted = false
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        if let localMonitor { NSEvent.removeMonitor(localMonitor); self.localMonitor = nil }
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observers.removeAll()
        workspace.panes.onChange = nil
        workspace.previewPanes = nil
    }

    func tick() {
        guard started else { return }
        updateMonitors()
        if workspace.store.missionControl { environmentChanged(); return }
        if (session != nil || placementInProgress) && (!workspace.native.trusted || !(workspace.panes.enabled || workspace.panes.edgeSnapping)) { environmentChanged() }
    }

    private func environmentChanged() {
        cancel()
        if placementInProgress { workspace.cancel() }
    }

    private func cancel() {
        if session != nil { trace("cancel") }
        session = nil
        deferredPointerWindow = nil
        timer?.invalidate(); timer = nil
        workspace.endUserWindowDrag()
        hide()
    }

    private func hide() {
        previewTask?.cancel(); previewTask = nil
        panel?.orderOut(nil)
        panel?.alphaValue = 1
        presentation = nil
        var transaction = Transaction(); transaction.disablesAnimations = true
        withTransaction(transaction) { overlayState.presentation = nil }
    }

    private func point(for event: NSEvent? = nil) -> CGPoint {
        if let cg = event?.cgEvent { return cg.location }
        let mouse = NSEvent.mouseLocation
        return CGPoint(x: mouse.x, y: (NSScreen.screens.first?.frame.maxY ?? 0) - mouse.y)
    }

    private func receive(_ event: NSEvent) {
        if event.type == .keyDown {
            if event.keyCode == 53 { environmentChanged() }
            return
        }
        if event.type == .leftMouseDown {
            cancel()
            trace("down", ["enabled": workspace.panes.enabled, "trusted": workspace.native.trusted, "busy": workspace.busy,
                            "missionControl": workspace.store.missionControl, "nativeMissionControl": OverlayController.isMissionControlOpen(),
                            "x": point(for: event).x, "y": point(for: event).y, "command": event.modifierFlags.contains(.command)])
            guard workspace.panes.enabled || workspace.panes.edgeSnapping, workspace.native.trusted,
                  !workspace.store.missionControl, !OverlayController.isMissionControlOpen() else { return }
            let location = point(for: event)
            guard let window = workspace.native.window(at: location, localWindow: event.window, onFailure: { trace("no-window", ["reason": $0]) }) else { return }
            trace("captured", ["windowID": window.id, "pid": window.pid, "frame": rectDictionary(window.frame),
                                "spaces": window.spaceIDs, "currentSpaces": workspace.store.desktops.filter(\.isCurrent).map(\.spaceID)])
            if workspace.busy {
                if workspace.canRetargetPlacement { deferredPointerWindow = window }
                return
            }
            admit(window, at: location, time: event.timestamp)
            return
        }
        if event.type == .leftMouseUp { deferredPointerWindow = nil; release(at: point(for: event), command: event.modifierFlags.contains(.command)); return }
        if event.type == .leftMouseDragged || (event.type == .flagsChanged && event.modifierFlags.contains(.command)) {
            if event.type == .leftMouseDragged, !workspace.busy, let candidate = deferredPointerWindow {
                deferredPointerWindow = nil
                if let frame = workspace.native.currentFrame(candidate) {
                    let current = LiveWindow(id: candidate.id, target: candidate.target, pid: candidate.pid, bundleID: candidate.bundleID,
                                             appName: candidate.appName, title: candidate.title, frame: frame,
                                             spaceIDs: workspace.native.spaces(for: candidate.id), minimized: false)
                    admit(current, at: point(for: event), time: event.timestamp)
                }
            }
            updatePresentation(at: point(for: event), command: event.modifierFlags.contains(.command))
            return
        }
        if event.type == .flagsChanged, !event.modifierFlags.contains(.command) {
            session?.presentation = nil
            hide()
        }
    }

    private func admit(_ window: LiveWindow, at location: CGPoint, time: TimeInterval) {
        guard workspace.store.desktops.contains(where: { $0.isCurrent && !$0.isFullScreen && window.spaceIDs.contains($0.spaceID) }),
              workspace.beginUserWindowDrag() else { trace("admission-refused"); return }
        let screens = PaneScreen.current
        session = Session(window: window, screens: screens, desktops: workspace.store.desktops,
                          evidence: PaneMoveEvidence(initialFrame: window.frame, initialPointer: location, time: time))
        let timer = Timer(timeInterval: screens.first(where: { $0.area.contains(location) })?.frameInterval ?? 1.0/60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func updatePresentation(at location: CGPoint, command: Bool) {
        guard var current = session, current.evidence.moved,
              workspace.hasUserWindowDrag, current.desktops == workspace.store.desktops else { return }
        current.presentation = dragPresentation(at: location, screens: current.screens, command: command)
        if let next = current.presentation { show(next) } else { hide() }
        session = current
    }

    private func sample() {
        guard var current = session else { return }
        guard workspace.hasUserWindowDrag, workspace.native.trusted, workspace.panes.enabled || workspace.panes.edgeSnapping,
              !workspace.store.missionControl, current.desktops == workspace.store.desktops,
              current.screens == PaneScreen.current else { trace("environment-changed"); cancel(); return }
        if NSEvent.pressedMouseButtons & 1 == 0 {
            if case .local = current.window.target {
                release(at: point(), command: NSEvent.modifierFlags.contains(.command))
                return
            }
            let now = ProcessInfo.processInfo.systemUptime
            if let since = current.missingMouseUpSince, now - since > 0.15 { cancel(); return }
            current.missingMouseUpSince = current.missingMouseUpSince ?? now
            session = current
            return
        }
        current.missingMouseUpSince = nil
        let location = point()
        guard let frame = workspace.native.currentFrame(current.window) else { cancel(); return }
        current.evidence.observe(frame: frame, pointer: location, time: ProcessInfo.processInfo.systemUptime)
        if current.diagnosticSamples < 8 {
            trace("sample", ["frame": rectDictionary(frame), "x": location.x, "y": location.y,
                              "command": NSEvent.modifierFlags.contains(.command), "confirmations": current.evidence.confirmations,
                              "rejected": current.evidence.rejected])
            current.diagnosticSamples += 1
        }
        guard !current.evidence.rejected else { cancel(); return }
        if current.evidence.moved, let next = dragPresentation(at:location,screens:current.screens,command:NSEvent.modifierFlags.contains(.command)) {
            current.presentation = next
            if presentation == nil { trace("show", ["preset": next.configuration.preset.rawValue, "desktopID": next.desktopID, "cells": next.geometry.cells.map(rectDictionary)]) }
            show(next)
        } else {
            current.presentation = nil
            hide()
        }
        session = current
    }

    private func release(at location: CGPoint, command: Bool) {
        guard let current = session else { return }
        trace("up", ["moved": current.evidence.moved, "command": command,
                      "hasPreview": current.presentation != nil, "hovered": current.presentation?.hovered ?? -1])
        session = nil
        timer?.invalidate(); timer = nil
        hide()
        guard current.evidence.moved, workspace.native.trusted,
              current.desktops == workspace.store.desktops, current.screens == PaneScreen.current,
              current.presentation != nil,
              let shown = dragPresentation(at: location, screens: current.screens, command: command), let index = shown.hovered,
              shown.geometry.cells.indices.contains(index),
              (shown.edgeAction == nil ? command && workspace.panes.enabled && shown.geometry.cells[index].contains(location) : !command && workspace.panes.edgeSnapping && WindowAction.edge(at:location,bounds:shown.screen.bounds)==shown.edgeAction),
              workspace.paneConfiguration(for: shown.desktopID) == shown.configuration,
              let frame = workspace.native.currentFrame(current.window),
              abs(frame.width - current.evidence.latestFrame.width) <= 2,
              abs(frame.height - current.evidence.latestFrame.height) <= 2 else {
            workspace.endUserWindowDrag()
            return
        }
        placementInProgress = true
        let target = shown.geometry.cells[index]
        let live = LiveWindow(id: current.window.id, target: current.window.target, pid: current.window.pid,
                              bundleID: current.window.bundleID, appName: current.window.appName, title: current.window.title,
                              frame: frame, spaceIDs: current.window.spaceIDs, minimized: false)
        workspace.finishUserWindowDrag(live, frame: target, displayID: shown.screen.id, desktopID: shown.desktopID, originalFrame:current.window.frame) { [weak self] text, success in
            guard let self else { return }
            self.placementInProgress = false
            self.recordPlacement(window: current.window, target: target, success: success)
            self.showResult(text, success: success, on: shown.screen)
        }
    }

    private func dragPresentation(at point: CGPoint, screens: [PaneScreen], command: Bool) -> PanePresentation? {
        if command { return workspace.panes.enabled ? makePresentation(at:point,screens:screens,previewOnly:false) : nil }
        guard workspace.panes.edgeSnapping, let screen=screens.first(where:{$0.bounds.contains(point)}),
              let action=WindowAction.edge(at:point,bounds:screen.bounds),let desktop=desktop(on:screen),
              let frame=action.frame(in:screen.area,current:screen.area,configuration:workspace.paneConfiguration(for:desktop.id),pixelScale:screen.pixelScale) else { return nil }
        return PanePresentation(screen:screen,desktopID:desktop.id,title:action.name,configuration:workspace.paneConfiguration(for:desktop.id),geometry:PaneGeometry(area:screen.area,cells:[frame]),hovered:0,previewOnly:false,edgeAction:action)
    }

    private func desktop(on screen: PaneScreen) -> Desktop? {
        workspace.store.desktops.first { $0.isCurrent && !$0.isFullScreen && ($0.display == screen.id || ($0.display == "Main" && NSScreen.screens.count == 1)) }
    }

    private func makePresentation(at point: CGPoint, screens: [PaneScreen], previewOnly: Bool) -> PanePresentation? {
        guard let screen = screens.first(where: { $0.area.contains(point) }), let desktop = desktop(on: screen) else { return nil }
        let config = workspace.paneConfiguration(for: desktop.id)
        let geometry = PaneGeometry(area: screen.area, configuration: config, pixelScale: screen.pixelScale)
        guard !geometry.cells.isEmpty else { return nil }
        return PanePresentation(screen: screen, desktopID: desktop.id,
                                title: workspace.store.name(desktop) + " · " + config.preset.name,
                                configuration: config, geometry: geometry,
                                hovered: previewOnly ? nil : geometry.hit(point), previewOnly: previewOnly,edgeAction:nil)
    }

    private func preview(desktopID: String) {
        guard !workspace.busy else { return }
        cancel()
        let screens = PaneScreen.current
        guard let screen = screens.first(where: { desktop(on: $0)?.id == desktopID }),
              let next = makePresentation(at: CGPoint(x: screen.area.midX, y: screen.area.midY), screens: screens, previewOnly: true) else {
            workspace.message = "Switch to this desktop to preview its panes."
            return
        }
        show(next)
        previewTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    private func overlayPanel() -> LabelPanel {
        if let panel { return panel }
        let panel = LabelPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.ignoresMouseEvents = true; panel.hidesOnDeactivate = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        self.panel = panel
        return panel
    }

    private func show(_ next: PanePresentation) {
        guard presentation != next else { return }
        presentation = next
        let panel = overlayPanel()
        if panel.frame != next.screen.panelFrame { panel.setFrame(next.screen.panelFrame, display: false) }
        if overlayHost == nil {
            overlayHost = NSHostingView(rootView: PaneOverlayHost(state: overlayState))
            overlayHost?.sizingOptions = []
        }
        let opening = !panel.isVisible
        var transaction = Transaction(); transaction.disablesAnimations = opening
        withTransaction(transaction) { overlayState.presentation = next }
        if panel.contentView !== overlayHost { panel.contentView = overlayHost }
        overlayHost?.frame = CGRect(origin: .zero, size: next.screen.panelFrame.size)
        if opening {
            overlayHost?.layoutSubtreeIfNeeded()
            overlayHost?.displayIfNeeded()
            panel.alphaValue = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 1 : 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.12
                panel.animator().alphaValue = 1
            }
        }
    }

    private func showResult(_ text: String, success: Bool, on screen: PaneScreen) {
        guard session == nil, !workspace.store.missionControl, workspace.native.trusted, workspace.panes.enabled || workspace.panes.edgeSnapping else { return }
        hide()
        let panel = overlayPanel()
        let width = min(460, screen.panelFrame.width - 40)
        panel.setFrame(CGRect(x: screen.panelFrame.midX - width/2, y: screen.panelFrame.minY + 35, width: width, height: 54), display: false)
        panel.contentView = NSHostingView(rootView: PaneResultView(text: text, success: success))
        panel.orderFrontRegardless()
        previewTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    private func recordPlacement(window: LiveWindow, target: CGRect, success: Bool) {
        guard workspace.store.defaults.bool(forKey: "paneDiagnosticsEnabled") else { return }
        let entry: [String: Any] = ["windowID": window.id, "pid": window.pid, "success": success,
                                    "target": rectDictionary(target), "actual": workspace.native.actualFrame(window).map(rectDictionary) ?? [:],
                                    "timestamp": Date().timeIntervalSince1970]
        trace("placement", entry)
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("DeskNames/pane-diagnostics.json")
        if let data = try? JSONSerialization.data(withJSONObject: entry, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: url, options: .atomic) }
    }

    private func rectDictionary(_ rect: CGRect) -> [String: Double] {
        ["x": rect.minX, "y": rect.minY, "width": rect.width, "height": rect.height]
    }

    private func trace(_ event: String, _ fields: @autoclosure () -> [String: Any] = [:]) {
        guard workspace.store.defaults.bool(forKey: "paneDiagnosticsEnabled") else { return }
        var entry = fields()
        entry["event"] = event; entry["time"] = ProcessInfo.processInfo.systemUptime
        diagnosticEvents.append(entry)
        if diagnosticEvents.count > 150 { diagnosticEvents.removeFirst(diagnosticEvents.count - 150) }
        guard let data = try? JSONSerialization.data(withJSONObject: diagnosticEvents, options: [.prettyPrinted, .sortedKeys]) else { return }
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("DeskNames/pane-events.json")
        diagnosticQueue.async { try? data.write(to: url, options: .atomic) }
    }
}


extension SmartPaneController {
    func verifyOverlayGeometryForTesting() async throws {
        guard let screen = PaneScreen.current.first,
              let next = makePresentation(at: CGPoint(x: screen.area.midX, y: screen.area.midY), screens: [screen], previewOnly: true) else {
            throw WindowIssue("No pane preview is available for this test.")
        }
        defer { stop(); panel?.close() }
        for afterResult in [false, true] {
            if afterResult { showResult("Fixture placement", success: true, on: screen) }
            show(next)
            await NativeWindows.pause(0.2)
            guard let panel, let overlayHost else { throw WindowIssue("Pane preview did not create its hosting view.") }
            overlayHost.layoutSubtreeIfNeeded()
            let expected = CGRect(origin: .zero, size: screen.panelFrame.size)
            print("OVERLAY afterResult=\(afterResult) panel=\(panel.frame) host=\(overlayHost.frame) expected=\(screen.panelFrame)")
            guard panel.frame == screen.panelFrame, overlayHost.frame == expected else {
                throw WindowIssue("The visible pane preview differs from the placement coordinate space.")
            }
            hide()
            precondition(overlayState.presentation == nil, "Hidden overlays must not retain a stale layout or highlight")
        }
        print("PASS: fresh and post-result overlay hosting frames match the detected work area")
    }

    func verifyUnrelatedClickForTesting() async throws {
        let enabled = workspace.panes.enabled
        workspace.panes.setEnabled(false)
        defer { workspace.panes.setEnabled(enabled) }
        workspace.run(interruptible: true) {
            try await Task.sleep(nanoseconds: 80_000_000)
            return "Placement survived unrelated click."
        }
        guard let event = NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [],
                                             timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0,
                                             context: nil, eventNumber: 0, clickCount: 1, pressure: 1) else {
            throw WindowIssue("Could not construct the local input fixture.")
        }
        receive(event)
        await workspace.operationTask?.value
        guard workspace.message == "Placement survived unrelated click." else { throw WindowIssue("An unrelated click cancelled the placement.") }
        print("PASS: unrelated pointer clicks do not leave a placement half-finished")
    }

    func verifyLatestDropTargetForTesting(window: LiveWindow) async throws {
        let screens = PaneScreen.current
        guard let screen = screens.first, let desktop = desktop(on: screen) else { throw WindowIssue("Missing test desktop.") }
        let config = workspace.paneConfiguration(for: desktop.id)
        let geometry = PaneGeometry(area: screen.area, configuration: config, pixelScale: screen.pixelScale)
        guard geometry.cells.count > 1 else { throw WindowIssue("Test requires two panes.") }
        let oldPoint = CGPoint(x: geometry.cells[0].midX, y: geometry.cells[0].midY)
        let releasePoint = CGPoint(x: geometry.cells[1].midX, y: geometry.cells[1].midY)
        let now = ProcessInfo.processInfo.systemUptime
        var evidence = PaneMoveEvidence(initialFrame: window.frame, initialPointer: oldPoint, time: now)
        for i in 1...3 {
            let offset = CGFloat(i*20)
            evidence.observe(frame: window.frame.offsetBy(dx: offset, dy: 0), pointer: CGPoint(x: oldPoint.x+offset, y: oldPoint.y), time: now+Double(i)*0.04)
        }
        guard evidence.moved, workspace.beginUserWindowDrag() else { throw WindowIssue("Could not prepare the disposable drag session.") }
        session = Session(window: window, screens: screens, desktops: workspace.store.desktops, evidence: evidence)
        session?.presentation = makePresentation(at: oldPoint, screens: screens, previewOnly: false)
        release(at: releasePoint, command: true)
        await workspace.operationTask?.value
        guard workspace.native.verifyFrame(geometry.cells[1], window: window) else { throw WindowIssue("Mouse-up used the stale pane instead of the latest pointer position.") }
        stop(); panel?.close()
        print("PASS: a mouse-up crossing panes resolves the latest pointer position")
    }
}
