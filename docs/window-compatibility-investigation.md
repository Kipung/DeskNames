# Third-party window discovery

This change improves discovery for applications with incomplete window accessibility metadata. The reported Obsidian failure remains unconfirmed on a trusted placement client. Do not describe this investigation as a verified Obsidian fix.

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
