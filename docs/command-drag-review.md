# Command-drag and motion review — build 25

Validated November 10, 2026. Version 0.5.0, build 25.

## Findings and changes

The user clarified that Command-drag left a narrow border. Code's pane spacing was 12 points; with explicit approval it was saved as 0 points. This is a runtime preference, not a global default change. Pane geometry still derives from the actual monitor work area and backing scale.

A read-only Claude Code review ran with model `claude-opus-5-5`, restricted to Read/Glob/Grep and no MCP servers. The user explicitly approved sending DeskNames source and project documentation to Anthropic; runtime preferences, saved layouts, credentials and other projects were excluded. The reviewer examined drag/overlay behavior and frame-write/linked-resize behavior. Its review informed the changes; it did not perform the live tests or edit the app.

- Clear the retained overlay presentation on hide; suppress opening geometry animations and explicitly size the hosting view to the detected work area.
- Animate cell highlights without implicitly animating cell bounds. Update hover from drag events and resolve the target again at mouse-up.
- Stop cancelling placement on every unrelated mouse-down. Admit a new drag after a prior placement finishes.
- Avoid diagnostic argument evaluation when drag diagnostics are disabled.
- Serialize Accessibility writes per app so separate apps can receive neighboring-window updates concurrently. Reuse the existing identity check's frame and skip unchanged attributes.
- Shrink dimensions before moving, then grow afterward. The old size-first order caused macOS to clamp growth at the old position.
- Use smoothstep easing and measured write latency. Finish directly if a write exceeds two display intervals, avoiding continued coarse animation. Allow up to 120 ms of settling before the existing compatibility retry.

## Reproduced live bug

A blank TextEdit fixture started at `(692,104,603,505)` in Accessibility coordinates. Left third requested `(0,31,1707,1409)`. Before the ordering fix, the app initially lost 73 points of height at its old Y position, then needed a correction. That run took 541 ms. The final build reached the same target without a correction in 96 ms. These are individual diagnostic observations, not a statistical benchmark.

## Final live observations

One physical monitor: 5120×1409 usable points, scale 1, maximum refresh reported as 144 Hz. All rows below had actual bounds equal to target bounds and no compatibility fallback.

| Action | Target `(x,y,width,height)` | Elapsed | Frame batches | Behavior |
| --- | --- | --- | --- | --- |
| Left third from original fixture | `(0,31,1707,1409)` | 96 ms | 2 | Direct finish after slow resize |
| Right third from left third | `(3413,31,1707,1409)` | 260 ms | 21 | Animated position-only move |
| Fourth column from right third | `(3840,31,1280,1409)` | 99 ms | 3 | Direct finish after slow resize |
| Bottom-right quarter | `(2560,736,2560,704)` | 112 ms | 2 | Direct finish after slow resize |

The blank fixture was restored to its original size and closed. DeskNames remains installed with renewed equivalent Accessibility approval. Rectangle was not running. Preferences compared semantically against the post-approved-zero-spacing baseline had no further changes; saved layouts were byte-identical.

## Automated checks

All passed on the final executable:

- `--self-test`: geometry, monitor mapping, shortcuts, persistence and other existing pure tests, plus bounded-app resize-order cases and adaptive timing decisions.
- `--movement-session-test`: local native overlay bounds before/after a result message, cleared hidden state, final-pointer drop targeting, unrelated-click behavior, retargeting, restore history and neighboring-pane resize.
- `--pane-interaction-test`: four native columns, cancellation with no delayed writes, shared resize persistence and constrained-neighbor rollback.
- `--pane-session-test`: native drag admission, permission refusal, competing-write refusal, desktop/session cancellation and recovery.
- `--layout-session-test`: real overlapping native fixture restoration and constrained placement reporting.

Build and signature verification passed. Installed executable SHA-256: `211156a04bed308fc5f071d63000fe358df0b568d602f38fad204a31c9db6cea`.

## Limits

These results establish exact placement for the measured TextEdit actions and correctness of the native fixtures. They do not prove uniform animation quality in every third-party app, 144 rendered frames per second, or simultaneous external-app divider motion. Linked resizing remains disabled in the user's settings. The fresh/post-result overlay check validates hosting bounds after layout, not a captured first rendered frame. After installing the final build, the user physically tested Command-drag and confirmed: “Fills correctly and feels better.” This confirms their observed gesture, not every app or monitor. Multiple-monitor, reconnect, identical-monitor and broad OS compatibility coverage remains outstanding. Slow resizing intentionally finishes directly; it is not described as a smooth interpolated resize.
