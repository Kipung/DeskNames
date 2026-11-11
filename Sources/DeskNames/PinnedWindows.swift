import AppKit
import SwiftUI

// Pinned windows follow the user: when another desktop becomes current on a pinned window's
// display, DeskNames moves the window there with the verified background transfer (no drag,
// no focus change). Pins last until DeskNames quits because window IDs change when apps relaunch.

enum PinnedFollow {
    struct Window { let id: UInt32; let display: String; let spaces: [UInt64] }

    /// Pinned windows that sit on a different desktop than the current one on their display.
    /// `attempted` holds the desktop each window was already sent to during this visit, so a refused move is not retried.
    static func destinations(_ windows: [Window], desktops: [Desktop], attempted: [UInt32: UInt64]) -> [(id: UInt32, desktop: Desktop)] {
        windows.compactMap { window in
            guard window.spaces.count == 1,
                  let target = desktops.first(where: { $0.display == window.display && $0.isCurrent && !$0.isFullScreen && !$0.id.isEmpty }),
                  window.spaces[0] != target.spaceID, attempted[window.id] != target.spaceID else { return nil }
            return (window.id, target)
        }
    }
}

struct PinTracking {
    var attempted: [UInt32: UInt64] = [:]
    var lastCheck = -Double.infinity
    var lastActive: Set<String> = []
    var activeChangedAt = -Double.infinity
}

extension LayoutController {
    func togglePin(_ candidate: LiveWindow?) {
        guard let candidate else { return notify("Focus a window to pin it.", symbol: "exclamationmark.triangle") }
        if let existing = pinnedWindows.removeValue(forKey: candidate.id) {
            pinTracking.attempted[candidate.id] = nil
            return notify("Unpinned \(existing.appName)", symbol: "pin.slash", detail: "Unpinned \(existing.label).")
        }
        guard nativeSpaceMoveAvailable() == 1 else {
            return notify("Pinning is unavailable on this macOS version", symbol: "exclamationmark.triangle")
        }
        guard !candidate.minimized, native.spaces(for: candidate.id).count == 1 else {
            return notify("Only ordinary windows on one desktop can be pinned", symbol: "exclamationmark.triangle")
        }
        pinnedWindows[candidate.id] = candidate
        notify("Pinned \(candidate.appName)", symbol: "pin.fill",
               detail: "Pinned \(candidate.label). It follows you to other desktops until you unpin it or quit DeskNames.")
    }

    func unpin(_ id: UInt32) {
        pinnedWindows[id] = nil
        pinTracking.attempted[id] = nil
    }

    /// Called from tick(): checks right after a desktop switch, otherwise at most once a second.
    func followPinnedWindows() {
        guard !pinnedWindows.isEmpty else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let active = Set(store.desktops.filter(\.isCurrent).map(\.id))
        if active != pinTracking.lastActive {
            pinTracking = PinTracking(lastActive: active, activeChangedAt: now)
        }
        guard now - pinTracking.lastCheck >= 1, !busy, native.trusted, NSEvent.pressedMouseButtons == 0,
              !store.missionControl, !OverlayController.isMissionControlOpen() else { return }
        // An automatic restore of the entered desktop starts 0.7 s after the switch and skips itself
        // while another operation runs, so give it time before moving pinned windows in.
        if now - pinTracking.activeChangedAt < 1.5, active.contains(where: { layouts[$0]?.autoRestore == true }) { return }
        pinTracking.lastCheck = now
        pinnedWindows = pinnedWindows.filter { native.identityExists($0.value) }
        let candidates = pinnedWindows.values.compactMap { window -> PinnedFollow.Window? in
            guard let frame = native.actualFrame(window), let screen = screenFor(frame) else { return nil }
            return PinnedFollow.Window(id: window.id, display: screenUUID(screen), spaces: native.spaces(for: window.id))
        }
        let moves = PinnedFollow.destinations(candidates, desktops: store.reader.read(), attempted: pinTracking.attempted)
        guard !moves.isEmpty else { return }
        for move in moves { pinTracking.attempted[move.id] = move.desktop.spaceID }
        run(refreshWindows: false) {
            var moved = 0
            for move in moves {
                guard let pinned = self.pinnedWindows[move.id], let live = await self.native.refreshedForOperation(pinned), !live.minimized else { continue }
                try await self.native.transfer(live, to: move.desktop, reader: self.store.reader)
                moved += 1
            }
            return moved == 1 ? "Brought your pinned window to \(self.store.name(moves[0].desktop))." : "Brought \(moved) pinned windows along."
        }
    }

    private func notify(_ text: String, symbol: String, detail: String? = nil) {
        message = detail ?? text + "."
        PinBubble.show(text, symbol: symbol)
    }
}

/// Brief confirmation near the bottom of the screen, so the pin shortcut gives visible feedback.
@MainActor enum PinBubble {
    private static var panel: NSPanel?
    private static var pendingHide: DispatchWorkItem?

    static func show(_ text: String, symbol: String) {
        let view = NSHostingView(rootView: Label(text, systemImage: symbol)
            .font(.system(size: 15, weight: .semibold)).lineLimit(1)
            .padding(.horizontal, 18).padding(.vertical, 11)
            .background(.regularMaterial, in: Capsule()))
        let size = view.fittingSize
        let bubble = panel ?? {
            let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true; p.ignoresMouseEvents = true
            p.level = .statusBar; p.isReleasedWhenClosed = false; p.hidesOnDeactivate = false
            p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            return p
        }()
        bubble.contentView = view
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let area = screen?.visibleFrame {
            bubble.setFrame(CGRect(x: area.midX - size.width/2, y: area.minY + 90, width: size.width, height: size.height), display: true)
        }
        bubble.orderFrontRegardless()
        panel = bubble
        pendingHide?.cancel()
        let hide = DispatchWorkItem { panel?.orderOut(nil) }
        pendingHide = hide
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: hide)
    }
}

/// Control-panel section: pin the window that was focused before the panel opened, or unpin.
struct PinControls: View {
    @ObservedObject var workspace: LayoutController
    let candidate: LiveWindow?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Pinned windows follow you to every desktop", systemImage: "pin").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if let candidate, workspace.pinnedWindows[candidate.id] == nil {
                    Button("Pin \(candidate.appName)") { workspace.togglePin(candidate) }.controlSize(.small)
                }
            }
            ForEach(workspace.pinnedWindows.values.sorted { $0.label < $1.label }) { window in
                HStack {
                    Image(systemName: "pin.fill").foregroundStyle(palette[0])
                    Text(window.label).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button("Unpin") { workspace.unpin(window.id) }.controlSize(.small)
                }.font(.callout)
            }
        }.padding(10).background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
    }
}
