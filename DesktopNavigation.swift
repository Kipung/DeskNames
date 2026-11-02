import AppKit

/// Resolves the native thumbnail by stable identity, including full-screen slots.
enum DesktopNavigation {
    static func index(of target: Desktop, in desktops: [Desktop], buttonCount: Int) -> Int? {
        let display = desktops.filter { $0.display == target.display }.sorted { $0.position < $1.position }
        guard display.count == buttonCount, Set(display.map(\.id)).count == display.count,
              let index = display.firstIndex(where: { $0.id == target.id }) else { return nil }
        return index
    }
}

extension NativeWindows {
    @MainActor func switchSpace(_ target: Desktop, reader: SpaceReader) async throws {
        guard trusted else { throw WindowIssue("Enable Accessibility to use desktop shortcuts.") }
        let initial = reader.read()
        guard let live = initial.first(where: { $0.id == target.id && $0.display == target.display }) else {
            throw WindowIssue("This desktop is no longer available.")
        }
        if live.isCurrent { return }
        guard let screen = MissionControlScreen.current().first(where: { $0.uuid == live.display }),
              let dockApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            throw WindowIssue("The destination display or Dock is unavailable.")
        }
        let dock = AXUIElementCreateApplication(dockApp.processIdentifier)
        AXUIElementSetMessagingTimeout(dock, 0.15)
        func children(_ element: AXUIElement) -> [AXUIElement] {
            axValue(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
        }
        func child(_ element: AXUIElement, _ id: String) -> AXUIElement? {
            let matches = children(element).filter { axValue($0, kAXIdentifierAttribute) as? String == id }
            return matches.count == 1 ? matches[0] : nil
        }
        let openedHere = child(dock, "mc") == nil
        if openedHere {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Mission Control.app"))
            // Dock exposes its buttons before they accept presses during the entrance animation.
            await Self.pause(0.35)
        }
        func record(_ phase: String) {
            let path=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("DeskNames/desktop-jump.json")
            let current=reader.read().filter(\.isCurrent).map(\.number)
            let detail:[String:Any]=["phase":phase,"targetNumber":live.number,"currentNumbers":current,"openedMissionControl":openedHere]
            if let data=try? JSONSerialization.data(withJSONObject:detail,options:[.prettyPrinted,.sortedKeys]) {try? data.write(to:path,options:.atomic)}
        }
        do {
            var pressed = false
            for _ in 0..<30 {
                try Task.checkCancellation()
                if let mc = child(dock, "mc"),
                   let display = children(mc).first(where: { (axValue($0, "AXDisplayID") as? NSNumber)?.uint32Value == screen.displayID }),
                   let strip = child(display, "mc.spaces"), let list = child(strip, "mc.spaces.list") {
                    let buttons = children(list)
                    let before = reader.read()
                    if buttons.allSatisfy({ axValue($0, kAXRoleAttribute) as? String == kAXButtonRole }),
                       let index = DesktopNavigation.index(of: live, in: before, buttonCount: buttons.count),
                       MissionControlSlot.snapshot(before) == MissionControlSlot.snapshot(initial) {
                        let result = AXUIElementPerformAction(buttons[index], kAXPressAction as CFString)
                        guard result == .success else { throw WindowIssue("Mission Control could not select the desktop. Try again.") }
                        record("selected")
                        pressed = true
                        break
                    }
                }
                await Self.pause(0.05)
            }
            guard pressed else { throw WindowIssue("Mission Control did not expose the requested desktop. Try again.") }
            for _ in 0..<40 {
                await Self.pause(0.05)
                try Task.checkCancellation()
                if reader.read().contains(where: { $0.id == live.id && $0.isCurrent }) { record("finished");return }
            }
            throw WindowIssue("macOS did not finish switching to the requested desktop.")
        } catch {
            record("failed: " + error.localizedDescription)
            // Close only the Mission Control session opened by this operation.
            if openedHere, child(dock, "mc") != nil {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Mission Control.app"))
            }
            throw error
        }
    }
}

@MainActor func runDesktopNavigationTests() {
    func desktop(_ id: String, _ display: String, _ position: Int, _ fullscreen: Bool = false) -> Desktop {
        Desktop(id:id,spaceID:UInt64(position+1),display:display,position:position,number:position+1,isCurrent:false,isFullScreen:fullscreen)
    }
    let a=desktop("a","screen1",0), b=desktop("b","screen1",1,true), c=desktop("c","screen1",2), other=desktop("other","screen2",0)
    precondition(DesktopNavigation.index(of:c,in:[other,a,b,c],buttonCount:3)==2)
    precondition(DesktopNavigation.index(of:b,in:[a,b,c],buttonCount:3)==1)
    precondition(DesktopNavigation.index(of:c,in:[a,c],buttonCount:3)==nil)
    precondition(DesktopNavigation.index(of:c,in:[a,b],buttonCount:2)==nil)
    precondition(DesktopNavigation.index(of:c,in:[a,a,c],buttonCount:3)==nil)
    precondition(DesktopNavigation.index(of:other,in:[a,b,c,other],buttonCount:1)==0)
    print("PASS: direct desktop selection respects display, full-screen slots, identity and changed thumbnail counts")
}
