# DeskNames architecture

## Application structure

DeskNames is compiled directly by `build.sh`. There is no package manager dependency graph. The script compiles `NativeSpaceMove.m`, links Swift sources against AppKit, SwiftUI, and Carbon, writes Info.plist, copies resources and third-party notices, and signs the bundle. Signing defaults to ad hoc; a configured persistent certificate supports repeated development builds without changing the designated identity.

`main.swift` defines desktop identity, preference-backed names and colors, Space enumeration, the editor, Mission Control labels, and application lifecycle. It also dispatches command-line test and preview modes.

## Source map

| Files | Responsibility |
| --- | --- |
| `main.swift` | SpaceReader, Store, main editor, overlay panels, and AppDelegate |
| `MissionControlGeometry.swift`, `AlignmentDiagnostics.swift` | Native strip geometry, stable placement, and alignment diagnostics |
| `DesktopNavigation.swift` | Mission Control thumbnail selection for direct desktop jumps |
| `WindowManager.swift` | Saved/live window models, Accessibility operations, LayoutController, and operation coordination |
| `LayoutSnapshots.swift` | Layout capture, restored frame choice, destination resolution, overlap restoration, and preview |
| `WorkspaceViews.swift` | Layout and window management interface |
| `PaneModel.swift`, `PaneViews.swift` | Presets, stored pane settings, geometry, and settings interface |
| `PaneInteraction.swift`, `LinkedPanes.swift` | Shared-divider geometry and persisted ratios, pane shortcut actions, display-paced interruptible frame transitions, reused divider handles, shortcut-layout detection and serialized linked-resize transactions |
| `SmartPanes.swift` | Drag observation, overlays, snapping, cancellation, and edge snapping |
| `WindowActions.swift` | Direct window commands and original-frame history |
| `Shortcuts.swift` | Binding persistence, validation, recording, and Carbon hotkey registration |
| `DisplayProfiles.swift`, `ScreenAwareWindows.swift` | Monitor identity/model matching, model-shared presets, and display-aware operations |
| `WindowRouting.swift`, `WindowRoutingView.swift` | Rule persistence, window birth tracking, routing, and settings interface |
| `NativeSpaceMove.m` | Native bridged Space transfer and symbol resolution |
| `Tests.swift`, `GeometryTests.swift`, `PaneTests.swift`, `PaneInteractionTests.swift`, `WindowActionTests.swift`, `ScreenLayoutTests.swift` | Matching, geometry, persistence, operation sessions, window commands, and screen cases |
| `Fixture.swift`, `probe.swift`, `geometry.swift`, `window-check.swift`, `verify_alignment.py` | Separate development fixtures and inspection helpers |
| `Icon.swift`, `DeskNames.icns`, `DeskNames.iconset/` | Icon generation source and app icon resources |
| `backup/DeskNames-v0.1.swift` | Historical source snapshot, excluded from the application build |

## Runtime flow

AppDelegate creates the store, window/layout controller, overlays, pane controller, and shortcuts. Space notifications refresh active desktop state. The store associates appearance settings with stable desktop IDs.

LayoutController coordinates operations through idle, user-drag, and writing states. A desktop request received during a window operation retains the latest destination. Pane sessions and routing must respect this shared admission state to avoid competing native writes.

The layout capture path enumerates ordinary windows, associates each with a screen and desktop, records geometry and order, rechecks topology, and persists atomically. Restore matches windows, resolves display destinations, applies frames, and reports constrained or missing targets. Manual restoration can verify overlap order. Automatic restoration does not raise windows.

Overlap capture and verification use the on-screen WindowServer list. The all-windows list remains useful for identity discovery, but can retain ordering from inactive Space lists. New captures record the ordering source; older captures stay readable and show resave guidance. Manual restore includes surviving size-constrained windows in ordering and requires two consecutive complete order observations on each visible desktop after bounded raise attempts. A raise can affect the same app's key window on another screen, so later passes repair only the necessary front prefixes while leaving the longest correctly ordered lower suffix untouched. Each raise is observed relative to its expected lower windows before another raise begins. Owned AppKit windows use `orderFrontRegardless()` so an inactive editor can rise above other applications. Verification counts every participating window and rejects missing windows or inversions within either desktop; unrelated interleaving ranks between screens do not represent visible overlap.

External Accessibility writes run on a serial worker with cancellation checks and bounded messaging timeouts. Each request reacquires the exact window by process/window identity; WindowServer bounds verify the result independently of the AX reply. Cross-display transfers establish native destination-Space ownership before fitting geometry. Neither path adds a focus-changing drag fallback for automatic operations.

Operation preflight reads external eligibility and identity on the same serial AX worker, leaving the main event loop available. It retries a failed cached AX reference by reacquiring the exact window ID/process, then repeats the ordinary-window, minimized/full-screen and owner checks. Routing rechecks its settings revision, input/operation state, initial frame/Space and destination after the await. Routing discovery still uses a synchronous census; the unresolved live-routing gap is recorded in validation notes. A bounded fallback diagnostic distinguishes this recovery from a confirmed window closure. Tests can direct diagnostics to temporary storage.

Routing scans window identities when enabled. WindowBirthTracker separates already known windows from new observations and discards stale work across settings revisions or unavailable operation periods. Native transfer verifies the result rather than assuming a successful request means a successful move.

## Local state

| State | Location |
| --- | --- |
| Names, colors, shortcuts, pane settings, monitor presets, routing rules | `local.desknames.app` UserDefaults domain |
| Saved layouts | `~/Library/Application Support/DeskNames/layouts-v1.json` |
| Desktop jump diagnostics | `~/Library/Application Support/DeskNames/desktop-jump.json` |
| Last window-operation failure, refresh fallback and manual order result | `~/Library/Application Support/DeskNames/window-operation-error.json`, `window-refresh-result.json`, `layout-order-result.json` |
| Previous window frames for restore-size commands | Bounded in-memory history for the app session |

Layout storage is separate from application code. Window titles and app identifiers can describe personal work. Tests must use temporary domains and files rather than replace live user state.

## Platform dependencies

Public AppKit, SwiftUI, Accessibility, Core Graphics, and Carbon APIs provide UI and window controls. Private Space and SkyLight interfaces supply functionality unavailable through stable public APIs. Unsupported native transfers are refused for automatic routing. Manual same-display operations can retain the older simulated drag path where applicable.

These dependencies make native testing on each intended macOS version necessary. Deployment target, compilation success, and simulated display tests establish different facts and must be reported separately.


## Releases and update boundaries

`AppUpdater.swift` wraps Sparkle 2.10.1 and exposes manual checks and persisted opt-in settings. AppDelegate starts it only in normal application mode; native tests and marketing rendering do not start update checks. Feed and archive verification are required. `build.sh` embeds the pinned framework and signs helpers inside-out. `scripts/package-release.py` packages the built artifact, verifies the Keychain/public-key match, signs/verifies the archive and feed, and generates the cask checksum. CI compiles/tests without private signing material.

`MarketingPreview.swift` renders the real control-panel view with isolated fictional data, plus an explicitly illustrated pane animation. It neither captures the screen nor renders actual saved preferences/layouts. `scripts/render-demo.sh` encodes these fixture frames as GIF/MP4.
