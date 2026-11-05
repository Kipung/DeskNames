# DeskNames architecture

## Application structure

DeskNames is compiled directly by `build.sh`. There is no package manager dependency graph. The script compiles `NativeSpaceMove.m`, links Swift sources against AppKit, SwiftUI, and Carbon, writes Info.plist, copies resources and third-party notices, and signs the bundle ad hoc.

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
| `SmartPanes.swift` | Drag observation, overlays, snapping, cancellation, and edge snapping |
| `WindowActions.swift` | Direct window commands and original-frame history |
| `Shortcuts.swift` | Binding persistence, validation, recording, and Carbon hotkey registration |
| `DisplayProfiles.swift`, `ScreenAwareWindows.swift` | Monitor identity/model matching, model-shared presets, and display-aware operations |
| `WindowRouting.swift`, `WindowRoutingView.swift` | Rule persistence, window birth tracking, routing, and settings interface |
| `NativeSpaceMove.m` | Native bridged Space transfer and symbol resolution |
| `Tests.swift`, `GeometryTests.swift`, `PaneTests.swift`, `WindowActionTests.swift`, `ScreenLayoutTests.swift` | Matching, geometry, persistence, operation sessions, window commands, and screen cases |
| `Fixture.swift`, `probe.swift`, `geometry.swift`, `window-check.swift`, `verify_alignment.py` | Separate development fixtures and inspection helpers |
| `Icon.swift`, `DeskNames.icns`, `DeskNames.iconset/` | Icon generation source and app icon resources |
| `backup/DeskNames-v0.1.swift` | Historical source snapshot, excluded from the application build |

## Runtime flow

AppDelegate creates the store, window/layout controller, overlays, pane controller, and shortcuts. Space notifications refresh active desktop state. The store associates appearance settings with stable desktop IDs.

LayoutController coordinates operations through idle, user-drag, and writing states. A desktop request received during a window operation retains the latest destination. Pane sessions and routing must respect this shared admission state to avoid competing native writes.

The layout capture path enumerates ordinary windows, associates each with a screen and desktop, records geometry and order, rechecks topology, and persists atomically. Restore matches windows, resolves display destinations, applies frames, and reports constrained or missing targets. Manual restoration can verify overlap order. Automatic restoration does not raise windows.

Routing scans window identities when enabled. WindowBirthTracker separates already known windows from new observations and discards stale work across settings revisions or unavailable operation periods. Native transfer verifies the result rather than assuming a successful request means a successful move.

## Local state

| State | Location |
| --- | --- |
| Names, colors, shortcuts, pane settings, monitor presets, routing rules | `local.desknames.app` UserDefaults domain |
| Saved layouts | `~/Library/Application Support/DeskNames/layouts-v1.json` |
| Desktop jump diagnostics | `~/Library/Application Support/DeskNames/desktop-jump.json` |
| Previous window frames for restore-size commands | Bounded in-memory history for the app session |

Layout storage is separate from application code. Window titles and app identifiers can describe personal work. Tests must use temporary domains and files rather than replace live user state.

## Platform dependencies

Public AppKit, SwiftUI, Accessibility, Core Graphics, and Carbon APIs provide UI and window controls. Private Space and SkyLight interfaces supply functionality unavailable through stable public APIs. Unsupported native transfers are refused for automatic routing. Manual same-display operations can retain the older simulated drag path where applicable.

These dependencies make native testing on each intended macOS version necessary. Deployment target, compilation success, and simulated display tests establish different facts and must be reported separately.
