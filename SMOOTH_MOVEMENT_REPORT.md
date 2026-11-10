# Window movement verification — November 10, 2026

Build 24 unifies shortcut and Command-drag geometry and reduces avoidable delays in frame writes. The final external-app animation adjustment still needs a live check; do not interpret passing native fixture tests as proof that every app animates smoothly.

## Changes

- Pane and shortcut targets use the detected usable display area, backing scale, configured gap, and applicable custom divider ratios. No monitor resolution is encoded into target placement.
- Transitions use distance-sensitive ease-out, pixel alignment, and display-frame deadlines. Slow writes skip elapsed animation frames rather than adding a full fixed sleep after every write.
- The latest placement replaces pending placements. Original restore geometry survives interruption. Pointer interaction cancels an unfinished placement.
- Frame writes reuse an identity-validated AX reference. Interactive completion avoids a synchronous AX window census.
- Shared divider panels survive idle scans and recognize standard shortcut layouts even when another pane guide is selected. Neighboring writes are batched; layout persistence and rollback remain transactional.
- AX frame transactions temporarily suppress Enhanced UI only if already enabled, then restore it. This addresses a competing-native-animation mechanism documented by [Rectangle](https://github.com/rxhanson/Rectangle/blob/main/TerminalCommands.md#control-enhanced-ui-handling). This behavior was independently implemented; no source was copied.

## Validation

All tests use disposable native windows and isolated preference/layout storage:

- `--self-test`: geometry agrees between shortcuts and pane guides across translated, negative-origin, ultrawide, portrait, and Retina configurations; adaptive durations and frame deadlines.
- `--movement-session-test`: newest placement wins, explicit cancellation clears the queue, interrupted movement retains original restore geometry, shortcut halves produce shared handles under a thirds guide, handles persist between scans, both neighbors resize while maintaining the gap.
- `--pane-interaction-test`: four-column placement, cancellation, linked resizing persistence, and constrained-window rollback.
- `--pane-session-test`: drag admission, stale sessions, cancellation, and operation recovery.
- `--layout-session-test`: exact native geometry and overlapping-window stacking, including app constraints.

The connected display reports 5120 × 1409 usable points, scale 1, and maximum refresh 144 Hz. This is detected capability, not a measured achieved animation frame rate. Physical multi-display movement, display disconnects during motion, and sustained real keyboard/Command-drag pacing remain unverified.

## Live check and remaining work

An interim build 24 was installed and Accessibility renewed. TextEdit reached the requested third and fourth-column positions. Diagnostic completion times were 1.411 and 1.551 seconds, both using compatibility retries despite planned durations of 0.170 and 0.222 seconds. These exposed the additional external AX animation issue; they are not performance success measurements. The final Enhanced UI adjustment and shared-divider release change were subsequently built and tested locally and still require installation and another external-app check.

One test action reached Claude while the window picker was settling. Automatic approval review blocked using Restore previous size to undo that snap. Explicit user approval was requested. The running interim app is intentionally retained so its original-frame history remains available for the undo; final restart/install follows that decision. No document contents were changed. The blank TextEdit fixture was closed.

Personal preferences were compared structurally after decoding JSON preference blobs and shortcut binding dictionaries; they were unchanged. Saved layout bytes were unchanged. Linked resizing remains opt-in and currently off. Rectangle remains stopped.
