# DeskNames project context

Status reviewed on November 10, 2026.

## Purpose

DeskNames is a local macOS productivity utility that combines desktop names with window arrangement tools. The original goal was to name virtual desktops. The project expanded into saved layouts, snapping, keyboard controls, and background routing for new windows.

The current product is version 0.5.0, build 27. It is a native Swift, SwiftUI, and AppKit menu bar application with a small Objective-C bridge. It uses Carbon for global shortcut registration and Accessibility for window inspection and manipulation.

## Repository and working copy

The canonical working copy is the DeskNames folder under the external drive's Project directory. On the development Mac, the mounted location is `/Volumes/Extra/Project/DeskNames`. The Desktop's Project folder is a symbolic link to `/Volumes/Extra/Project`, so both paths refer to the same files.

The installed application is `/Applications/DeskNames.app`. It is separate from the source checkout and is not updated by editing source files. Build with `./build.sh`, quit a running copy, and install the resulting app deliberately.

The repository began with commit `072457d`, titled `DeskNames 0.5.0`, dated November 2, 2026. Earlier experiments and packaged outputs exist outside the canonical checkout in the original development chat's workspace. The repository contains the complete current build sources, tests, icon resources, build script, license, notices, and an early source backup. Personal runtime preferences and saved window arrangements are deliberately outside Git.

## Implemented behavior

### Names and desktop navigation

Names and colors follow stable Space UUIDs rather than desktop numbers. Mission Control labels use Accessibility geometry from the expanded native strip. Labels hide when geometry is compact, unavailable, or inconsistent. Full-screen Spaces keep native labels. Desktop jumps select the destination thumbnail directly, so intermediate desktops are skipped, but Mission Control still appears briefly.

### Layout capture and restore

New captures store exact frames, normalized fallback frames, screen bounds and work areas, display profiles, per-window desktop identities, desktop positions, and front-to-back order. The editor can participate in the capture. Capture rechecks topology before replacing an existing layout.

Matching starts with live identity and then uses unambiguous app/title matches. Ambiguous windows are skipped. Manual restore can visit saved desktops, gather windows if enabled, and raise windows to reproduce overlap order. Automatic restore changes visible-desktop geometry while preserving focus and does not restore stacking. Missing-app launch cannot recreate unsaved content.

Exact geometry is preferred when resolution is unchanged, including when the Dock or menu bar changes the work area. Resolution changes use a reported fitted fallback. Legacy layouts remain readable but need a new save for the added metadata.

### Smart panes and window commands

Seven presets are available: Two columns, Three columns, Four columns, Four quarters, Two rows, Wide + stack, and Focus. Command-drag previews targets and snaps on mouse release. Cancelling, changing desktops, competing writes, and stale sessions must not trigger a late snap.

Edge and corner snapping are independently optional. Direct commands include halves, quarters, thirds, maximize, center, size changes, restore previous size, and next/previous display. Original-frame history is bounded and belongs to the current app session, separate from persistent saved layouts.

### New-window routing

Rules match an app bundle identifier and optionally a title substring. The user's explicit choice was to move a window only when it opens. Routing does not continually enforce a destination.

Existing windows are baselined. Rule edits and periods when another operation prevents routing do not create a backlog of windows to move later. A bounded observation period lets metadata settle. Automatic transfers use the native background path on supported systems and verify the result. They never use a simulated drag fallback.

### Screen awareness

Exact screen UUID matching comes first. Equivalent replacement monitors can use vendor/model profiles and desktop positions. Identical connected displays use spatial roles, and ambiguous destinations are refused. Shared pane presets apply by monitor model rather than serial number. Pure tests cover replacement and repeated-model assignments, but live hardware validation remains incomplete.

## Decisions to preserve

- Global shortcuts and automatic behaviors remain opt-in.
- Window routing is new-window-only and must respect later manual movement.
- Automatic operations preserve focus and do not silently fall back to desktop traversal.
- Manual restore and automatic restore have different stacking behavior.
- Missing or ambiguous windows and displays produce reported skips or refusals.
- Preserve user preferences and existing layout files during tests and upgrades.
- Keep native bridge attribution in source and in the app bundle.
- Distinguish recorded native tests, pure tests, and untested hardware behavior.

## Current validation and limits

The original build 22 validation recorded successful build/signature checks, self-tests, pane session tests, and a native overlapping-window restore test. A native external-app test on build 21 verified TextEdit routing without changing the active desktop or rerouting a manually moved window. Build 22 retained that transfer path and added monitor assignment tests.

Only one physical screen was connected during that work. Cross-monitor transfer, reconnects, and simultaneous identical-monitor mapping remain unverified on hardware. Global hotkey delivery through a physical keyboard also remains a user check. App-specific Accessibility constraints and private macOS API changes remain compatibility risks.

The preview is ad hoc signed and has no notarized distribution pipeline. The build script targets Apple Silicon and macOS 14 or later; native background transfer support is narrower. No broad OS compatibility claim follows from the deployment target.

## Next work

1. Connect two monitors and test cross-screen manual moves, layout restoration, active desktop preservation, and monitor disconnection/reconnection.
2. Test two identical monitors and an equivalent replacement monitor. Verify ambiguity handling rather than accepting a guessed assignment.
3. Confirm configured global shortcuts with a physical keyboard.
4. Test fresh-install Accessibility permission flow and representative third-party apps.
5. Decide supported macOS versions based on native testing, then plan signing, notarization, and distributable releases.

## Relationship to computer use

DeskNames organizes windows and Spaces. It does not create a separate input session, virtual machine, or enforced boundary for an AI agent. A future agent-workspace feature is an idea only, not an implemented capability. Desktop switching and manual restore can change the user's view even though background routing is designed to preserve it.

## Start future work

Read this document, README.md, README.txt, and docs/architecture.md. Inspect the current Git state before changes. Run the calculation and pane tests after changes to their behavior. Reserve native layout and desktop-navigation checks for a time when temporary windows or visible desktop transitions are acceptable. Update validation notes with the exact build, environment, test, and remaining gap.

## Pane interaction update — November 10, 2026

Four columns, preset selection/cycling shortcuts, pane placement shortcuts, and opt-in linked pane resizing are implemented. Shared divider handles resize aligned neighboring windows together and save normalized divider positions only after verified completion; cancellation or app constraints roll back participating windows. Snaps and direct window size actions use short easing transitions and respect Reduce Motion. Existing saved shortcut bindings are preserved, with new suggestions opt-in. `--pane-interaction-test` exercises native fixture animation, cancellation, shared resize persistence, and constrained-neighbor rollback; external-app gesture and physical-monitor coverage must still be verified separately.

## Motion update — build 24

Direct halves/thirds/fourths/quarters and Command-drag now share monitor work-area, gap, custom-divider, and backing-pixel calculations. Animation uses distance-sensitive ease-out and display-frame deadlines. Latest placement requests replace pending ones; cancellation waits for the previous writer before starting a replacement. Frame streams reuse identity-validated AX references, and completion avoids a synchronous external window census. Enhanced UI is temporarily suppressed for the entire animation or linked-drag session only when already enabled, then restored to its prior state, including cancellation and error cleanup.

Linked handles are reused between scans and detect aligned standard shortcut layouts as well as the active guide. Linked writes are batched and paced against display deadlines. Active-preset divider changes persist; inferred layouts retain adjusted ratios for the current session without changing the chosen guide. The opt-in linked-resizing setting and existing shortcut bindings are preserved.

`--movement-session-test` adds native cancellation/retargeting/restore-history and shared-divider coverage. See SMOOTH_MOVEMENT_REPORT.md for measured external-app results and hardware limits.


## Command-drag and motion correction — build 25

The build 24 report established final bounds, not consistently smooth animation. A read-only Claude Code review using `claude-opus-5-5`, authorized by the user for project source/documentation, identified stale overlay state, mouse-up target lag, unrelated clicks cancelling placement, and serialized external-app writes. Build 25 clears hidden overlay state, isolates highlight animation from geometry, fixes the hosting frame, updates hover from pointer events, resolves the final mouse-up position, and lets unrelated clicks leave a placement running. New drags can be admitted after an existing placement finishes.

External writes are serialized per application instead of globally. Unchanged dimensions are skipped. Windows shrink before moving and grow afterward; live TextEdit testing reproduced a 73-point height shortfall from the old size-first order. The final build eliminated that correction pass. Transitions use smoothstep easing, finish directly when frame writes exceed two display intervals, and give receiving apps up to 120 ms to settle before compatibility retry. This does not establish smooth resizing in every third-party app.

All five test modes passed. The final installed executable SHA-256 is `211156a04bed308fc5f071d63000fe358df0b568d602f38fad204a31c9db6cea`. Live TextEdit thirds, fourth column and corner commands matched their target exactly, without compatibility retries. Physical monitor coverage remains one 5120×1409-point work area at scale 1, reporting 144 Hz. See COMMAND_DRAG_REVIEW.md for measurements and limits. User-approved Code spacing is 0 points; other runtime preferences and saved layouts were preserved. Linked resizing remains opt-in and was tested in isolated native fixtures.

The user subsequently tested physical Command-drag on the installed build and confirmed that it fills correctly and feels better.


## Control panel — build 26

The existing shortcut action 100 now opens a DeskNames control panel with Pane layouts and Desktops tabs. Existing shortcut bindings are retained; the suggestion for a new installation is Control–Option–Command–Space to avoid Finder. All seven layouts are illustrated, searchable, and selectable by click or arrows/Return. The panel captures the active desktop before activating DeskNames, shows its name and current layout, and rechecks the desktop identity/current status before saving. Changing a preset preserves spacing; selecting the current preset preserves custom dividers. It honors explicitly shared monitor presets and labels that scope. It changes pane guides, not existing window positions. Escape restores previous-app focus; Settings opens the full editor. Desktop switching remains available in its own tab.

Build 26 validation: build/signature checks and `--self-test` passed on the final executable; `--movement-session-test` passed with the new popup preset-selection tests before the final height-only adjustment. Those tests cover all seven choices, preserved spacing/custom dividers, another desktop left unchanged, and stale/busy target refusal. Live UI checks verified arrow/Return selection of Four columns, reopening with the saved choice, search/Return restoring Three columns, desktop-tab search with no-result Return, and Escape dismissal. The final popup visibly fits all seven cards. Existing Accessibility approval was renewed after installation. Runtime preferences compare unchanged after the temporary selection test, and saved layout bytes are unchanged. Physical global-shortcut confirmation for this build is pending; automated shortcut injection did not open the panel. Installed executable SHA-256: `100a1b37f1ce9d7d5cae273482193494677a889645b62ffcfcc385cbb0c0b94c`.


## Utility window behavior — build 27

The user confirmed build 26's physical control-panel shortcut, but reported that the full editor appeared with it. Build 27 starts without creating or presenting the full editor. The menu-bar icon and app reopen route to the compact panel; opening that panel hides an existing editor before activating DeskNames. Only the panel's explicit Settings action creates/shows the editor, and that window is not restorable by AppKit. Closing the panel does not reopen the editor.

Build 27 passed build/signature verification and `--self-test`. Live checks opened the compact panel, explicitly opened Settings, returned to the panel from that editor, and dismissed with Escape. Computer Use then reported `noWindowsAvailable`, confirming the editor was hidden instead of reappearing. Equivalent Accessibility approval was renewed. Installed executable SHA-256: `b8f082fdeff1edf3a2bc739bfbc79d76cbd59191ef3b9a33efbc25afd1a353c3`.
