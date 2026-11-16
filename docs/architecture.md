# DeskNames architecture

## Application structure

DeskNames is compiled directly by `build.sh`. There is no package manager dependency graph. The script compiles `NativeSpaceMove.m`, links every Swift file under `Sources/DeskNames/` against AppKit, SwiftUI, and Carbon, writes Info.plist, copies resources and third-party notices, and signs the bundle. Signing defaults to ad hoc; a configured persistent certificate supports repeated development builds without changing the designated identity.

`main.swift` defines desktop identity, preference-backed names and colors, Space enumeration, Mission Control labels, and application lifecycle. It also dispatches command-line test and preview modes.

## Source map

Application sources live in `Sources/DeskNames/`; the self-tests compiled into the app (run with `--self-test`) live in `Sources/DeskNames/SelfTests/`.

| Files | Responsibility |
| --- | --- |
| `main.swift` | SpaceReader, Store, overlay panels, and AppDelegate |
| `ControlCenter.swift` | One native window, quick/settings routes, sizing, focus restoration, and background-launch classification |
| `SettingsViews.swift` | Settings page model, navigation, and detailed editor composition |
| `GeneralPreferences.swift` | Read-only preference initialization, visibility persistence, and General settings for menu bar, startup, and updates |
| `MissionControlGeometry.swift`, `AlignmentDiagnostics.swift` | Native strip geometry, stable placement, and alignment diagnostics |
| `DesktopNavigation.swift` | Mission Control thumbnail selection for direct desktop jumps |
| `WindowManager.swift` | Saved/live window models, Accessibility operations, LayoutController, and operation coordination |
| `LayoutSnapshots.swift` | Layout capture, restored frame choice, destination resolution, overlap restoration, and preview |
| `WorkspaceViews.swift` | Layout and window management interface |
| `PaneModel.swift`, `PaneViews.swift` | Presets, stored pane settings, geometry, and settings interface |
| `PaneInteraction.swift`, `LinkedPanes.swift` | Shared-divider geometry and persisted ratios, pane shortcut actions, display-paced interruptible frame transitions, reused divider handles, shortcut-layout detection and serialized linked-resize transactions |
| `SmartPanes.swift` | Drag observation, overlays, snapping, cancellation, and edge snapping |
| `WindowActions.swift` | Direct window commands and original-frame history |
| `Shortcuts.swift`, `ShortcutDefaults.swift` | Binding defaults, persistence, validation, recording, digit normalization, and Carbon hotkey registration |
| `ShortcutConflicts.swift` | Physical shortcut identities, macOS/global conflict inspection, report model, and shared setup/settings report |
| `DisplayProfiles.swift`, `ScreenAwareWindows.swift` | Monitor identity/model matching, model-shared presets, and display-aware operations |
| `PinnedWindows.swift` | Session-only pinned windows that follow the current desktop on their display, the pin confirmation bubble, and the control-panel pin section |
| `WindowRouting.swift`, `WindowRoutingView.swift` | Rule persistence, window birth tracking, routing, and settings interface |
| `NativeSpaceMove.m` | Native bridged Space transfer and symbol resolution |
| `SelfTests/`: `Tests.swift`, `GeometryTests.swift`, `PaneTests.swift`, `PaneInteractionTests.swift`, `MovementTests.swift`, `WindowActionTests.swift`, `ScreenLayoutTests.swift` | Matching, geometry, persistence, operation sessions, window commands, and screen cases |
| `MarketingPreview.swift` | Offscreen, fixture-only rendering of the README screenshot and illustrated demo |
| `FirstRunPreferences.swift`, `FirstRunPanel.swift`, `LoginItemController.swift` | Persistent first-run gating and progress, one-time pane spacing migration, compact welcome UI and explicit login-item registration |
| `Tools/`: `Fixture.swift`, `probe.swift`, `geometry.swift`, `window-check.swift`, `verify_alignment.py` | Separate development fixtures and inspection helpers, not part of the app build |
| `Tools/Icon.swift`, `Resources/DeskNames.icns`, `Resources/DeskNames.iconset/` | Icon generation source and app icon resources |
| `docs/command-drag-review.md`, `docs/smooth-movement-report.md` | Historical design review and measured movement results |

## Runtime flow

AppDelegate creates the store, window/layout controller, overlays, pane controller, and shortcuts. Space notifications refresh active desktop state. The store associates appearance settings with stable desktop IDs.

ControlCenter owns one NSWindow and switches its content between compact controls and detailed settings. Quick controls are non-resizable and floating; settings are resizable at normal window level, preserving editor eligibility for capture and snapping. Routes retain the selected quick-controls section and original external application for focus restoration. Navigation and closing cancel shortcut recording. Opening settings from onboarding does not complete setup; Back restores its current step.

GeneralPreferences reads visibility defaults without writing them during initialization. AppDelegate applies icon/name visibility and hide-on-deactivate to the status item and control window. Explicit app reopen forces the control center open even when the menu-bar icon is hidden. A cold explicit launch also recovers the hidden-icon state, while login/service Apple events suppress that recovery opening. Startup registration and update settings live in General, with the initial login choice also available during onboarding.

ShortcutConflictInspector combines enabled CopySymbolicHotKeys entries with short-lived exclusive Carbon registration probes. PhysicalShortcut retains raw key codes so a successful number-row registration cannot conceal a conflicting numpad variant. HotKeys supplies only its successfully owned physical combinations, which are excluded from probes. Each acquired probe is released immediately. Reports distinguish known macOS conflicts, occupied global registrations, and incomplete checks; they neither identify other applications nor guarantee discovery of app-local bindings. The welcome shortcut step and keyboard page share the report UI. Edits invalidate reports, and enabling or reapplying unchanged bindings refreshes an existing report after registration changes.

AppDelegate captures first-run eligibility from the persistent preference domain before initializing preference-writing services. It applies the pane spacing migration only in normal application startup, before constructing pane models. Model construction, self-tests and rendering never implicitly migrate standard preferences. The existing timer polls Accessibility trust for the welcome state and panel banner. Login-item registration is separate from UserDefaults and uses explicit SMAppService actions.

LayoutController coordinates operations through idle, user-drag, and writing states. A desktop request received during a window operation retains the latest destination. Pane sessions and routing must respect this shared admission state to avoid competing native writes.

The layout capture path enumerates ordinary windows, associates each with a screen and desktop, records geometry and order, rechecks topology, and persists atomically. Restore matches windows, resolves display destinations, applies frames, and reports constrained or missing targets. Manual restoration can verify overlap order. Automatic restoration does not raise windows.

Overlap capture and verification use the on-screen WindowServer list. The all-windows list remains useful for identity discovery, but can retain ordering from inactive Space lists. New captures record the ordering source; older captures stay readable and show resave guidance. Manual restore includes surviving size-constrained windows in ordering and requires two consecutive complete order observations on each visible desktop after bounded raise attempts. A raise can affect the same app's key window on another screen, so later passes repair only the necessary front prefixes while leaving the longest correctly ordered lower suffix untouched. Each raise is observed relative to its expected lower windows before another raise begins. Owned AppKit windows use `orderFrontRegardless()` so an inactive editor can rise above other applications. Verification counts every participating window and rejects missing windows or inversions within either desktop; unrelated interleaving ranks between screens do not represent visible overlap.

External Accessibility writes run on a serial worker with cancellation checks and bounded messaging timeouts. Each request reacquires the exact window by process/window identity; WindowServer bounds verify the result independently of the AX reply. Cross-display transfers establish native destination-Space ownership before fitting geometry. Neither path adds a focus-changing drag fallback for automatic operations.

Operation preflight reads external eligibility and identity on the same serial AX worker, leaving the main event loop available. It retries a failed cached AX reference by reacquiring the exact window ID/process, then repeats the ordinary-window, minimized/full-screen and owner checks. Routing rechecks its settings revision, input/operation state, initial frame/Space and destination after the await. Routing discovery also awaits the bounded background census and rechecks its settings revision before consuming results. A bounded fallback diagnostic distinguishes this recovery from a confirmed window closure. Tests can direct diagnostics to temporary storage.

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

## Isolated normal application storage

`open -n build/DeskNames.app --args --storage /absolute/disposable/directory`
starts the normal UI and Carbon shortcuts with isolated preferences. Configuration
runs before any test-mode dispatch or `NSApplication` creation. It does not change
the installed application or its saved settings.

`RuntimeStorage(directory:)` exposes the same `defaults` and `supportDirectory`
for helpers to seed before launching the separate app. Preferences use an absolute
UserDefaults suite at `<directory>/preferences.plist`. Call
`storage.defaults.synchronize()` after seeding and before launch. Layouts and all
DeskNames diagnostics use `<directory>/Application Support/DeskNames/`. The
normal first-run check uses this isolated suite's domain. Missing, relative,
duplicate or unreadable storage arguments fail instead of selecting live storage.

In isolated mode, the public Objective-C `standardUserDefaults` getter returns
the isolated suite too, so AppKit window preferences cannot use the owner's app
domain. This replacement occurs only in the isolated process. Sparkle is not
constructed in this mode. An absolute suite was verified to exclude the process's
normal application domain and persist beneath the supplied directory;
`CFFIXED_USER_HOME` alone did not redirect preference-daemon writes on this Mac.
The supported mode changes DeskNames storage, not macOS Accessibility permission
or system services such as launch-at-login registration.

The real-key integration harness and recovery wrapper are described in [hotkey-soak.md](hotkey-soak.md). `SelfTests/HotkeySoakTests.swift` owns input generation, fixture ownership, WindowServer assertions, and recovery. `scripts/test-hotkey-soak.py` owns the independent timeout and installed-app relaunch.
