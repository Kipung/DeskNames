import AppKit

@_silgen_name("dn_can_move_window_to_space") func nativeSpaceMoveAvailable() -> Int32
@_silgen_name("dn_move_window_to_space") private func submitNativeSpaceMove(_ window:UInt32,_ space:UInt64) -> Int32

extension NativeWindows {
    func identityExists(_ window:LiveWindow) -> Bool {
        let infos=CGWindowListCopyWindowInfo(.optionIncludingWindow,window.id) as? [[String:Any]] ?? []
        return infos.contains { ($0[kCGWindowNumber as String] as? UInt32)==window.id && ($0[kCGWindowOwnerPID as String] as? Int32)==window.pid && ($0[kCGWindowLayer as String] as? Int)==0 }
    }
    /// Transfers ownership without following the window or synthesizing a drag.
    @MainActor func transfer(_ window:LiveWindow,to target:Desktop,reader:SpaceReader,frame requestedFrame:CGRect?=nil) async throws {
        guard trusted else {throw WindowIssue("Enable Accessibility before sending windows.")}
        guard nativeSpaceMoveAvailable()==1 else {throw WindowIssue("Background window sending is unavailable on this macOS version.")}
        let topology=reader.read(),screens=ConnectedDisplay.all()
        guard let destination=topology.first(where:{$0.id==target.id && $0.display==target.display && !$0.isFullScreen}),
              let screen=screens.first(where:{$0.id==destination.display}),identityExists(window),!window.minimized else {
            throw WindowIssue("The window, destination desktop, or screen is no longer available.")
        }
        let membership=spaces(for:window.id)
        guard membership.count==1,topology.contains(where:{$0.spaceID==membership[0] && !$0.isFullScreen}) else {
            throw WindowIssue("Only ordinary windows assigned to one desktop can be sent automatically.")
        }
        let active=Set(topology.filter(\.isCurrent).map(\.id))
        let frame: CGRect?
        if let requestedFrame { frame = requestedFrame }
        else if let source=screenFor(window.frame),screenUUID(source) != screen.id {
            frame=WindowAction.movedFrame(window.frame,from:screenArea(source),to:screen.area)
        } else { frame=nil }
        try Task.checkCancellation()
        guard identityExists(window),MissionControlSlot.snapshot(reader.read())==MissionControlSlot.snapshot(topology) else {
            throw WindowIssue("The screen or desktop arrangement changed before the window could be sent.")
        }
        if spaces(for:window.id) != [destination.spaceID] {
            guard submitNativeSpaceMove(window.id,destination.spaceID)==1 else {throw WindowIssue("macOS refused the background window transfer.")}
        }
        for _ in 0..<30 {
            try Task.checkCancellation()
            await Self.pause(0.05)
            guard identityExists(window) else {throw WindowIssue("The window closed while being sent.")}
            if spaces(for:window.id)==[destination.spaceID] {
                // Set ownership first. Geometry writes against a source-Space AX
                // reference can race the WindowServer's cross-display migration.
                // setFrame reacquires this same window by ID on the destination.
                if let frame {
                    guard ConnectedDisplay.all().contains(where:{$0.id==screen.id && $0.area==screen.area}),
                          MissionControlSlot.snapshot(reader.read())==MissionControlSlot.snapshot(topology) else {
                        throw WindowIssue("The screen or desktop arrangement changed while sending the window.")
                    }
                    try await setFrame(frame,window:window)
                    guard verifyFrame(frame,window:window) else {throw WindowIssue("The app could not fit the destination screen.")}
                }
                guard Set(reader.read().filter(\.isCurrent).map(\.id))==active else {throw WindowIssue("Window sent, but the active desktop changed during the operation.")}
                guard let frame=actualFrame(window),screenFor(frame).map(screenUUID)==screen.id else {throw WindowIssue("Window sent, but its screen placement could not be verified.")}
                return
            }
        }
        throw WindowIssue("The window transfer could not be verified. It will not be retried automatically.")
    }
    @MainActor func activeDesktop(reader:SpaceReader) -> Desktop? {
        let all=reader.read()
        let focused=focusedWindow().flatMap{screenFor($0.frame)}
        let screen=focused ?? NSScreen.screens.first(where:{$0.frame.contains(NSEvent.mouseLocation)}) ?? NSScreen.main
        if let screen,let desktop=all.first(where:{$0.display==screenUUID(screen) && $0.isCurrent && !$0.isFullScreen}) {return desktop}
        let current=all.filter{$0.isCurrent && !$0.isFullScreen}
        return current.count==1 ? current[0]:nil
    }
}
