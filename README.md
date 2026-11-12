<div align="center">

# DeskNames

**Give every desktop a name. Give every window a place.**

A quiet macOS menu-bar utility for named desktops, visual pane layouts, and remembered window arrangements.

**Apple Silicon · macOS 14+ · Free and open source (MIT)**

[**Download for Mac**](https://github.com/Kipung/DeskNames/releases/latest) · [Install with Homebrew](#install) · [User guide](README.txt) · [Report a bug](https://github.com/Kipung/DeskNames/issues)

<img src="docs/media/panes-demo.gif" width="760" alt="Illustrated demo: choosing Three columns in the DeskNames panel, Command-dragging three sample windows into the guides, saving the arrangement, moving windows with keyboard shortcuts, restoring the saved arrangement, and jumping to a desktop named Read">

<sub>Illustrated demo with fictional sample windows, drawn with DeskNames’ own pane geometry. Not a screen recording. <a href="docs/media/panes-demo.mp4">MP4 version</a>.<br>DeskNames is an unnotarized public preview. See <a href="#install">Install</a> before first launch.</sub>

</div>

## What it does

DeskNames lives in the menu bar. Open its compact panel to pick a pane layout for the current desktop, or switch to another desktop by name. Search, click, or use the arrow keys and Return. The full settings window opens only when you ask for it.

- **Seven pane layouts:** two, three, or four columns; quarters; rows; wide + stack; and focus.
- **Command-drag to fit:** choose a guide, drag a window, and release the mouse before Command. Per-desktop spacing includes an edge-to-edge option.
- **Resize neighbors together:** an optional shared divider adjusts windows on both sides.
- **Name your desktops:** names and colors follow Space identities, with labels in expanded Mission Control.
- **Remember arrangements:** save where every window sits on a desktop, including overlap order, and put them all back in one step after things get messy. Restores can run automatically when you enter a desktop. Optional routing sends a newly opened window to its chosen desktop once.
- **Pin a window:** a pinned window follows you to whichever desktop you switch to, landing a moment after the switch. Pin with ⌃⌥P or from the panel’s Desktops tab; pins last until DeskNames quits.
- **Keep control:** shortcuts, edge snapping, routing, and automatic updates are configurable. Existing shortcut bindings survive upgrades.

### Keyboard shortcuts

Shortcuts start **off**. Turn them on in **Settings → Keyboard shortcuts**, and use the **Add suggested** buttons for the window and pane shortcuts. Suggestions never replace bindings you already set.

| Action | Suggested shortcut |
| --- | --- |
| Open the DeskNames panel | ⌃⌥⌘ Space |
| Save / restore this desktop’s arrangement | ⌃⌥S / ⌃⌥R |
| Go to desktop 1–9 | ⌃⌥1 … ⌃⌥9 |
| Pin / unpin the focused window | ⌃⌥P |
| Left / right / top / bottom half | ⌃⌥← / → / ↑ / ↓ |
| Quarters | ⌃⌥U, I, J, K |
| Thirds | ⌃⌥⇧1, 2, 3 |
| Maximize / center / restore previous size | ⌃⌥↩ / ⌃⌥C / ⌃⌥⌫ |
| Move the window into pane 1–4 | ⌃⌥F1 … F4 |
| Previous / next pane layout | ⌃⌥[ / ⌃⌥] |

Every binding can be changed. The [user guide](README.txt) lists them all.

> [!NOTE]
> Selecting a pane preset changes the guides; it does not rearrange every open window at once. The separate tiling and restore commands handle arrangements.

<p align="center"><img src="docs/media/control-panel.png" width="420" alt="DeskNames control panel with the Pane layouts tab open, showing seven layout cards for a fictional desktop named Create, with Three columns selected"></p>

<p align="center"><sub>The actual control panel, rendered with fictional sample data.</sub></p>

## Install

You need a Mac with Apple Silicon (M1 or later) running macOS 14 or later. Setup takes about two minutes.

### Step 1: Get the app

**With Homebrew** (paste into Terminal):

```sh
brew install --cask kipung/desknames/desknames
```

**Or download it:**

1. Download **DeskNames-VERSION-arm64.zip** from the [latest release](https://github.com/Kipung/DeskNames/releases/latest).
2. Double-click the ZIP, then drag **DeskNames.app** into your **Applications** folder.

### Step 2: Allow it to open (first time only)

DeskNames is free and isn’t notarized by Apple, so macOS asks you to confirm it once. This is normal for apps outside the App Store that aren’t notarized. DeskNames doesn’t turn off any macOS protection to get around it.

1. Open **DeskNames** from Applications. macOS says *“DeskNames” Not Opened*. Click **Done**.
2. Open **System Settings → Privacy & Security** and scroll down to **Security**.
3. Next to *“DeskNames” was blocked to protect your Mac*, click **Open Anyway**, then confirm with your password or Touch ID.
4. Click **Open Anyway** once more in the dialog that appears.

On macOS 14 you can instead Control-click **DeskNames.app** in Applications and choose **Open**. Apple explains this in [Open a Mac app from an unknown developer](https://support.apple.com/en-us/102445).

### Step 3: Turn on window controls

The DeskNames panel opens automatically the first time. After that, click the **DeskNames icon in the menu bar** (top right of your screen) to open it.

1. In the panel, choose **Settings**. On the **Layouts & windows** page, click **Open Accessibility settings**.
2. Turn on **DeskNames** in the list. macOS may ask for your password.

That’s it. To use keyboard shortcuts, turn them on in **Settings → Keyboard shortcuts**. They start off so DeskNames doesn’t take over shortcuts you already use.

### If something doesn’t work

- **No “Open Anyway” button:** open DeskNames once first (Step 2.1). The button only appears after macOS blocks an attempt, and it stays for about an hour.
- **Window controls stay off after an update, even though DeskNames is turned on in Accessibility:** select DeskNames in the Accessibility list, remove it with the **–** button, then click **Open Accessibility settings** in DeskNames again and turn it back on. From 0.6.2 on, updates keep the approval.
- **Can’t find the menu bar icon:** a crowded menu bar can hide it behind the notch. Open DeskNames from Applications again and the panel appears.
- **Intel Mac:** not supported.

To check a download, compare it with `SHA256SUMS.txt` from the release. The Homebrew [tap](https://github.com/Kipung/homebrew-desknames) checks the archive automatically. It is maintained by this project; DeskNames isn’t in Homebrew’s official cask list. The [0.6.0 validation report](docs/release-0.6.0-validation.md) has the tested install and update details.

## Updates

The control panel includes **Check for Updates…**, **Check automatically**, and **Download and install updates automatically**. On its second launch, DeskNames asks once whether to check for updates automatically. Automatic installation **starts off**. You can change both settings at any time.

Updates use [Sparkle](https://sparkle-project.org/). Both the feed and archives are verified with the embedded Ed25519 public key, and downloads use HTTPS. Update signing is separate from Apple notarization: this preview is still unnotarized after an update. Builds from before the updater was added need a one-time manual upgrade.

Homebrew users can also run:

```sh
brew update
brew upgrade --cask desknames
```

## Privacy

- Desktop names, shortcuts, pane preferences, rules, and saved arrangements stay on your Mac.
- No accounts or analytics. DeskNames does not request Screen Recording permission.
- Network use is limited to updates: checks contact GitHub for the feed, and downloads use GitHub release hosting. Sparkle’s optional system-profile reporting is disabled. Window titles, desktop names, and layout files are not sent with update checks.

The screenshot uses the real panel with fictional fixture data; the GIF and MP4 are illustrated demos generated offscreen from fictional content. [Download the MP4 demo](docs/media/panes-demo.mp4) or [reproduce the media](docs/releasing.md#sample-only-media).

## Compatibility and limitations

- **macOS version:** the deployment target is macOS 14, but current native validation is on macOS 26.6.2. That is not a claim that all functionality has been validated on every OS release.
- **Moving windows between desktops:** background window transfers use private macOS interfaces and are supported more narrowly; automatic routing refuses unsupported transfers.
- **Other apps:** apps can enforce minimum window sizes or reject Accessibility actions.
- **Displays:** multiple-monitor reconnects and identical-monitor arrangements still need broader physical testing.
- **Restoring layouts:** does not recreate closed documents or browser tabs.

## Build from source

Install Xcode’s command-line tools on an Apple Silicon Mac, then:

```sh
git clone https://github.com/Kipung/DeskNames.git
cd DeskNames
./build.sh
open build/DeskNames.app
```

The build script downloads a pinned, checksum-verified Sparkle framework and compiles the native Swift/AppKit/SwiftUI app. Local builds are ad-hoc signed by default. [Persistent development signing](docs/development-signing.md) is optional.

Run the self-test:

```sh
build/DeskNames.app/Contents/MacOS/DeskNames --self-test
```

The movement, pane, and layout session tests create disposable native windows and may briefly affect the display. See [validation notes](docs/validation.md) and [the contributor guide](CONTRIBUTING.md).

## Documentation

[Full user guide](README.txt) · [0.6.0 validation report](docs/release-0.6.0-validation.md) · [Architecture](docs/architecture.md) · [Release process](docs/releasing.md) · [Project context](PROJECT_CONTEXT.md)

## License

[MIT](LICENSE). Native bridge attribution for ferry and yabai, and Sparkle’s license, are preserved in [THIRD_PARTY_NOTICES.txt](THIRD_PARTY_NOTICES.txt) and the app bundle.
