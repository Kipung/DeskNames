# Release 0.6.0 validation

Validated on November 10, 2026, on Apple Silicon with macOS 26.6.2. The release is build 28, tagged at `2f0b488992e58c4a7e5134ae2790376ea8564dff`.

## Published artifacts

- [Release and Mac download](https://github.com/Kipung/DeskNames/releases/tag/v0.6.0)
- [Homebrew tap](https://github.com/Kipung/homebrew-desknames)
- [Signed update feed](https://raw.githubusercontent.com/Kipung/DeskNames/main/release/appcast.xml)

The downloaded public ZIP matched the packaged artifact: SHA-256 `4d999cfb5b431c136493cfb84d2aac46219faba93e2d64a3f04c6a67696fadb9` (2,874,730 bytes). The installed executable hash is `5a99158f43796af565ff5b94f2209d358cdb3ce04bd2a34572a478a7df979bc4`.

## Completed checks

- The final app built successfully, passed deep/strict code-signature verification, and passed `--self-test` and `--pane-session-test`.
- A public-key-only CryptoKit verifier accepted the archive and signed feed. Modified archive and feed copies were rejected. The feed downloaded from its public raw URL also verified.
- `brew install --cask kipung/desknames/desknames` installed the published archive into a disposable app directory. The installed signature and executable hash matched the release. Uninstall removed the disposable installation without using `--zap`. Final cask metadata was checked with Homebrew 7.0.12; its requirements are Apple Silicon and macOS 14 or later.
- A disposable copy of the new updater-enabled app was marked as version 0.5.99/build 27, using an isolated Sparkle defaults domain. Sparkle found 0.6.0 from the public feed, installed it, and relaunched. The replaced executable matched the release hash, and a subsequent check displayed “You’re up to date!” for 0.6.0. This validates the real download/install/relaunch path from a simulated older version; historical build 27 did not include an updater and needs a manual upgrade once.
- The main installed app was upgraded to the exact release build. Its manual update check reported 0.6.0 as current. All seven layout cards and update controls fit in the compact panel. Automatic checks and installation remain opt-in.
- macOS retained stale Accessibility approval after the ad-hoc build replacement. Toggling and re-adding alone did not repair it. Resetting only `local.desknames.app` Accessibility approval and adding the installed app again repaired it; the user confirmed that the physical panel shortcut worked and Layouts & windows controls were enabled without the warning.
- Existing application preference values and saved-layout bytes were unchanged. Only update-check/window metadata was added by Sparkle.
- The published PNG uses the actual panel view with fictional fixture data. The GIF and MP4 are explicitly labeled illustrated demos. These assets were visually reviewed; no personal desktop recording, preferences, or saved layouts were published.

## Limits

This is an ad-hoc-signed, unnotarized preview. Update signatures do not replace Apple Developer ID signing or notarization. First launch and Accessibility renewal can require local user action. No Gatekeeper or quarantine bypass is included.

The GitHub Actions [build run](https://github.com/Kipung/DeskNames/actions/runs/42929387337) did not start because GitHub reported an account billing lock. It is not a passing CI run; the build and tests above ran locally. The workflow is ready for a rerun after the account restriction is resolved.

This release validation does not expand physical monitor or third-party app coverage. See [general validation notes](validation.md) for those limits. Scheduled automatic updates were not tested over a full background-check interval; the shared manual update installation path was exercised end to end.
