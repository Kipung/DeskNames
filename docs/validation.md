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
