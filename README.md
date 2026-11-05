# DeskNames

A native macOS menu bar app for named desktops, window layouts, smart panes, and one-time window routing.

DeskNames helps you organize macOS Spaces around activities such as Work, Research, and Code. It adds name labels to the expanded Mission Control desktop strip and remembers window arrangements for later restoration.

**Current version: 0.5.0, build 22.** This is an experimental, ad-hoc-signed local preview for Apple Silicon. The build targets macOS 14 or later. Development and native window-transfer testing were recorded on macOS 26.6.2. Targeting macOS 14 does not establish that every feature works on every supported OS version.

## What it does

- Give desktops names and colors, stored against stable Space UUIDs.
- Display custom labels below the expanded Mission Control desktop thumbnails.
- Find desktops by name in a quick switcher and jump directly to their thumbnails.
- Save and restore window positions, sizes, screen assignments, desktop assignments, and overlap order.
- Restore visible-desktop window geometry automatically when entering a desktop, if enabled.
- Snap windows into six pane presets with Command-drag. Each desktop remembers its preset and spacing.
- Snap to screen edges and corners through a separate optional setting.
- Apply halves, quarters, thirds, maximize, center, resize, restore-size, and display-movement commands.
- Record custom global shortcuts and report registration conflicts. Global shortcuts are opt-in.
- Send newly opened windows to a desktop using app rules and an optional title match.
- Match saved screens by exact identity first, then by equivalent monitor model where the destination is unambiguous.

## Build and run

Install the Xcode command line tools on an Apple Silicon Mac. The build uses Apple's frameworks without third-party package dependencies.

```sh
git clone https://github.com/Kipung/DeskNames.git
cd DeskNames
./build.sh
open build/DeskNames.app
```

The script compiles the Objective-C bridge and Swift sources, creates an app bundle, and signs it ad hoc. There is no Xcode project or Swift package to open. To install the build, quit any running copy first and copy `build/DeskNames.app` into `/Applications` using Finder.

Enable DeskNames in **System Settings > Privacy & Security > Accessibility** for window management and desktop switching. Rebuilding may require removing a stale permission entry and approving the current app again. DeskNames itself does not request Screen Recording permission.

This repository does not provide an Apple-notarized installer. Build locally for now.

## Use it

Start with desktop names and colors in the editor. Expand the Mission Control desktop strip by hovering near the top of the screen to see the labels.

To save an arrangement, open and arrange your windows, enter the desktop, and choose **Save current layout** in **Layouts & windows**. By default, a capture includes the active desktop on each connected screen. Manual restore also restores overlap order. Automatic restore preserves focus and leaves stacking unchanged.

Choose a preset in **Smart panes**, then hold Command while dragging a window by its title bar. Release the mouse before Command to snap. Release Command first, or press Escape, to cancel. Edge snapping has a separate switch.

For window routing, choose a running app, an optional title substring, and a destination desktop. Enable **Automatically send new windows**. Existing windows remain in place. A new window is considered once, so moving it manually does not make DeskNames send it back.

See [the complete user guide and version history](README.txt) for settings, suggested shortcuts, matching rules, and troubleshooting.

## Verify a build

```sh
build/DeskNames.app/Contents/MacOS/DeskNames --self-test
build/DeskNames.app/Contents/MacOS/DeskNames --pane-session-test
```

The native layout session test creates temporary overlapping windows and exercises restoration. Run it when a brief visual test will not interrupt your work:

```sh
build/DeskNames.app/Contents/MacOS/DeskNames --layout-session-test
```

Test coverage and hardware gaps are recorded in [validation notes](docs/validation.md). Passing calculation tests does not prove physical multi-monitor behavior.

## Limits and compatibility

DeskNames uses private macOS interfaces to read Spaces and, on supported macOS 26 systems, move windows in the background. Apple can change these interfaces. Automatic routing refuses unsupported transfers rather than falling back to a focus-changing simulated drag.

- Physical cross-monitor movement, monitor reconnection, and simultaneous identical monitors still need live validation.
- Some apps enforce minimum window sizes or reject Accessibility actions.
- Full-screen, minimized, utility, and all-desktop windows have operation-specific exclusions.
- Layouts restore matching windows. They do not recreate unsaved documents, browser tabs, or application content.
- Old captures need saving again to acquire exact geometry, monitor metadata, and overlap order.
- Global shortcut registration and editing were tested. Physical keyboard delivery still needs a user check.
- Desktop jumps use Mission Control and can visibly change your desktop. Manual restore can activate desktops and raise windows. DeskNames does not isolate a computer-use agent inside a Space.

## Privacy and local storage

DeskNames has no accounts, analytics, or application network requests. It stores names, colors, rules, shortcuts, and pane preferences in the `local.desknames.app` preferences domain. Window layouts live at `~/Library/Application Support/DeskNames/layouts-v1.json`; they include app identifiers, window titles, geometry, and screen metadata.

Do not publish your personal preference exports, saved layouts, or diagnostic captures in bug reports without reviewing their contents. The app does not add itself to login items.

## Project documentation

- [Project context](PROJECT_CONTEXT.md): scope, current state, decisions, and next work.
- [Architecture](docs/architecture.md): source map and runtime behavior.
- [Validation](docs/validation.md): recorded evidence and remaining checks.
- [Contributing](CONTRIBUTING.md): build, test, and review expectations.
- [User guide and history](README.txt): detailed operation and earlier versions.

## License and attribution

DeskNames is MIT licensed. See [LICENSE](LICENSE).

The native bridge adapts work from [ferry](https://github.com/softmaxe/ferry) and [yabai](https://github.com/asmvik/yabai). Their MIT notices are preserved in [THIRD_PARTY_NOTICES.txt](THIRD_PARTY_NOTICES.txt) and copied into the app bundle. Additional design and API research references are recorded in the user guide.
