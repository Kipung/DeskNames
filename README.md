<div align="center">

# DeskNames

**Give every desktop a name. Give every window a place.**

A quiet macOS menu-bar utility for named desktops, visual pane layouts, and remembered window arrangements.

[Download for Mac](https://github.com/Kipung/DeskNames/releases/tag/v0.6.0) · [Install with Homebrew](#install) · [User guide](README.txt) · [Report a bug](https://github.com/Kipung/DeskNames/issues)

**Apple Silicon · macOS 14+ · Free and open source**

![Illustrated pane-layout demo using only fictional sample windows](docs/media/panes-demo.gif)

<sub>Illustrated demo with synthetic sample windows, using DeskNames’ pane geometry. No personal desktop was recorded.</sub>

</div>

## A small panel, then back to work

Press **Control–Option–Command–Space** to choose a pane layout for the current desktop, or find another desktop by name. Search, click, or use the arrow keys and Return. The full settings window opens only when you ask for it.

<p align="center"><img src="docs/media/control-panel.png" width="480" alt="DeskNames control panel showing seven illustrated layouts for the fictional Create desktop"></p>

- **Seven pane layouts:** two, three, or four columns; quarters; rows; wide + stack; and focus.
- **Command-drag to fit:** choose a guide, drag a window, and release the mouse before Command. Per-desktop spacing includes an edge-to-edge option.
- **Resize neighbors together:** an optional shared divider adjusts windows on both sides.
- **Name your desktops:** names and colors follow Space identities, with labels in expanded Mission Control.
- **Remember arrangements:** save and restore window bounds and overlap order. Optional routing sends a newly opened window to its chosen desktop once.
- **Keep control:** shortcuts, edge snapping, routing, and automatic updates are configurable. Existing shortcut bindings survive upgrades.

Selecting a pane preset changes the guides; it does not rearrange every open window at once. The separate tiling and restore commands handle arrangements.

## Install

**0.6.0 is an unnotarized public preview.** It is ad-hoc signed, not Developer ID signed or notarized by Apple. macOS may block first launch. Review [Apple’s guidance for opening downloaded apps](https://support.apple.com/en-us/102445); DeskNames does not disable Gatekeeper or remove quarantine. Updating may require renewing its Accessibility approval. Intel Macs are not supported by this download.

### Homebrew

```sh
brew install --cask kipung/desknames/desknames
```

The [tap](https://github.com/Kipung/homebrew-desknames) pins the release archive’s SHA-256. This is a project-maintained tap, not a listing in Homebrew’s official cask repository.

### Download for Mac

1. Download [DeskNames-0.6.0-arm64.zip](https://github.com/Kipung/DeskNames/releases/download/v0.6.0/DeskNames-0.6.0-arm64.zip).
2. Unzip it and drag **DeskNames.app** into **Applications**.
3. Open DeskNames, then click its menu-bar icon. It starts without a full app window.
4. Choose **Settings** and enable DeskNames in **System Settings → Privacy & Security → Accessibility** for window management.
5. In **Keyboard shortcuts**, enable global shortcuts to use **Control–Option–Command–Space**. They start off so DeskNames does not take over existing bindings.

Release assets include checksums. No account or subscription is required.

See the [0.6.0 validation report](docs/release-0.6.0-validation.md) for the tested Homebrew installation, signed updater installation/relaunch, and remaining limits.

## Updates

The control panel includes **Check for Updates…**, **Check automatically**, and **Download and install updates automatically**. Background checks and automatic installation start off; enable the behavior you want.

Updates use [Sparkle](https://sparkle-project.org/). Both the feed and archives are verified with the embedded Ed25519 public key, and downloads use HTTPS. Update signing is separate from Apple notarization: this preview is still unnotarized after an update.

Homebrew users can also run:

```sh
brew update
brew upgrade --cask desknames
```

## Privacy

Desktop names, shortcuts, pane preferences, rules, and saved arrangements stay on your Mac. There are no accounts or analytics. DeskNames does not request Screen Recording permission.

Update checks contact GitHub for the feed, and update downloads use GitHub release hosting. Sparkle’s optional system-profile reporting is disabled. Window titles, desktop names, and layout files are not sent with update checks.

Promotional media is generated offscreen from fictional fixture content. [Download the MP4 demo](docs/media/panes-demo.mp4) or [reproduce the media](docs/releasing.md#sample-only-media).

## Build from source

Install Xcode’s command-line tools on an Apple Silicon Mac, then:

```sh
git clone https://github.com/Kipung/DeskNames.git
cd DeskNames
./build.sh
open build/DeskNames.app
```

The build script downloads a pinned, checksum-verified Sparkle framework and compiles the native Swift/AppKit/SwiftUI app. Local builds are ad-hoc signed by default. [Persistent development signing](docs/development-signing.md) is optional.

```sh
build/DeskNames.app/Contents/MacOS/DeskNames --self-test
```

The movement, pane, and layout session tests create disposable native windows and may briefly affect the display. See [validation notes](docs/validation.md) and [the contributor guide](CONTRIBUTING.md).

## Compatibility

The deployment target is macOS 14; current native validation is on macOS 26.6.2. That is not a claim that all functionality has been validated on every OS release. Background window transfers use private macOS interfaces and are supported more narrowly; automatic routing refuses unsupported transfers.

Apps can enforce minimum window sizes or reject Accessibility actions. Multiple-monitor reconnects and identical-monitor arrangements still need broader physical testing. Restoring a layout does not recreate closed documents or browser tabs.

[Full user guide](README.txt) · [Architecture](docs/architecture.md) · [Release process](docs/releasing.md) · [Project context](PROJECT_CONTEXT.md)

## License

[MIT](LICENSE). Native bridge attribution for ferry and yabai, and Sparkle’s license, are preserved in [THIRD_PARTY_NOTICES.txt](THIRD_PARTY_NOTICES.txt) and the app bundle.
