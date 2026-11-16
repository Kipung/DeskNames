# Third-party window discovery and placement

Release-signed, LaunchServices-launched DeskNames now verifies real placement in seven applications, including Obsidian. The owner's original Obsidian failure did not reproduce. A real TextEdit range-shortcut failure did reproduce and is fixed. The earlier discovery investigation below remains historical evidence, not a diagnosis of the original Obsidian report.

## Trusted placement verification, November 15, 2026

Tested on macOS 26.6.2 (25G83), Apple Silicon, one physical display with a 5120×1409-point work area at scale 1. The app remains version 0.7.0, build 31. Executable SHA-256: `58af84e82b72bc23e63b099d3edadd9de7c41714bd3ecf5c89623ed856d28b15`.

| Application | Bundle ID | Final live result |
| --- | --- | --- |
| Obsidian | `md.obsidian` | 15/15 passed |
| VS Code | `com.microsoft.VSCode` | 15/15 passed |
| Spotify | `com.spotify.client` | 15/15 passed |
| Discord | `com.hnc.Discord` | 15/15 passed |
| Arc | `company.thebrowser.Browser` | 15/15 passed |
| Finder | `com.apple.finder` | 15/15 passed |
| TextEdit | `com.apple.TextEdit` | 15/15 passed after the range fix |
| Ghostty | `com.mitchellh.ghostty` | Unavailable: running, no on-screen window on the current desktop |

Bundle IDs were confirmed with `osascript -e 'id of app "Name"'`, including Terminal (`com.apple.Terminal`). Computer Use refused access to Ghostty, so no terminal fixture was created. This is a coverage gap, not an app placement refusal. TextEdit initially had no on-screen document. Its startup Open panel was cancelled and one empty Untitled fixture was opened without entering content.

Each successful app run checked asynchronous focused discovery, Four columns panes 1 through 4 at gap 0, rapid 3→4 and 4→2 chords, both chords after the first placement settled, left half, right half, maximize, the production Command-drag pointer-discovery path at a title-bar point, original-frame restoration, and accessibility-mode preservation. Target and actual bounds were checked against the captured WindowServer identity. All recorded position and size writes in the final run returned AX error 0. The seven original frames were restored exactly within the production one-point tolerance. Initial and final readable Enhanced UI and Manual Accessibility values agreed.

The committed [evidence summary](evidence/external-placement-2026-11-15.json) contains each requested and actual frame, elapsed time, AX write error sets, app metadata, before-fix TextEdit failures, and divider ordering. Complete per-write traces and per-step AX attribute errors are retained locally in `build/external-placement-audit/desknames-external-final.json`. Reports omit window titles and document content.

### Confirmed root cause and production fix

TextEdit exposed a 66×20 normal-level WindowServer window, ID 38460, above its 603×505 document, ID 38431. The former `NativeWindows.frontmostWindowIdentity()` selected the first app-owned visible WindowServer window without applying the operation size threshold. `PaneRangeChord.resolve()` compared that ID with the AX-focused document ID, found a mismatch, and discarded the first pane. Both rapid chords consequently moved only to their final endpoint, despite successful AX writes. The same identity mismatch could also clear a settled chord during polling.

`WindowDiscovery.shortcutIdentity` in `Sources/DeskNames/WindowDiscovery.swift:80` now excludes normal-level candidates that fail the existing greater-than-80×50 operation bounds policy. `NativeWindows.frontmostWindowIdentity` in `Sources/DeskNames/WindowManager.swift:248` uses that selector. Elevated windows and document-sized dialogs still block/reset the chord. Focused-discovery fallback and pointer hit selection retain their conservative foremost-window behavior. The operation inspector shares the same bounds predicate, preventing drift between its policy and the shortcut hint.

Pure regressions in `SelfTests/PaneRangeTests.swift` reproduce the measured decoration/document ordering, exercise pending range resolution, preserve the settled anchor, retain small elevated blockers and larger normal dialogs, and retain the conservative focused fallback. Existing tests still check real document switches and stale request cleanup. The final trusted TextEdit run verifies both chord orders in rapid and settled forms.

No Obsidian-specific exception, Manual Accessibility enablement, AX timeout change, or frame-write ordering workaround was justified. Obsidian was AXStandardWindow with both accessibility-mode flags false and passed every requested placement. The original report may depend on a different window state or shortcut-delivery condition; this run does not establish its historical cause.

### Real divider verification

Three disposable Finder windows were opened, with WindowServer IDs 38384, 38385, and 38386. The first two were placed in adjacent halves through `performWindowAction`. The real `LinkedPaneController` census and visibility logic produced handle 38491 at layer 0, rank 29, above neighbors at ranks 30 and 31. A third Finder window was placed over the seam and raised: it occupied rank 29 and no seam handle remained on screen. Raising both neighbors restored the same normal-level handle above them. All three original frames were restored before fixture closure. Finder subsequently reported only its two preexisting windows. The empty TextEdit fixture was closed through its close button; the UI service timed out on the subsequent state read, and an independent WindowServer check found none of the four fixture IDs on screen. No document was saved. The committed evidence includes the three ordered window lists and bounds.

### Repeat the checks

The new modes dispatch before normal application services. They use a UUID preference suite, temporary layout storage, and temporary diagnostics. They never initialize the normal updater or migration path, request permissions, or call desktop navigation. The app must already have an on-screen ordinary window on the current desktop. Missing apps launch through NSWorkspace without activation, with a bounded wait. Activation is refused when the focused/main window cannot be established on screen. This preflight reduces desktop-switch risk; a subsequent desktop-identity check detects an unexpected activation-induced switch and stops placement. It does not guarantee that macOS activation can never change desktops, and the test never switches back automatically. No such change occurred in the final runs. Original frames are restored after step failures. Process termination or a crashed target can still prevent restoration.

```sh
DESKNAMES_SIGN_IDENTITY="DeskNames Release" ./build.sh
open -n -W --stdout /tmp/desknames-placement.log --stderr /tmp/desknames-placement.log \
  build/DeskNames.app --args --external-placement-test \
  md.obsidian,com.microsoft.VSCode,com.spotify.client,com.hnc.Discord,company.thebrowser.Browser,com.apple.finder,com.apple.TextEdit,com.mitchellh.ghostty \
  --report /tmp/desknames-placement.json
```

Use temporary output paths. Redirecting LaunchServices output directly to this external-drive checkout failed with `-10810`; a run writing its report there blocked in Foundation's file open. That test process was terminated while saving its report after its placement/restoration phase. Retrying with `/tmp` output succeeded. No TCC reset or permission grant was made. A valid signature alone was not used as evidence of trust; the in-process report records `trusted: true`. `open -W` does not propagate the app's test exit code, so inspect the report and printed results.

For divider checks, create three disposable Finder windows, record their IDs, and run:

```sh
open -n -W --stdout /tmp/desknames-dividers.log --stderr /tmp/desknames-dividers.log \
  build/DeskNames.app --args --external-divider-test ID1,ID2,ID3 \
  --report /tmp/desknames-dividers.json
```

The divider mode only accepts three distinct Finder windows on the current desktop. It restores their original frames. The operator who created them must close those exact fixture windows afterward.

### Other verification and limits

The final release-signed build, strict deep signature verification, notice comparison, and `git diff --check` passed. `python3 scripts/test-robustness.py` passed self-test, pane-session, pane-interaction, and movement-session modes. Its direct-shell window-refresh mode failed only at its documented Accessibility precondition. Launching that same mode through LaunchServices passed trust and then refused because no `DeskNames Transfer ` TextEdit fixture was present; its recovery assertions remain unverified.

These are real external-app controller calls and real pointer discovery, not physical keyboard delivery or a complete mouse Command-drag gesture. The normal installed DeskNames process remained running and did not interfere with the observed checks. The installed bundle, TCC settings, live preference domain, and saved layouts were not modified by the test code. No desktop navigation, installation, push, or publication occurred. Small-screen app minimum-size constraints, other app window states, multiple physical monitors, and OS versions other than this Mac remain unverified.

The Model the Domain principle led to per-app/per-step report records and one shared bounds predicate. Fix Root Causes led to correcting the identity hint rather than adding a TextEdit exception. Prove It Works required observing failed and repaired real TextEdit chords, successful Obsidian placements, and WindowServer divider order.

## Earlier discovery investigation

## Findings

The starting revision is `39e1418`.

- `Sources/DeskNames/WindowManager.swift:213` rejects every subrole except `AXStandardWindow`. The census repeats this restriction at line 419. The first check serves Command-drag, focused shortcuts, and operation preflight.
- `Sources/DeskNames/WindowActions.swift:89-95` requires `AXFocusedApplication` and `AXFocusedWindow`. There is no main-window or frontmost-process fallback.
- `Sources/DeskNames/WindowManager.swift:188-197` abandons pointer discovery when hit testing fails or the hit lacks `AXWindow`.
- Titles are already optional. The census substitutes an empty title, and direct discovery does not read one.
- Placement already verifies WindowServer geometry, then retries position, size, position. Animation already shrinks before moving and grows afterward. Changing that order has no supporting evidence here.

These source checks establish discovery limitations. They do not establish which limitation caused the owner's Obsidian report.

## Decisions

One metadata policy now serves census and operation discovery. Actual subrole read failures are refusals, not missing metadata. Standard windows remain eligible without relying on settable hints. Missing, empty, and `AXUnknown` subroles require an `AXWindow` role and confirmed movable position. Explicit auxiliary subroles, modal windows, attached sheets, and fullscreen windows remain excluded. The census can retain minimized windows for layout restoration; direct operations cannot select them. Explicitly observed but rejected identities leave the census cache. Only omitted identities retain the inactive-Space fallback.

Focused discovery uses the captured frontmost process. A genuinely missing focused-window attribute can fall back to the main window or the foremost visible WindowServer identity belonging to that process. An elevated-layer window blocks fallback to a document below it. A present but ineligible focused window, an AX read error, or a changed frontmost process causes refusal. Fallback never selects the first eligible document behind a dialog.

Pointer fallback selects the foremost WindowServer window at the pointer before checking eligibility. It requires an exact AX window ID and owner match. Blocking auxiliary windows and unmatched identities cause refusal. It does not infer identity from a title or a similar frame.

The existing exact-identity checks, AX messaging deadlines, placement order, and scoped Enhanced UI restoration remain. Failure diagnostics now explain focused-discovery refusal. The implementation does not activate another application or change desktops.

No automatic `AXManualAccessibility` enablement was added. [Electron documents this attribute](https://github.com/electron/electron/blob/main/docs/tutorial/accessibility.md) as a way to enable its accessibility features, but this investigation did not demonstrate that it was needed for window placement. No geometry-based substitute for `_AXUIElementGetWindow` was added. Ambiguous identity must remain a refusal.

## Live observations

The machine reports macOS 26.6.2, build 25G83, on November 15, 2026.

The standalone Swift interpreter reported `trusted=false`. Reads of Obsidian's `AXWindows`, `AXFocusedWindow`, `AXMainWindow`, `AXEnhancedUserInterface`, and `AXManualAccessibility` all returned `-25211`. The same read failures occurred for VS Code and Spotify. These errors describe the probe's permissions, not an application refusing placement.

A Terminal-hosted Swift attempt failed with AppleEvent timeout `-1712` and produced no probe result. Computer Use rejected Terminal access. No permission grants or security-setting changes were attempted.

Read-only inspection through the trusted Computer Use service identified standard windows in Obsidian 1.15.1, VS Code, and Spotify. All three pass the old subrole check in that observed state. This service did not expose the raw focused/main attributes, settable results, window ID lookup errors, or frame-write results needed to test the complete placement path. Discord inspection timed out. Chrome, Firefox, and Slack were not installed in `/Applications`.

No Obsidian frame writes were attempted, so there was no probe frame to restore. No vault content was changed. The installed DeskNames app, running DeskNames process, live preference domain, and saved layouts were outside the test scope.

## Reproduce the remaining live check

`Tools/window-accessibility.swift` prints window metadata, attribute errors, identity results, and frame-write verification without printing window titles or document content. It refuses to proceed when the host lacks Accessibility trust. It does not launch applications or request permissions.

From an already trusted host, run:

```sh
swift Tools/window-accessibility.swift md.obsidian com.microsoft.VSCode com.spotify.client
swift Tools/window-accessibility.swift md.obsidian --move-obsidian
```

The optional move applies a small inset to the focused standard Obsidian window, checks the WindowServer result, then restores and verifies its original frame. It reports AX errors and returns failure if movement or restoration fails. It never changes accessibility modes or vault content.

## Verification

The baseline ad-hoc build and `--self-test` passed. Tests used `CFFIXED_USER_HOME` under this worktree's `build/self-test-home`; fixture preference suites and layout files remain isolated.

The final `DESKNAMES_SIGN_IDENTITY=- ./build.sh` passed. The final executable passed `--self-test` with the same isolated user home. `codesign --verify --deep --strict` passed, and the bundled third-party notices matched the repository file.

The new self-test output includes:

```text
PASS: shared window eligibility, titleless move-capable discovery, conservative CG identity fallback, focused refusal and frontmost-owner recheck
```

Four mutations in disposable copies under `build/discovery-tests` failed the regression checks as intended. Restoring the strict subrole gate and refusing missing focus both failed. Swallowing subrole errors failed with `An AX error must not admit an auxiliary window as an unknown subrole`. Retaining rejected cache entries failed with `A window refused by the current census must not return from cache`.

The final standalone probe compiled and exited 2 with `trusted=false` and its explicit permission refusal. This verifies the probe's safe refusal path only.

Pure tests exercise policy and fallback selection. They do not establish physical shortcut delivery, actual Command-drag behavior, or placement compatibility with a specific application or toolkit. Electron, Chromium, Qt, and Java live placement remain integration checks.

## Review and execution notes

Independent review found two defects in the initial implementation. AX subrole errors could be mistaken for absent metadata, and the census cache could resurrect a newly rejected window. The final implementation distinguishes AX errors and reconciles observed identities before retaining omitted windows. Pure tests exercise both corrections.

The Fix Root Causes principle kept the unverified Obsidian attribution separate from source-confirmed discovery defects. Model the Domain put eligibility and foreground identity selection in shared pure code. Prove It Works required running the built self-test executable and checking actual probe trust rather than inferring it from the installed app's approval.

One implementation delegate violated the worktree-only rule by compiling a temporary pure-test executable in a `mktemp` directory matching `/tmp/desknames-discovery.*`. The delegate did not remove it or record its generated suffix. The root reran the check inside `build/discovery-tests` and did not treat the outside run as release evidence. This deviation did not involve DeskNames settings, the installed app, or vault contents.

A second independent review accepted both production corrections and requested explicit AX error-classification coverage. That coverage is included in the final passing self-test suite. The final source review found no additional concrete correctness issue. Local build logs and the decision trail are retained under `build/window-compatibility-audit`.
