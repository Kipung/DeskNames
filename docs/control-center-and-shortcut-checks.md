# Unified controls and setup shortcut checks

Local validation on November 16, 2026, on macOS 26.6.2 arm64. This preview includes the shortcut defaults, numeric-key equivalence and original-desktop fixes described in [the earlier report](shortcut-defaults-and-primary-desktop.md).

## Behavior and ownership

Quick controls and detailed settings share one native window. Back returns to controls or the current setup step. Settings remains resizable and eligible for window capture; quick controls remain excluded. General groups menu-bar visibility, desktop-name visibility, hiding when switching apps, startup and updates. Explicitly opening DeskNames recovers the controls even with its icon hidden and shortcuts disabled. Background login/service launches remain quiet.

`ControlCenter.swift` owns window routes and lifecycle. `SettingsViews.swift` owns the settings shell. `GeneralPreferences.swift` owns appearance preferences and their view. `ShortcutConflicts.swift` owns typed reports and the system/registration boundary. Existing detailed customization pages and saved preferences remain available.

The welcome shortcut step checks automatically. Keyboard settings provides the same report and Recheck. The check reads enabled macOS symbolic shortcuts and temporarily attempts exclusive Carbon registration for each physical key variant. Successful probes are released immediately; the app's own successful registrations are skipped. Numeric aliases remain distinct during probing. Occupied combinations, system reservations and incomplete checks have different results. Binding edits invalidate the report, and enabling or reapplying unchanged bindings refreshes it.

The check does not enable shortcuts or change macOS settings. It cannot detect every app-local shortcut or identify the owner of an occupied global registration. It describes the current registrations, so use Recheck after other apps start or their settings change.

## Verification

The canonical checkout produced `build/control-center/DeskNames.app` using `./build.sh "$PWD/build/control-center"`. The app remains version 0.7.0, build 31. The optimized build and `codesign --verify --deep --strict` passed. This local build is ad-hoc signed.

The full `--self-test` passed with isolated storage. It covers the 28 defaults, all ten numeric aliases, the seven presets on a single UUID-less desktop, preference preservation, system conflicts, partial physical conflicts, owned registrations, probe cleanup, incomplete checks and report invalidation. It also covers background-launch descriptors and read-only appearance initialization. The log is `build/control-center/self-test.log`.

The isolated `--control-center-test` passed. It verifies the same window number across controls/settings/Back, settings capture eligibility, quick-control exclusion, close and reopen. The log is `build/control-center/native-test.log`.

The normal app was launched with disposable `--storage`, shortcuts off and smart panes disabled. UI inspection verified automatic conflict detection at the welcome shortcut step, Customize opening keyboard settings, Back preserving that step, Set up later revealing quick controls, Settings and Command-comma opening General, and persistence of hidden icon/name preferences. The already-running installed copy occupied the 28 tested shortcuts; the test copy reported those occupied combinations without enabling its own shortcuts.

The test copy was quit through its UI. After confirming the process exited and the hidden-icon preference persisted, it was cold-launched again with the same isolated storage. Before any UI inspection, its diagnostic reported a visible panel, shortcuts disabled and zero registered hotkeys. UI inspection then confirmed the controls and persisted General preferences. The test copy was closed after verification; the installed app and personal storage were preserved.

Offscreen `--render-marketing --panels-only` fixtures cover full and compact General and keyboard settings, conflicts, quick controls and setup. These contain fictional data. Renders are under `build/control-center/preview`.

Independent design and correctness reviews found no remaining blockers after fixing stale conflict results following enable/reapply and hidden-icon cold-launch recovery.

## Limits and artifact

No desktop was added, removed or switched. The friend's single-desktop native state and physical number-key delivery remain unverified; the isolated regression coverage is distinct from those checks. Login/service startup was checked using launch descriptors, not by logging out. A CUA focus-switch attempt did not produce an application deactivation, so it does not establish live hide-on-deactivate behavior. The right-click status menu was reviewed in source but not exercised in this UI pass. Accessibility permission and login registration were not changed.

The executable SHA-256 is `93b0e84085b417f32afae47f57afeb518ce3ceaca73ee673ba9d0b6bcb4f34b5`. The local archive is `build/control-center/DeskNames-control-center-preview.zip`. Nothing was installed, published or added to the updater feed.
