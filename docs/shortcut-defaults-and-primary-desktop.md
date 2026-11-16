# Shortcut defaults and the original desktop

This local change follows the November 16, 2026 report that a new user could not change pane layouts until adding a second desktop.

## Behavior

New installations use the owner's 28 configured key bindings. Global shortcuts remain opt-in. Existing saved bindings remain authoritative. **Settings → Keyboard shortcuts → Shortcut options → Restore default shortcuts** replaces the binding set and retains the current on/off setting. Optional desktop jumps, preset selection, and display movement start unbound because some of their old suggestions conflict with the owner's keys.

Number-row and numpad digits share an identity for recording, duplicate detection, display, and pane-range chords. Carbon registers both physical key codes. If another app owns one variant, the working variant remains registered and Settings reports the conflict.

The original macOS desktop can have an empty UUID. Previously, DeskNames accepted that desktop from enumeration but refused its empty identity when choosing or saving pane configuration. A [documented native capture](https://github.com/noobomancer/space-renamer/blob/main/Tests/SpaceRenamerCoreTests/SpacesPlistParserTests.swift) shows this condition even with additional desktops present. A unique unnamed ordinary desktop now receives a display-scoped identity independent of its position or session Space ID. Ambiguous unnamed desktops and unnamed fullscreen Spaces are excluded.

The separate native display alias `Main` resolves to the physical screen UUID only when exactly one native display group and one physical screen exist. This fixes the mismatch between desktop selection and pane placement or capture on that topology.

Legacy empty-ID desktop names and saved arrangements resolve conservatively in memory. Explicit identities win. Contradictory display evidence remains unresolved. Loading does not rewrite preference bytes or saved files.

## Verification

Environment is macOS 26.6.2, build 25G83, arm64. The tested app remains version 0.7.0, build 31, in `build/shortcut-fix/DeskNames.app`.

- A read-only comparison confirmed all 28 default key/modifier pairs match the owner's saved shortcut configuration.
- The isolated desktop fixture invokes the actual `choosePanePreset` path for all seven layouts with one UUID-less desktop. It checks reload, adding another desktop, reordering, changed session IDs, and ambiguity rejection.
- The shortcut fixtures cover all ten digits, recording, persistence, duplicate aliases, mixed input chords, partial conflicts, and registration cleanup. Restore-default tests cover enabled and disabled configurations and existing custom bindings.
- A separate native Carbon check registered both physical keys under the same action ID, then verified that disabling releases both registrations. It did not inject keys.
- An independent review found no blocking correctness issues after adding the legacy nil-desktop-ID display guard.

The first optimized self-test exposed a lifetime assumption in the new cleanup-count fixture. Swift released its hotkey owner before the assertion finished. `withExtendedLifetime` now keeps that fixture alive through the assertion. The optimized focused check passes.

The final `./build.sh "$PWD/build/shortcut-fix"`, isolated `--self-test`, isolated `--pane-session-test`, and `codesign --verify --deep --strict` all exited successfully. The app's bundled third-party notices match the source file. Offscreen onboarding and shortcut settings renders were inspected, including the minimum 640×520 settings size.

The self-test reports `PASS: a sole UUID-less desktop selects and persists all seven pane layouts without creating another desktop; adding and reordering desktops preserves the choice` and `PASS: all ten numpad digits record, persist, detect alias conflicts, register both physical keys, retain pane chords and report partial conflicts`.

The final executable SHA-256 is `742ab637dd824c01ffbaa5b6477b99c934fbc8828b74438be60e4b5657612d48`. The local test archive is `build/shortcut-fix/DeskNames-shortcut-fix.zip`. Test logs and rendered fixtures are alongside it. This archive is not a published update.

## Limits

The current machine's live desktops have UUIDs, so the original empty-UUID condition is verified with isolated native-data fixtures. The friend's machine and physical keyboard delivery remain unverified. No desktop was added, removed, or switched during this work. No installed app, public release, updater feed, or Homebrew package was changed.

Model the Domain kept the default bindings and numeric aliases in explicit maps. Prove It Works required the real selection method, persisted values, native Carbon registration, and rendered settings screens in addition to compilation.
