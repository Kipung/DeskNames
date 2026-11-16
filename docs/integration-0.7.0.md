# DeskNames 0.7.0 integration

The release combines the five robustness branches on `v0.7-robustness`. The integration is local only. It does not publish a release or replace the installed app.

## Merge decisions

- The range merge conflicted in `LinkedPanes.swift`, `PaneInteraction.swift`, `PaneInteractionTests.swift`, and `main.swift`. It retains asynchronous placement, bounded AX discovery, shortcut result delivery, and completion-owned cleanup. Span occupants use their complete pane set. Handles remain non-key normal-level `PaneHandlePanel` instances presented relative to `PaneHandleCover.anchor`. The old cover assertions are all represented in `PaneHandleVisibilityTests`.
- Range input records an immutable request before discovery starts. Requests retain the first pane, modifier session, foreground process/window identity, and generation/sequence. The existing placement queue drains cancelled writers and retains the latest endpoint. Late discovery or failure cleanup cannot recreate a released chord or clear newer input. A single press has no chord delay. WindowServer identity, desktop/geometry and modifier checks replace synchronous AX polling.
- The stubborn-app merge conflicted in `WindowActions.swift` and `WindowManager.swift`. Focused and main-window fallback, exact foreground identity, eligibility and rejected-cache eviction now apply to the bounded async paths used by shortcuts and Command-drag. A present but ineligible focused window remains a refusal. The hotkey census result was renamed `WindowCensus` to avoid colliding with the stubborn branch's `WindowDiscovery` policy.
- The install merge conflicted in workspace tests, the control panel and test dispatch. The resolution retains isolated fixtures, shortcut feedback, login controls, the async test entry point and all new test suites. Onboarding eligibility initializes before preference-writing models. Spacing migration runs during normal startup before pane models load.
- The owner's explicit override restores the permission implementation and comment from `39e1418`. When untrusted, a permission request resets only the current DeskNames bundle identifier's Accessibility record, then prompts. The tests do not invoke it.
- `.audit/` is removed. Design notes remain. Version metadata is 0.7.0, build 31. Preexisting untracked `.claude/` files remain outside these commits.

The Model the Domain principle led to one request state inside `PaneRangeChord`, rather than a second placement queue or independent controller flags. A mutable coalescing placement task was considered and rejected because it would change writer and result ownership unnecessarily.

## Defects found in combined review

1. Cancelling first-press discovery lost the range anchor. Synchronous input capture and generation-checked completion fix it.
2. Chord timer polling reintroduced main-thread AX discovery. It now checks modifiers, WindowServer identity, screen geometry and desktop state without AX reads.
3. The stubborn branch's fallback existed only on the synchronous path. The actual async shortcut and drag paths now share its eligibility and exact-identity policy.
4. Newly ineligible windows could survive in the census cache. Observed identities now invalidate cached entries before accepted snapshots are merged.
5. Eligibility inspection could traverse an unbounded AX child tree and ignore cancellation. Metadata reads, child roles and async refresh now share deadlines and cancellation checks.
6. Eligibility timeouts bypassed census completeness accounting. Errors now refuse the window and mark the census incomplete, preventing partial layout capture.
7. Enabling shortcuts before Accessibility approval could retain stale chord monitors. Trust transitions remove and recreate monitors once; repeated polling does not duplicate registration.
8. Movement fixtures assumed synchronous refresh and immediate linked-handle discovery. They now await discovery while keeping the original geometry, history, stable-handle and cancellation assertions.
9. The pane-session fixture allowed external discovery by default. It now explicitly disables external windows and uses its existing isolated preference suite and layout file.

Independent review checked the combined diff and identified the metadata budget and incomplete-census defects. Comment review requested no style-only changes. The owner-required permission comment remains.

## Verification

Run `./build.sh`, then `python3 scripts/test-robustness.py`. The runner creates a unique directory under `build/`, redirects `CFFIXED_USER_HOME` and `TMPDIR` separately for each mode, saves complete output and returns nonzero for any failure. Every fixture uses a unique preference suite and temporary layout path. Normal startup, updater and migrations are not entered by these test modes. No test switches desktops, invokes permission reset, uses the installed app, or controls its process.

Final verification ran on November 15, 2026, macOS 26.6.2 (25G83), Apple Silicon. `./build.sh`, `codesign --verify --deep --strict`, `git diff --check`, and byte comparisons of bundled third-party notices all exited 0. Info.plist reports version 0.7.0 and build 31. The executable SHA-256 is `67cef7c7e5dd128be8b780b98a0ad3f3b5c297d2211c3d297cf32a5a7dfced83`.

Complete logs and isolated storage are in `build/robustness-tests-oq1yg_iu/`. Actual final output includes:

```text
RESULT --self-test: exit 0
RESULT --pane-session-test: exit 0
RESULT --pane-interaction-test: exit 0
RESULT --movement-session-test: exit 0
FAIL: Accessibility is required for the external refresh test.
RESULT --window-refresh-test: exit 1
```

Selected behavioral evidence from the final executable:

```text
PASS: range retarget during suspended discovery preserves first pane, drains cancelled work, and releases admission
PASS: eligibility timeout marks census incomplete; metadata cancellation and deadlines stop child traversal
PASS: native fixture covers, immediate visibility refresh, movement, off-screen panes, simulated full-screen/Mission Control state, and unchanged focus
PASS: native spanning-window linked resize preserves the whole span and releases admission
PASS: latest placement replaces old requests, explicit cancellation clears the queue, interrupted snaps preserve restore history, shortcut neighbors resize together with stable handles
DISPLAY: 5120×1409 usable points, scale 1.0, maximum refresh 144 Hz
```

The test runner exits 1 because the built binary lacks Accessibility trust for the external refresh test. That mode fails before external discovery; its stale-token recovery assertions did not execute. The trust check was not changed, bypassed, or treated as a pass. When trusted, this existing mode also requires a disposable TextEdit window titled with the `DeskNames Transfer ` prefix. No external fixture was opened during this integration.

The local native fixture modes use their existing injected trust and local windows. They establish native geometry, cancellation, handle ordering and cleanup, not external-app AX permission or compatibility. The initial movement-mode assertion failure came from fixtures that assumed synchronous discovery; all original assertions remain and pass after the API update.

Independent source review approved the final metadata classification fix after checking the stale-child regressions. Physical key delivery and full shortcut dispatch into an external app, actual Command-drag in stubborn apps, fresh install/Gatekeeper/TCC approval, login/logout, actual Mission Control/full-screen transitions and multiple physical monitors remain unverified. No desktop-changing test ran. `release/`, root license/notices, the installed application, its running process and live preference/layout storage were not modified by this integration.
