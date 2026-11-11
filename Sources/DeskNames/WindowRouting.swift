import AppKit
import SwiftUI

struct WindowRule: Codable, Identifiable, Equatable {
    var id = UUID()
    var enabled = true
    var bundleID: String
    var titleContains = ""
    var desktopID: String
    var displayID: String
    var appName: String
    var displayProfile:DisplayProfile?
    var desktopPosition:Int?
    @MainActor func destination(desktops:[Desktop],screens:[ConnectedDisplay]) -> Desktop? {
        if let exact=desktops.first(where:{$0.id==desktopID && $0.display==displayID && !$0.isFullScreen}) {return exact}
        guard !screens.contains(where:{$0.id==displayID}),let position=desktopPosition,
              let index=DisplayMatching.index(id:displayID,profile:displayProfile,ids:screens.map(\.id),profiles:screens.map(\.profile)) else{return nil}
        return desktops.first(where:{$0.display==screens[index].id && $0.position==position && !$0.isFullScreen})
    }
}

@MainActor final class RoutingSettings: ObservableObject {
    private struct Stored: Codable { var enabled: Bool; var rules: [WindowRule] }
    private let defaults: UserDefaults
    private let key = "DeskNames.windowRouting.v1"
    @Published var enabled = false { didSet { if enabled != oldValue { persist() } } }
    @Published var rules: [WindowRule] = [] { didSet { if rules != oldValue { persist() } } }
    @Published private(set) var revision = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let saved = try? JSONDecoder().decode(Stored.self, from: data) {
            enabled = saved.enabled
            rules = saved.rules
        }
    }

    private func persist() {
        revision += 1
        if let data = try? JSONEncoder().encode(Stored(enabled: enabled, rules: rules)) {
            defaults.set(data, forKey: key)
        }
    }
}

struct WindowBirthIdentity: Hashable {
    let pid: Int32
    let windowID: UInt32
    let launch: Date
}

struct WindowBirthObservation: Equatable {
    let frame: CGRect
    let spaces: Set<UInt64>

    func matches(_ other: WindowBirthObservation) -> Bool {
        spaces == other.spaces && abs(frame.minX - other.frame.minX) <= 2
            && abs(frame.minY - other.frame.minY) <= 2
            && abs(frame.width - other.frame.width) <= 2
            && abs(frame.height - other.frame.height) <= 2
    }
}

struct WindowBirthTracker {
    private struct Pending { let firstSeen: Double; let observation: WindowBirthObservation }
    private var known = Set<WindowBirthIdentity>()
    private var pending: [WindowBirthIdentity: Pending] = [:]
    private var revision: Int?

    mutating func reset() { known.removeAll(); pending.removeAll(); revision = nil }
    mutating func consume(_ id: WindowBirthIdentity) { pending[id] = nil }
    func observation(for id: WindowBirthIdentity) -> WindowBirthObservation? { pending[id]?.observation }
    func age(of id: WindowBirthIdentity, now: Double) -> Double? {
        pending[id].map { now - $0.firstSeen }
    }

    mutating func observe(census: [WindowBirthIdentity: WindowBirthObservation], now: Double,
                          revision: Int, acceptingWork: Bool) -> [WindowBirthIdentity] {
        let identities = Set(census.keys)
        guard self.revision == revision else {
            self.revision = revision
            known = identities
            pending.removeAll()
            return []
        }
        let births = identities.subtracting(known).filter { id in !known.contains(where:{$0.pid==id.pid && $0.windowID==id.windowID}) }
        known = identities
        guard acceptingWork else { pending.removeAll(); return [] }
        for id in births {
            if let observation = census[id] { pending[id] = Pending(firstSeen: now, observation: observation) }
        }
        var ready: [WindowBirthIdentity] = []
        for (id, birth) in pending {
            guard let current = census[id], birth.observation.matches(current),
                  now - birth.firstSeen <= 3 else { pending[id] = nil; continue }
            if now - birth.firstSeen >= 0.35 { ready.append(id) }
        }
        return ready.sorted { ($0.pid, $0.windowID) < ($1.pid, $1.windowID) }
    }
}

extension LayoutController {
    func scanNewWindows() {
        guard routing.enabled, routing.rules.contains(where:{$0.enabled}), native.trusted else { births.reset(); lastBirthScan = 0; return }
        if busy || NSEvent.pressedMouseButtons != 0 { births.reset() }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastBirthScan >= 1 else { return }
        lastBirthScan = now
        guard let infos = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] else {
            births.reset()
            return
        }
        let apps = Dictionary(uniqueKeysWithValues: NSWorkspace.shared.runningApplications.map { ($0.processIdentifier, $0) })
        let matchingBundles=Set(routing.rules.filter(\.enabled).map(\.bundleID))
        var census: [WindowBirthIdentity: WindowBirthObservation] = [:]
        for info in infos {
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? Int32,
                  let id = info[kCGWindowNumber as String] as? UInt32,
                  let app = apps[pid], app.activationPolicy == .regular,
                  let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { continue }
            census[WindowBirthIdentity(pid: pid, windowID: id, launch: app.launchDate ?? .distantPast)] =
                WindowBirthObservation(frame: frame, spaces: matchingBundles.contains(app.bundleIdentifier ?? "") ? Set(native.spaces(for: id)):[])
        }
        let accepting = !busy && NSEvent.pressedMouseButtons == 0 && !OverlayController.isMissionControlOpen()
        let ready = births.observe(census: census, now: now, revision: routing.revision, acceptingWork: accepting)
        guard accepting, !ready.isEmpty else { return }
        let windows = native.windows()
        let desktops = store.reader.read()
        var batch: [(WindowBirthIdentity, LiveWindow, Desktop, WindowBirthObservation)] = []
        for id in ready {
            guard let window = windows.first(where: { $0.id == id.windowID && $0.pid == id.pid }) else { continue }
            guard id.pid != getpid(), let app = apps[id.pid], app.activationPolicy == .regular,
                  !window.minimized, window.spaceIDs.count == 1,
                  let source = desktops.first(where: { $0.spaceID == window.spaceIDs[0] }), !source.isFullScreen,
                  let initial = births.observation(for: id),
                  initial.matches(WindowBirthObservation(frame: window.frame, spaces: Set(window.spaceIDs))) else {
                births.consume(id)
                continue
            }
            let rules = routing.rules.filter { $0.enabled && $0.bundleID == window.bundleID }
            if window.title.isEmpty, rules.contains(where: { !$0.titleContains.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
               (births.age(of: id, now: now) ?? 2) < 2 { continue }
            let rule = rules.first {
                let title = $0.titleContains.trimmingCharacters(in: .whitespacesAndNewlines)
                return title.isEmpty || window.title.localizedCaseInsensitiveContains(title)
            }
            births.consume(id)
            guard let rule,
                  let destination = rule.destination(desktops:desktops,screens:ConnectedDisplay.all()),
                  NSScreen.screens.contains(where: { screenUUID($0) == destination.display }) else {
                if rule != nil {message="A routing destination is unavailable. Check its desktop and screen."}
                continue
            }
            batch.append((id, window, destination, initial))
        }
        guard !batch.isEmpty else { return }
        let revision = routing.revision
        run {
            var moved = 0
            var skipped = 0
            for (id, window, destination, initial) in batch {
                try Task.checkCancellation()
                let refreshed=await self.native.refreshedForOperation(window)
                try Task.checkCancellation()
                guard self.routing.enabled, self.routing.revision == revision, self.native.trusted,
                      NSEvent.pressedMouseButtons == 0, !OverlayController.isMissionControlOpen(),
                      let app = NSRunningApplication(processIdentifier: id.pid), app.launchDate == id.launch,
                      let live = refreshed, !live.minimized,
                      initial.matches(WindowBirthObservation(frame: live.frame, spaces: Set(live.spaceIDs))),
                      let target = self.store.reader.read().first(where: { $0.id == destination.id && $0.display == destination.display && !$0.isFullScreen }),
                      NSScreen.screens.contains(where: { screenUUID($0) == target.display }) else { skipped += 1; continue }
                do { try await self.native.transfer(live, to: target, reader: self.store.reader); moved += 1 }
                catch is CancellationError { throw CancellationError() }
                catch { return "Moved \(moved) new windows. Routing stopped: \(error.localizedDescription)" }
            }
            return "Moved \(moved) new windows.\(skipped > 0 ? " Skipped \(skipped) changed windows." : "")"
        }
    }
}

@MainActor func runWindowRoutingTests() {
    let id = WindowBirthIdentity(pid: 12, windowID: 34, launch: Date(timeIntervalSince1970: 1))
    let initial = WindowBirthObservation(frame: CGRect(x: 10, y: 20, width: 300, height: 200), spaces: [1])
    var tracker = WindowBirthTracker()
    precondition(tracker.observe(census: [id: initial], now: 0, revision: 0, acceptingWork: true).isEmpty)
    precondition(tracker.observe(census: [id: initial], now: 1, revision: 0, acceptingWork: true).isEmpty)
    tracker.reset()
    precondition(tracker.observe(census: [:], now: 0, revision: 0, acceptingWork: true).isEmpty)
    precondition(tracker.observe(census: [id: initial], now: 1, revision: 0, acceptingWork: true).isEmpty)
    precondition(tracker.observe(census: [id: initial], now: 1.4, revision: 0, acceptingWork: true) == [id])
    tracker.consume(id)
    precondition(tracker.observe(census: [id: initial], now: 1.8, revision: 0, acceptingWork: true).isEmpty)
    for changed in [WindowBirthObservation(frame: initial.frame.offsetBy(dx: 50, dy: 0), spaces: [1]),
                    WindowBirthObservation(frame: initial.frame, spaces: [2])] {
        tracker.reset()
        _ = tracker.observe(census: [:], now: 0, revision: 0, acceptingWork: true)
        _ = tracker.observe(census: [id: initial], now: 1, revision: 0, acceptingWork: true)
        precondition(tracker.observe(census: [id: changed], now: 1.4, revision: 0, acceptingWork: true).isEmpty)
        precondition(tracker.observe(census: [id: initial], now: 1.8, revision: 0, acceptingWork: true).isEmpty)
    }
    tracker.reset()
    _ = tracker.observe(census: [:], now: 0, revision: 0, acceptingWork: true)
    _ = tracker.observe(census: [id: initial], now: 1, revision: 0, acceptingWork: false)
    precondition(tracker.observe(census: [id: initial], now: 1.4, revision: 0, acceptingWork: true).isEmpty)
    tracker.reset()
    _ = tracker.observe(census: [:], now: 0, revision: 0, acceptingWork: true)
    _ = tracker.observe(census: [id: initial], now: 1, revision: 0, acceptingWork: true)
    precondition(tracker.observe(census: [id: initial], now: 1.4, revision: 1, acceptingWork: true).isEmpty)
    precondition(tracker.observe(census: [id: initial], now: 1.8, revision: 1, acceptingWork: true).isEmpty)
    tracker.reset()
    _ = tracker.observe(census: [:], now: 0, revision: 0, acceptingWork: true)
    _ = tracker.observe(census: [id: initial], now: 1, revision: 0, acceptingWork: true)
    _ = tracker.observe(census: [id: initial], now: 1.2, revision: 0, acceptingWork: false)
    precondition(tracker.observe(census: [id: initial], now: 1.8, revision: 0, acceptingWork: true).isEmpty)
    tracker.reset()
    _ = tracker.observe(census: [:], now: 0, revision: 0, acceptingWork: true)
    _ = tracker.observe(census: [id: initial], now: 1, revision: 0, acceptingWork: true)
    precondition(tracker.observe(census: [id: initial], now: 4.1, revision: 0, acceptingWork: true).isEmpty)
    tracker.reset()
    _=tracker.observe(census:[:],now:0,revision:0,acceptingWork:true)
    let burst=Dictionary(uniqueKeysWithValues:(0..<12).map{(WindowBirthIdentity(pid:12,windowID:UInt32(100+$0),launch:id.launch),initial)})
    _=tracker.observe(census:burst,now:1,revision:0,acceptingWork:true)
    precondition(tracker.observe(census:burst,now:1.4,revision:0,acceptingWork:true).count==12,"A burst must not lose windows after the eighth")
    tracker.reset()
    let unknown=WindowBirthIdentity(pid:id.pid,windowID:id.windowID,launch:.distantPast)
    _=tracker.observe(census:[unknown:initial],now:0,revision:0,acceptingWork:true)
    precondition(tracker.observe(census:[id:initial],now:1,revision:0,acceptingWork:true).isEmpty,"Launch-date metadata arriving late is not a new window")
    print("PASS: new-window baseline, one-shot consumption, busy/manual-change/revision/expiry suppression, 12-window burst and late process metadata")
}
