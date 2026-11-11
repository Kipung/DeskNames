DeskNames 0.5.0 preview. Desktop names, smart panes, window layouts, and switching.

OPEN
Installed locally at /Applications/DeskNames.app. Open it there, or click the DeskNames menu bar item. Closing the editor leaves the app running; Command-Q quits it.

ACCESSIBILITY
Window management and desktop switching require DeskNames to be enabled under System Settings → Privacy & Security → Accessibility. The Layouts & windows page has an Open Accessibility settings button. Accessibility permits reading window titles, resizing/repositioning windows, and generating desktop-switch and drag events. No Screen Recording permission is requested. With access off, window controls are disabled. If macOS Settings crashes, restart Settings and check the switch again. A rebuilt ad-hoc-signed app can require permission to be granted again. If the switch is on but DeskNames still reports no access, the entry may belong to an earlier build: remove that entry and add /Applications/DeskNames.app again. If macOS leaves the old entry stuck, a developer can reset only this app with `tccutil reset Accessibility local.desknames.app`, then use the app’s Open Accessibility settings button and approve the current build.

SAVE AND RESTORE
1. Open the apps/documents you want on a desktop and arrange their windows.
2. In Layouts & windows, select that desktop and click Save current layout. There is one saved layout per desktop; saving replaces that desktop's previous layout.
3. Restore layout puts matching windows back. Matching uses live window identity, then unique app/title matches, and never guesses between multiple changed document titles.
4. Enable Restore automatically when I enter this desktop to apply the layout on a later desktop switch. It is off by default.
5. Open missing apps when restoring launches saved apps that are no longer running. It cannot recreate unsaved documents or browser tabs; apps that do not create a matching window are reported as skipped.
6. Gather windows from other desktops is an optional manual-restore setting. Automatic restore only rearranges windows already on the entered desktop and can launch missing apps, so it does not bounce through other desktops in the background.

WINDOW MOVEMENT
Choose a window and click a numbered grid cell, Left half, Right half, or Fill screen. Set rows, columns and gap, then Tile this desktop to place its current windows into the grid. Grid overflow is left unchanged and reported. Some applications enforce minimum window sizes.

SMART PANES
Open Smart panes and choose a desktop, one of seven illustrated layouts, and spacing. Each desktop remembers its own pane preset. Set spacing to 0 pt for edge-to-edge panes without an inset border. Hold Command while dragging a window by its title bar; numbered panes appear across the screen and the target highlights. Release the mouse first, then Command, to fit the window. Releasing Command first cancels the snap and leaves an ordinary drag. Escape also cancels. Preview panes temporarily shows the layout without moving windows; the small settings illustration is not a drop target.

The seven presets are Two columns, Three columns, Four columns, Four quarters, Two rows, Wide + stack, and Focus. The overlay uses the current desktop's saved preset on the display under the pointer. Gaps are not drop targets. Moving and resizing are distinguished by observed window geometry, so selecting content or resizing an edge does not snap the window. Full-screen, minimized, and utility-panel windows are excluded. Pane presets are separate from saved window arrangements, and the Command-drag switch is independent of global keyboard shortcuts.

Enable Resize neighboring panes together to show small draggable handles between windows that fill adjacent panes. Drag a handle to grow one side and shrink the other while preserving the gap; Escape cancels. Window minimum sizes are checked before saving: a rejected resize restores the participating windows and leaves the pane configuration unchanged. Adjusted dividers persist for that desktop or shared monitor preset. Choose the preset again to reset its widths. Minimized, ambiguous overlapping, and all-desktop windows are excluded. Handles are for windows aligned to the Smart panes geometry, not arbitrary overlapping windows.

Keyboard shortcuts includes Next/Previous pane layout, each of the seven presets, Move window to pane 1–4, and Toggle linked pane resizing. Add suggested pane shortcuts fills only unused bindings; existing installations retain their bindings until you opt in. Suggested cycling uses Control–Option–[ and Control–Option–]; pane placement uses Control–Option–F1 through F4. Preset selection changes the pane guides; placement shortcuts move the focused window into a pane of that layout. The separate Column 1–4 window commands divide the screen into equal fourths. Snaps and direct size commands share pixel-aligned pane geometry, using the current monitor’s usable area, scale, and configured gap. Easing duration adapts to travel distance (roughly 0.12–0.24 seconds); updates follow display frame deadlines. If an app takes more than two display intervals to apply a frame, the transition finishes directly instead of continuing visibly choppy steps. Windows shrink before moving and grow afterward to avoid being clipped at their old position. A newer placement interrupts the old transition and preserves the original Restore previous size frame. Final position is verified. Reduce Motion skips the animation.

DeskNames' editor is resizable and can itself be snapped. It requires at least 640×520 content points and refuses panes that cannot fit it. The visible editor is included in new saved layouts. Existing applications may enforce their own minimum sizes. This local preview's native gesture validation is documented separately; building and passing the self-test alone does not establish that every application's title bar works.

Move to desktop sends the selected ordinary window to the chosen desktop through a verified native background operation on supported macOS 26 systems. It does not follow the window. On unsupported systems, manual same-display movement retains the older simulated title-bar drag; automatic rules never use that fallback. Full-screen and all-desktop windows are excluded. Cross-display native transfers validate both Space ownership and resulting screen placement; physical two-monitor validation remains pending.

SWITCHER AND SHORTCUTS
DeskNames starts quietly in the menu bar. Click its menu-bar icon or use the control-panel shortcut. The full settings window opens only from Settings in that panel. Opening the control panel hides an existing settings window. The Pane layouts tab shows seven visual presets for the current desktop. Search, click a card, or use the arrow keys and Return to choose. The active layout is marked; spacing is preserved, and choosing the same preset retains adjusted dividers. Choosing guides does not rearrange existing windows. The Desktops tab retains desktop search and switching. Escape closes the panel and returns focus to the previous app. Settings opens the full editor. Global shortcuts start disabled, including when upgrading from earlier versions. Open Keyboard shortcuts to opt in, click any shortcut and press the replacement key combination. Escape or Tab cancels, and Delete or Clear removes a binding. Clicking away or switching apps cancels recording. DeskNames pauses its global shortcuts while recording so an existing binding does not run as you enter it. Changes save automatically and take effect immediately. Suggested bindings:
  Control–Command–Option–Space: DeskNames control panel (avoids Finder’s Command–Option–Space)
  Control–Option–1 through 9: go to desktop
  Control–Option–S: save the active desktop layout
  Control–Option–R: restore the active desktop layout
Duplicate bindings and unsupported combinations are rejected. Shortcut registration conflicts are displayed in Keyboard shortcuts. Turning shortcuts off immediately releases all registered keys. Desktop switching selects the destination thumbnail directly in Mission Control and verifies the active Space, skipping intermediate desktops. Live tests verified desktop switching and moving an ordinary window between Work and Research on the same display. Shortcut registration succeeded, but global hotkey delivery could not be verified through the automated input tool; the desktop switcher and Go buttons were verified in that build.

NAMES AND MISSION CONTROL
Click names to edit; choose colors from each row's menu. Names are stored against stable desktop UUIDs. In Mission Control, hover at the top to expand desktop thumbnails. Automatic alignment reads the native desktop strip through Accessibility. Allow DeskNames in System Settings > Privacy & Security > Accessibility. Labels appear below the expanded strip after its position settles. The compact strip and unavailable or inconsistent geometry hide labels. Full-screen Spaces retain native labels. Private read-only APIs enumerate Spaces; future macOS changes can affect compatibility.
Previous alignment values remain saved but no longer affect label positions. Names, colors, keyboard shortcuts, and saved window layouts retain their existing settings.

LOCAL DATA
Names, colors, and legacy label calibration remain in local.desknames.app preferences.
Layouts: ~/Library/Application Support/DeskNames/layouts-v1.json
Layouts contain application bundle identifiers, window titles and normalized geometry. They are stored only on this Mac. There are no accounts or analytics. Optional Sparkle update checks contact GitHub; update downloads use GitHub release hosting. System-profile reporting is disabled. Desktop names, window titles and layout files are not sent with update checks. This release does not add itself to login items.

BUILD AND TEST
Requires Apple Silicon and Xcode command line tools. Build target: macOS 14+. Development testing: macOS 26.6.2.
  ./build.sh
  build/DeskNames.app/Contents/MacOS/DeskNames --self-test
Tests cover name and layout persistence, stable desktop identity, window matching and ambiguity rejection, screen normalization, offscreen clamping, and 48 grid configurations. Live tests also verified grid placement, restoring six windows, cross-desktop window movement, gathering a saved window from another desktop after restarting DeskNames, and automatic restoration when returning through Go. Temporary test windows were closed afterward. Automatic restoration and gathering remain opt-in. This is an ad-hoc-signed local preview, not an Apple-notarized release.

--render-preview PATH renders the actual editor with local saved names. Add --layouts to render the workspace page. Fixture.swift is an optional standalone two-window test application; it contains no documents and is excluded from the app build. Icon.swift renders the original app icon and is also excluded from the executable build.

DESIGN SOURCES
Original Swift/AppKit implementation, MIT licensed. REA inspection of SpaceJump established the general use of non-activating label panels; no SpaceJump code or assets are included. Initial Mission Control geometry was informed by public measurements in https://github.com/ZipLyne-Agency/SpaceNamer. Space membership declarations were checked against public CGS headers: https://github.com/fjolnir/xnomad/blob/master/CGSPrivate.h. Those private interfaces are not a compatibility contract.

KEYBOARD EVENT NOTE
Arrow-key navigation preserves the Fn and numeric-pad flags created for arrow events. The behavior was checked locally and against the first-hand issue report at https://github.com/AprilNEA/OpenLogi/issues/1653 and Apple’s Core Graphics flag documentation. No third-party implementation code is included.

0.2.1 UPDATE
Restore matches exact window identities first. Title matching requires one unmatched saved window and one live window with that title, within the same app. Duplicate saved titles are skipped if identity cannot disambiguate them; a single remaining window is used only if there is a single unmatched saved window for that app. New regression checks cover ambiguous shared titles in both orders, multiple live duplicates, exact-identity disambiguation and separate applications.

This build also includes the reviewed reductions in idle editor redraws and label-view reconstruction, bounds checks for saved colors/alignment, launch waits only for newly launched apps, clearer automatic-cancellation reporting, display UUID matching for tiling and an empty-result switcher selection fix.

Live validation of 0.2.1: same-title windows restored to their respective saved positions; moving one to another desktop and gathering it back succeeded; automatic restoration on return through Go succeeded; replacing both saved same-title windows with one new same-title window correctly skipped both entries and did not move or resize the replacement. The user's original layout was restored and the temporary windows were closed.

In paired 20-second samples on this Mac with the Label settings page visible and the same field focused, idle CPU averaged 5.64% before and 0.50% after the update. This is a short local measurement, not a general performance guarantee.

The source package includes MatchingFixture.swift as an optional separate test app for the duplicate-title scenario; it is not part of the DeskNames executable.

0.2.4 UPDATE
Shortcut dropdowns are replaced by clickable recorder fields. Click a binding and press the new combination; it saves automatically. Escape or Tab cancels, and Delete or Clear removes it. Duplicate or unsupported combinations leave the recorder open without changing the saved binding. Punctuation, navigation, and function keys are now supported with Command, Option, or Control. Recording temporarily releases DeskNames' global shortcut registrations and restores them when recording ends; it does not change the enabled preference.

Tests cover recorded input, duplicate and Shift-only rejection, repeat rejection, persistence, cancellation, deleting a binding, replacing an active recorder, and editing while globally disabled. Installed-app checks verified Command–Shift–K, Command–Q capture without quitting, duplicate rejection, unmodified-key rejection, Escape and Tab cancellation, Delete clearing, and leaving the page. The existing global hotkey delivery limitation of the automated input tool remains; registration and editing are checked separately.

BUILD 13: ANIMATION AND RESOURCE USE
Pane overlays reuse a persistent hosting view, animate highlights and fade in over 120 ms, and respect macOS Reduce Motion. There is no repeating animation while idle. Desktop-state polling runs once per second outside Mission Control; Space-change notifications trigger an immediate refresh. Mission Control detection retains its existing 200 ms cadence. The editor adapts down to 640×520, collapsing its sidebar to labelled-accessible icon buttons below 850 points wide; settings remain scrollable.

0.4.0 WINDOW COMMANDS
Layouts & windows now includes direct commands for halves, quarters, thirds, maximize, center, restore previous size, smaller/larger, and next/previous display. Select a window before using these controls. Keyboard commands act on the focused ordinary window instead.

Open Keyboard shortcuts and click Add suggested window shortcuts to fill unassigned window commands without replacing existing bindings. Record any replacement by clicking its field. Existing installations preserve their bindings and enabled setting. Suggestions use Control–Option with arrows for halves, U/I/J/K for quarters, Shift–1/2/3 for thirds, Return to maximize, C to center, Delete to restore, minus/equal to shrink/grow, and Command–Left/Right for display movement. Global shortcuts remain opt-in and registration conflicts are reported.

Smart panes has a separate Snap at screen edges and corners switch, off by default. When enabled, dragging without Command to a side snaps a half, a corner snaps a quarter, the top maximizes, and the bottom snaps a bottom half. Holding Command gives the existing desktop pane layout priority. Leaving an edge, Escape, or a changed desktop/display cancels a stale drop. Use one edge-snapping utility at a time to avoid competing placements.

Restore keeps the original rectangle before the first successful manual snap/command during this app session. Repeated snaps do not overwrite it; a successful Restore clears it. History is bounded to 128 windows and checks window ID, owning process and app identity. Saved desktop layouts and automatic restoration are separate. Restore returns to the original display when it is still connected; otherwise it fits the recorded proportions into the current work area. Display commands preserve size where possible, fit within the destination work area, preserve relative center position, and cycle displays from left to right; with one display, they report that another is needed. Some apps enforce size limits.

0.4.1 desktop and shortcut fixes
- Desktop jumps select the destination thumbnail directly in Mission Control, skipping intermediate desktops. A brief Mission Control transition remains.
- Before version 0.5, window carrying retained the drag-based path. Version 0.5 adds native background transfer on supported systems.
- A desktop jump requested during a window operation waits; the latest requested destination wins.
- Shortcut registration is exclusive, so keys claimed by another app are marked unavailable. DeskNames does not change your bindings.
- Keyboard shortcuts shows the last received action and its result, plus guidance for desktop numbers that do not exist.
- Last desktop-jump diagnostics are stored locally in Application Support/DeskNames/desktop-jump.json and contain only desktop numbers and operation status.

0.5.0: screen-aware layouts and one-time window routing

Window routing: choose a running app, optionally match part of its title, select a desktop, and enable Automatically send new windows. Existing windows are baselined; each new window is considered once. Manual moves, rule edits, and windows opened during another operation are never replayed later. A short bounded observation period lets new window metadata settle. Background sending uses the macOS 26 native bridged operation and verifies membership, frame ownership and unchanged active desktops. Unsupported systems do not fall back to focus-stealing simulated drags for automatic rules.

Monitor models: Smart panes has a Share this preset with every matching monitor option. It shares pane geometry and spacing by vendor/model (or display-name/physical-size fallback), never by serial number. Exact screen UUIDs are tried first for saved layouts/rules, then equivalent monitor models. Simultaneously connected identical displays are distinguished by spatial slots; ambiguous replacements are skipped. Saved per-window desktop positions allow another unit of the same model to reuse an arrangement on its own native desktop IDs. The original screen's deleted desktop is never silently replaced by a numbered desktop.

Layouts: new saves capture exact point geometry, screen bounds/work area, monitor model, each window's desktop and front-to-back order, including the DeskNames editor. The default all-screen scope captures the active desktop on each connected screen. A topology recheck protects the previous save during screen changes. Manual restore activates each saved screen's desktop, restores frames, then verifies overlap order. Automatic restore restores visible-desktop geometry while preserving focus; it does not rearrange stacking. A resolution change uses a reported fitted fallback; Dock/menu-bar changes do not rescale an unchanged-resolution screen.

Older saves remain usable but must be saved once again to acquire exact geometry, screen-model and overlap metadata. Use the Save active layout shortcut to capture without bringing the editor to the front. Saved arrangement lets you choose an existing capture even after its original monitor has been replaced. Missing, ambiguous or app-constrained windows are reported rather than presented as exact successes. Unsaved documents, tabs and application content are not recreated.

Verification commands: --self-test, --pane-session-test, --layout-session-test, --pane-interaction-test, --movement-session-test. The movement session checks rapid retargeting, cancellation, restore history, persistent divider handles, and linked neighbors placed by shortcuts even when another guide layout is selected. The pane interaction test creates four disposable native windows and uses temporary settings to verify animated placement, linked resizing, and constrained-window rollback. The layout session creates three disposable overlapping windows and uses a temporary settings domain/layout file; it cannot enumerate external-app windows. Native TextEdit tests verified background routing, unchanged existing windows and no rerouting after a manual move. Physical cross-monitor testing still needs a connected second monitor. Pure checks cover translated screens, equivalent replacement units and eight identical-monitor role assignments.

Native bridge adapted from ferry (https://github.com/softmaxe/ferry) and yabai (https://github.com/asmvik/yabai). See THIRD_PARTY_NOTICES.txt.


0.6.0 distribution and updates
------------------------------
The public preview includes a ZIP download, a project-maintained Homebrew cask, and Sparkle updates. It is ad-hoc signed and not Apple-notarized. See README.md for installation and first-launch limitations. In the compact control panel, Check for Updates checks manually; Check automatically and Download and install updates automatically are opt-in. Signed feeds and archives are verified before extraction. User layouts remain local. Promotional screenshots and illustrated animations use isolated fictional sample content.
