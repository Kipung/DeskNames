# Window movement verification — November 10, 2026

Build 24 unifies shortcut and Command-drag geometry and reduces avoidable delays in frame writes. The final build is installed and live TextEdit placement checks passed. Native fixture and single-app checks do not establish that every app animates smoothly.

## Changes

- Pane and shortcut targets use the detected usable display area, backing scale, configured gap, and applicable custom divider ratios. No monitor resolution is encoded into target placement.
- Transitions use distance-sensitive ease-out, pixel alignment, and display-frame deadlines. Slow writes skip elapsed animation frames rather than adding a full fixed sleep after every write.
- The latest placement replaces pending placements. Original restore geometry survives interruption. Pointer interaction cancels an unfinished placement.
- Frame writes reuse an identity-validated AX reference. Interactive completion avoids a synchronous AX window census.
- Shared divider panels survive idle scans and recognize standard shortcut layouts even when another pane guide is selected. Neighboring writes are batched; layout persistence and rollback remain transactional.
- Animation and linked-drag sessions temporarily suppress Enhanced UI only if already enabled, then restore it on completion, error, or cancellation. This happens once per session rather than between every animation frame. This addresses a competing-native-animation mechanism documented by [Rectangle](https://github.com/rxhanson/Rectangle/blob/main/TerminalCommands.md#control-enhanced-ui-handling). This behavior was independently implemented; no source was copied.

## Validation

All tests use disposable native windows and isolated preference/layout storage:

- `--self-test`: geometry agrees between shortcuts and pane guides across translated, negative-origin, ultrawide, portrait, and Retina configurations; adaptive durations and frame deadlines.
- `--movement-session-test`: newest placement wins, explicit cancellation clears the queue, interrupted movement retains original restore geometry, shortcut halves produce shared handles under a thirds guide, handles persist between scans, both neighbors resize while maintaining the gap.
- `--pane-interaction-test`: four-column placement, cancellation, linked resizing persistence, and constrained-window rollback.
- `--pane-session-test`: drag admission, stale sessions, cancellation, and operation recovery.
- `--layout-session-test`: exact native geometry and overlapping-window stacking, including app constraints.

The connected display reports 5120 × 1409 usable points, scale 1, and maximum refresh 144 Hz. This is detected capability, not a measured achieved animation frame rate. Physical multi-display movement, display disconnects during motion, and sustained real keyboard/Command-drag pacing remain unverified.

## Live verification

The initial interim build reached TextEdit's requested third and fourth-column positions but took 1.411 and 1.551 seconds, including compatibility retries. This prompted investigation of competing native animations and per-frame overhead.

The installed final artifact has SHA-256 `781eb8b3238418986ff15e63d44d6bd01c7ea10bfee4f5bf9c7e79607dd03d3d`. Signature verification passed. Accessibility was renewed and the running app was restarted from `/Applications/DeskNames.app`.

| TextEdit action | Entire frame session | Submitted frame batches | Compatibility retries |
| --- | ---: | ---: | --- |
| Left third from fourth column | 0.316 s | 8 | No |
| Fourth column from left third | 0.251 s | 8 | No |
| Top-left quarter from fourth column | 0.259 s | 9 | No |

Times include the frame session's setup and cleanup, but exclude shortcut delivery and operation preflight. These are individual diagnostic samples, not a benchmark or measured display FPS. Final window geometry was verified by the app and successful completion was observed in its UI. The latest samples reported zero Enhanced UI adjustments (the attribute was not enabled), so these samples do not independently verify restoration of an enabled external app's mode or isolate that mechanism's contribution. Restoration on failure/cancellation remains structurally scoped and awaited.

One interim test snap reached Claude while the window picker was settling. After explicit approval, Restore previous size completed successfully for Claude before the app restart. The blank TextEdit fixture was closed. No document contents were changed.

Personal preferences were compared structurally after decoding JSON preference blobs and shortcut binding dictionaries; they were unchanged. Saved layout bytes were unchanged. The UI confirms linked resizing is currently off; enable **Smart panes → Resize neighboring panes together** to use shared handles. Rectangle remains stopped. Real pointer-driven shared-divider dragging, physical Command-drag/shortcut feel, and multi-monitor hardware behavior remain manual coverage gaps; shared-edge coordination and rollback passed the isolated native tests.
