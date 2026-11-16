# Real global shortcut testing

The trusted `--hotkey-soak-test` helper drives a separate, normally started DeskNames process. It posts key down/up events at the HID tap with modifier transitions. It never calls the target's action methods. Suggested pane bindings are Control-Option-F1 through F4. The range tests hold Control-Option across the function-key presses.

Build with an identity already granted Accessibility access, then run:

```sh
DESKNAMES_SIGN_IDENTITY="DeskNames Release" ./build.sh
python3 scripts/test-hotkey-soak.py --report /tmp/desknames-hotkey-report.json
```

The wrapper quits the installed copy before starting the helper and relaunches `/Applications/DeskNames.app` in `finally`. It does not replace the installed app. A recovery journal records process IDs, owned window IDs, and original bounds before changes. The wrapper runs recovery after a helper crash, timeout, or failed cleanup. Both the helper and the tested normal instance use separate absolute `--storage` directories. The normal instance has suggested shortcuts enabled and Four columns selected. Sparkle is disabled for isolated instances.

`--quick` checks fixture and UI setup while skipping the 300-press loop. Its report is not soak evidence.

The report contains WindowServer bounds, action IDs, delivery sequence numbers, and observed latency. `shortcut-result.json` contains the latest accepted request. Isolated instances also write `hotkey-events.jsonl`, which preserves every receipt and accepted completion, and refresh `hotkey-status.json` every 200 ms. A burst may replace a still-running placement. Such observations are `IN_FLIGHT`; each group of 25 requires all Carbon receipts and a successful, settled probe within 1.5 seconds. This tests responsiveness under replacement, not completion of every intermediate animation.

The helper creates disposable TextEdit and Finder windows and uses an already visible Obsidian window if available. It restores original bounds and closes only windows it created. A separate disposable native process receives SIGSTOP/SIGCONT and supplies the modal-sheet and minimized-window cases. Finder browser windows on the current desktop are temporarily minimized for the desktop case, journaled, then restored. The owner’s application processes are never suspended. Exact foreground app/window and mouse-up checks guard each placement key, including both chord endpoints; focus drift aborts and releases synthetic modifiers. These checks reduce interference risk but cannot atomically lock global focus. Current-desktop checks guard activation. No desktop-navigation shortcut is tested.

The synthetic event generator preserves intrinsic function/keypad flags and uses a fresh private event source per event. Overwriting the flags loses Carbon delivery for function and arrow keys. Reusing the HID state source can carry an earlier function flag into Return, Escape, or Space. Pure tests cover both cases. These were injector defects, not lost app registrations.

Secure Input cannot be bypassed. DeskNames reports it independently of the latest action result. The helper briefly enables Secure Input, verifies that status, releases it, and verifies recovery. Display sleep is skipped when unattended wake could require a password.

## Interpretation limits

A successful soak establishes delivery and responsiveness for the recorded run and hardware. It cannot establish that shortcuts never fail over days, across every app, or under physical keyboard input. Physical multi-monitor changes and desktop switching are outside this test. Run `python3 scripts/test-robustness.py` separately for simulated geometry and state-machine coverage.

The full run also invokes `--external-placement-test md.obsidian,com.apple.TextEdit,com.apple.finder` in a separately tracked trusted process before closing fixtures. Every application must supply all 15 passing steps, including frame restoration. Missing coverage fails the soak report.

## Findings and changes

The native click-away case reproduced two separate problems. An `NSPanel` with `hidesOnDeactivate` can retain `isVisible` while its application is inactive. The next toggle therefore reported “closed” instead of reopening. `ControlPanelToggle` now considers application activity, and `showSwitcher` orders out the previous panel before replacement so reactivation cannot resurrect it. Pure cases cover all visibility/activity combinations.

A pane press immediately after a title-bar click could arrive before the asynchronous mouse-up monitor released `.userDrag`, producing “Finish the window operation before changing pane layouts.” `SmartPaneController.prepareForShortcut` clears pending drag capture when the physical mouse button is up. It preserves a held drag and never releases an active placement writer. The state regression exercises those three cases and successful admission after release.

A replacement placement previously inherited a competing request's message until its own writer started. The queue now reports “Working…” immediately; request sequence ownership prevents late completions from overwriting newer diagnostics. Isolated instances retain receipt history so fast delivery is distinguishable from a superseded animation.

Secure Input availability is now polled independently of shortcut delivery and displayed in the panel/settings diagnostic. Real Secure Input enable/disable verifies the cause and recovery without requiring a key to reach DeskNames. Registration validation and handler-install failures mark bindings unavailable rather than presenting a ready state.

Source inspection found no suspension counter. Recording is one optional action; cancellation reapplies the enabled bindings. Carbon handler removal occurs at deinitialization. Binding reapplication unregisters then rebuilds the active set; trust changes rebuild chord monitors without unregistering Carbon bindings. These paths have pure regression coverage. No lost Carbon registration was observed in the native tests, and this work does not establish the historical cause of every owner-reported interruption.

`--storage /absolute/directory` isolates the normally started application, including AppKit's standard defaults, application support, and diagnostics. Sparkle is not constructed in that mode. A subprocess sentinel test verifies that the live application preference domain is excluded; `CFFIXED_USER_HOME` alone did not isolate cfprefsd on this Mac. The robustness script now passes explicit storage too.

## Interrupted-run disclosure

The earlier `verified` run was invalidated by pointer input outside the helper and foreground changes. Its delivery log records five completed actions on Arc at sequences 300, 316, 321, 324, and 325. Arc was not a journaled fixture; its original bounds were not captured, and subsequent pointer input also moved it. Those bounds could not safely be reconstructed. All journaled fixture windows were restored and the installed application was relaunched. The input's human or software origin is unknown. This failure prompted per-key app/window and mouse-state guards, which abort into cleanup rather than retrying activation. Selected failed observations and pointer/delivery evidence are retained in [failed runs](evidence/hotkey-soak-2026-11-15/failed-runs.json).

The Fix Root Causes principle kept observed panel/drag defects separate from injector and interference failures. Prove It Works required real Carbon receipts, WindowServer bounds, and bounded recovery probes instead of direct action calls.
