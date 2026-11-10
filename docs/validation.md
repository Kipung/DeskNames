# Validation record

## Recorded development evidence

The original version 0.5.0 build 22 validation recorded:

- Successful build, strict code-signature verification, and matching built/installed executable hashes.
- Self-tests for matching, old/new layout JSON, exact and intentional offscreen geometry, screen translation and resizing, Dock/menu changes, per-window desktop destinations, equivalent monitor models, eight identical display roles, ambiguity refusal, and monitor preset persistence.
- Shortcut registration, pane geometry, one-shot window births, delayed metadata, and bursts of twelve windows.
- Pane session admission, competing-write protection, early cancellation, and recovery.
- A native manual layout restore of three disposable overlapping windows with verified bounds and front-to-back order. The test used temporary storage and could not enumerate external-app windows.
- A native TextEdit routing test on build 21. A preexisting window stayed on its desktop, a new window moved to Research in the background, the active desktop and frontmost app stayed unchanged, and a later manual move was respected. Build 22 retained this native path and extended destination resolution.
- Existing user layouts remained byte-identical during those tests, and shortcut preferences were preserved.

These are historical test results, not a claim that the environment is unchanged today.

## November 2026 guest regression work

The current guest executable SHA-256 is `22fceaa36f04cfa91eebb9388d6f7fbc859a6f717b2bd576cb4752077825557e`, built on macOS 26.6.2 (25G83), arm64, with the VM unchanged at 4 GiB/two CPUs. The optimized one-job build, strict signature, self-test, pane session test and native layout session test all passed (exit 0). Logs: `/Users/test/Developer/DeskNames-dev-tools/logs/run-20261107T004910Z-ZzA9Ph`. A separate read-only external TextEdit test passed exact-window recovery from a deliberately invalid cached AX token on the serial worker, rejected wrong identities and preserved geometry with isolated diagnostics.

One additional official DeskPad 1.3.2 display was configured at 1280×800, scale 1. macOS and DeskNames detected both displays, and Computer Use operated guest windows on them. Eight fresh TextEdit first transfers passed across preceding candidate revisions, with independent frame/Space traces and unchanged active Space IDs. On the current build, the first Restore previous size after a layout restore succeeded without Refresh; Previous display and a subsequent Restore previous size also succeeded, returning the selected window to its exact virtual-screen frame. This finite sample does not establish an intermittent-error rate.

The visible stacking defect had several concrete causes: the all-windows query could retain stale order; cross-screen raises affected another window of the same app; and `orderFront(nil)` could leave DeskNames' inactive editor below Finder. Capture and verification now use the on-screen list, restore and verify complete order within each native Space, repair only necessary front prefixes, observe each raise, and use `orderFrontRegardless()` for owned windows. Current-build live verification independently proved both display stacks were disturbed before restoring all 14 captured windows. All 14 frames returned exactly and every participating window's per-display order matched, including the editor, Finder and external TextEdit windows. The product diagnostic and independent on-screen assessment agreed. Evidence: `fix-transfer-stack-20261106/stacking-final-final-result.json`. Earlier failed trials remain in the same evidence directory; they are not counted as passes.

The strengthened native layout test independently checks the first restore after proving an actual disturbance. Its constrained-window case verifies complete order even when minimum size prevents one exact frame. Pure tests reject missing windows, duplicates and inversions and cover delayed observations and minimal repair. These fixtures do not replace external-app verification.

Final-build automatic routing **failed** in three live new-window trials (IDs 4669, 4720 and 4746, including keyboard open): the documents stayed on the main Space instead of moving to DeskPad. Existing windows and active Space IDs remained unchanged. No routing transfer result appeared. A later read-only sample found no pressed mouse buttons or Mission Control detector match, but does not establish admission state at birth. The cause is unresolved. An earlier live routing pass on a preceding build remains historical evidence, not a pass for this runtime. The test rule was removed and routing disabled through the GUI.

Persistent guest signing uses a dedicated local certificate. A controlled changed signed bundle and subsequent source recompiles retained Accessibility approval. The user saved access for `/usr/bin/codesign`, with unrestricted application access confirmed off. No global root-trust or normal macOS security protection was weakened. This local development setup is not a notarized distribution pipeline.

Earlier guest GUI trials passed resolution changes, arrangement changes, software display removal/recreation, valid-UUID Space pane/name/color persistence with model sharing off, shortcut recorder flows and selected placement actions. Those paths were not all repeated on the current binary. The built-in Space reports an empty native UUID in this VM; the UI now explains and disables unavailable per-desktop pane persistence there.

Cleanup and remaining GUI checks are currently **blocked**: the native Computer Use service fails to start, including after reset and retry. Five empty fixture windows were closed during a temporary recovery, and their files were archived reversibly. Test layout storage, the extra display and fixture6 remain pending cleanup; the helper again failed on subsequent calls. Saved user text in Transfer 7/8 and the original Untitled document must be preserved. No claim of completed environment restoration is made. Exact current status and private evidence paths: `/Users/test/Developer/DeskNames-dev-tools/VERIFICATION_STATUS.txt`.

Physical monitors, docks, cables, electrical reconnects, simultaneous identical physical monitors and physical hotkeys remain unverified by this software-display trial. Command-drag modifier-phase coverage and full menu-bar/Mission Control visual coverage also remain incomplete.

## Reproducible commands

```sh
./build.sh
codesign --verify --deep --strict build/DeskNames.app
build/DeskNames.app/Contents/MacOS/DeskNames --self-test
build/DeskNames.app/Contents/MacOS/DeskNames --pane-session-test
```

Run the following native test when temporary test windows will not interrupt other work:

```sh
build/DeskNames.app/Contents/MacOS/DeskNames --layout-session-test
```

## Pending checks

- Actual cross-monitor moves and layout restoration with two physical screens.
- Screen reconnects, changed display arrangements, identical monitor pairs, and equivalent replacement units.
- Physical keyboard delivery of global shortcuts. Automated input did not reliably exercise Carbon hotkeys.
- A fresh-install permission flow and wider third-party app coverage.
- OS compatibility outside the recorded development environment.
- Signed and notarized public binary distribution.

See `publication-check.txt` in this directory for the checks repeated while preparing the public repository. Native desktop-changing tests are not implied by a successful build or self-test.
