# DeskNames project context

Status reviewed on November 5, 2026.

## Purpose

DeskNames is a local macOS productivity utility that combines desktop names with window arrangement tools. The original goal was to name virtual desktops. The project expanded into saved layouts, snapping, keyboard controls, and background routing for new windows.

The current product is version 0.5.0, build 22. It is a native Swift, SwiftUI, and AppKit menu bar application with a small Objective-C bridge. It uses Carbon for global shortcut registration and Accessibility for window inspection and manipulation.

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
