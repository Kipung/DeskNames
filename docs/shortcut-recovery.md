# Shortcut delivery and operation recovery audit

Scope: dedicated `cx-hotkeys` worktree, based on commit `39e1418`. The reported physical-key failure was not reproduced against the owner's running app. The findings below are source defects and isolated reproductions, not a claim that every reported symptom has one cause.

## Findings and changes

Baseline line numbers in this table refer to `39e1418`.

| Defect and source evidence | Fix and regression coverage |
| --- | --- |
| Main-thread AX discovery reads every app and its child windows synchronously (`WindowManager.swift:408–438`). Only the application element receives a timeout at line 416; child elements do not inherit that element-specific setting. Focus lookup also runs before operation admission (`WindowActions.swift:89`, `main.swift:399–417`). A stalled target can delay the event loop and Carbon delivery. | Install a process-wide AX timeout at NativeWindows initialization, explicitly bound app/window messages, cap candidate scans, and move routine focus, census, routing, linked-pane discovery and external drag lookup to worker queues. Cancellation skips queued reads and stops further candidates. Fake blocked-worker tests prove the main actor remains able to cancel and release work; real AX timeout enforcement remains unverified. |
| Restore awaits NSWorkspace application launch without a deadline (`WindowManager.swift:750–753`). Optional launch prompts default to enabled; the SDK documents that completion can be withheld until dismissal. Task cancellation alone cannot complete that callback wait. | Disable optional prompts and wrap completion in a five-second, exactly-once deadline/cancellation state machine. A late launch callback cannot resume completed work. Timeout ends manual or automatic restore; tests inject absent, duplicate, late, successful and failed callbacks and verify subsequent operation admission. The OS may still finish an already submitted launch later. |
| Operation admission does not check cancellation before the body and leaves `operationTask` populated after completion (`WindowManager.swift:661–686`). Queuing preserves only the body, losing completion/refresh ownership. Automatic restores independently write `.writing` from `pending` (`825–836`), and restore catches consume cancellation (`792`, `801`). | An operation value owns body, flags and completion. One runner checks cancellation around the body and uses deferred cleanup to clear task/state and complete callers, including cancelled-before-start pane drops. Automatic batches use the same runner and stop between desktops. Tests cover queued replacement, cancellation before execution, errors, cleanup callbacks, drag release and batch cancellation. Busy remains held until an actual AX writer/rollback has drained; no watchdog permits overlapping writers. |
| Delivered shortcuts can disappear through missing-desktop/save-layout guards, and the displayed result follows unrelated workspace messages (`main.swift:406`, `WindowManager.swift:728`, `Shortcuts.swift:211`). Trust changes are not freshly gated at dispatch. | Give each delivered shortcut a sequence and retained result. Record refusals for permission, busy, missing focused window/desktop/layout, and superseded operations. Ignore stale completions. Display the latest result quietly in the panel/settings and write the latest `shortcut-result.json` through the existing diagnostic seam. No alerts are added. Pure tests cover refusals, result ownership and permission revocation before the UI poll. |

Asynchronous discovery introduces opportunities for the desktop, target app or gesture to change. Capture now revalidates desktop topology, active desktops on every monitor and screen geometry before replacing a saved layout. Incomplete discovery refuses layout capture and restore matching rather than weakening uniqueness. Drag capture saves WindowServer identity, geometry, pointer and time before awaiting AX, retains movement observed while waiting, and refuses late admission after mouse-up. Pure tests cover these boundaries. Routing still uses its original birth observations and checks for manual moves before transfer.

## Audited paths without an established defect

- The panel does not suspend Carbon registration. Shortcut recording already cancels on Escape/Tab/delete, responder/key loss, dismantling, window detach and view disappearance. No additional suspension flag or speculative resume timer was added.
- No source evidence establishes Carbon registrations being invalidated by wake, session activation, display changes, Space changes or secure input. Registrations were left unchanged; no wake re-registration or polling watchdog was added. Physical delivery under those conditions still needs validation.
- The old focus path queried AX afresh; a stale focused-window cache was not established. New asynchronous focus results reject changed frontmost PIDs, revoked trust and closed window identities. Same-process focus changes during a request remain a native validation case.
- Existing smart-pane missing-mouse-up recovery and linked-pane button-state cleanup were retained. The changed operation completion path additionally guarantees cleanup when a queued drop never starts.
- Existing AX writes already ran on a serial worker with cancellation/rollback ownership. The fix preserves that ownership; it does not declare an in-flight writer finished merely because a timer fires.

## Verification and integration notes

Pure tests use unique preference suites, temporary layout files, injected trust and `includeExternal: false`. The self-test entry point runs its async tests with prohibited activation and does not start AppDelegate. No installed app, running DeskNames process, live preference domain or live DeskNames support directory was used.

Actually run on the final source:

- `DESKNAMES_SIGN_IDENTITY=- ./build.sh`: exit 0; worktree output only, ad-hoc signing.
- `./build/DeskNames.app/Contents/MacOS/DeskNames --self-test`: exit 0, all 15 PASS groups, including the four new recovery/delivery groups.
- `codesign --verify --deep --strict ./build/DeskNames.app`: exit 0.
- `git diff --check`: clean. Bundled THIRD_PARTY_NOTICES matches the source; source LICENSE and notices are unchanged.
- Independent source review of operation cleanup, launch completion, asynchronous capture and cancellation: no remaining must-fix findings.

Native keyboard delivery, secure input, sleep/wake, physical monitors, real hung target apps, launch prompts and drag sessions require a separate authorized session. Simulated geometry and injected timeouts do not validate those native behaviors.

Integration touches shared action entry points in WindowManager, main, SmartPanes, LinkedPanes, routing and layout capture. Preserve the operation completion ownership and capture-before-await ordering when resolving sibling-worktree conflicts. Routine discovery now completes asynchronously; slow apps may cause a conservative incomplete-discovery refusal. Save/restore must retain that refusal to protect existing layouts and window matching.

## Real-key follow-up

The November 15 trusted helper run, subsequent panel and released-drag fixes, and bounded native coverage are recorded in [hotkey-soak.md](hotkey-soak.md). Those results supersede the unverified-input limitation above for the tested environment. They do not establish indefinite reliability, physical keyboard delivery, sleep/wake, or multiple-monitor behavior.
