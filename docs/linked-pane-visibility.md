# Linked pane handle visibility

Decision recorded November 15, 2026. Scope: linked divider presentation and its tests. No preference schema, layout format, version, or release changes.

Before this change, `LinkedPanes.swift` used `.floating` at line 161 and `orderFrontRegardless()` at line 180. Its one-second coverage check ran after the mouse-button guard, excluded elevated windows, shrank cover bounds, and removed absent panes from the required set. An active resize bypassed coverage entirely. These locations refer to the worktree's base revision, `39e1418`; commit `04be693` introduced that coverage check.

The panel now uses normal window level and orders immediately above the frontmost participating pane. The existing 200 ms controller tick checks visibility before the slower discovery scan and the mouse-button guard. A window in front of either participating pane hides the whole grabber when their rectangles overlap. Only this divider's participants and DeskNames divider panels are excluded from blockers; other DeskNames windows still block. All window levels and positive alpha values count as covers. Missing participants or changed pane bounds suppress the handle.

The pure decision returns a window ID suitable for relative ordering, or nil to hide. This applies the Model the Domain principle: visibility and the permitted ordering anchor are one result. Whole-handle hiding is intentionally conservative. Fragment clipping would add separate input, cursor, and accessibility regions to an 8-by-60-point control.

Divider panels cannot become key or main windows and retain the nonactivating style. They disable AppKit animation so ordering out does not leave a fading handle behind. The native fixture investigation observed a removed cover still on screen with alpha 0.431 during its default fade; visibility correctly rejected it until that animation ended.

Starting a resize rechecks visibility. During an owned resize, participant bounds may change between writes, so the decision skips comparison against the original frames. It still checks presence, coverage, normal level, and desktop eligibility. Invalid environments or coverage cancel the session and order the panel out immediately; the existing writer handles rollback and cleanup.

Validation on macOS 26.6.2, build 25G83, Apple Silicon:

- A temporary native fixture reproduced a floating grabber above a cover. Normal-level relative ordering put the grabber below the cover without changing the frontmost application or key window.
- A separate two-process fixture verified relative ordering against the other process's CGWindowID and unchanged focus.
- The original pure function returned visible for a missing neighbor and a half-point overlap. The new pure cases cover those failures, reordered panes, interleaved covers, elevated and translucent covers, moved or resized panes, ignored divider panels, and unavailable environments.
- `DESKNAMES_SIGN_IDENTITY=- ./build.sh` passed. `codesign --verify --deep --strict build/DeskNames.app` passed.
- `./build/DeskNames.app/Contents/MacOS/DeskNames --self-test` passed, including the new pure visibility cases.
- `--pane-interaction-test` passed with normal and floating fixture covers, moved/off-screen panes, simulated desktop state, unchanged focus, linked resize persistence, and constrained-neighbor rollback.
- `--movement-session-test` passed, including stable handle reuse and resizing inferred shortcut layouts. Both native test processes exited with status 0.

Native fixture assertions wait for actual visibility to settle and reacquire panels after invalidation, since a discovery scan may replace them. The initial failing fixture assumptions and diagnostic probes are retained locally under `build/handle-validation/`; they are not part of the release bundle.

Tests run with `HOME`, `CFFIXED_USER_HOME`, and `TMPDIR` redirected under `build/handle-test-home`, in addition to their existing unique preference suites and temporary layout files. The installed app, its running process, and live preferences/layout storage are outside this task.

Physical dragging through a real application switch, actual Mission Control/full-screen transitions, and multiple monitors remain unverified. The native controller test simulates the desktop flags without switching desktops. WindowServer rectangles conservatively hide the whole handle even for a partly transparent or irregularly shaped cover. Visibility polling follows the existing 200 ms timer; native normal-level ordering provides occlusion by windows above both panes between ticks.
