# Releasing DeskNames

## Distribution status

The first downloadable release is an **unnotarized Apple Silicon preview**. A Developer ID Application certificate and notarization access require the appropriate Apple Developer membership. An Apple Development certificate is not a replacement. Do not describe these preview artifacts as notarized, and do not add quarantine-removal or Gatekeeper-disable commands to installation scripts.

Sparkle update signatures are independent of Apple code signing. They establish that updates were produced by the holder of the DeskNames update key, not Apple approval of the app.

## Publishing a release

Releases run from the release Mac, which holds the update key in its login Keychain. On `main`, with everything committed and pushed, run:

```sh
./scripts/release.sh 0.6.1 "What changed. Blank lines separate paragraphs."
```

The notes appear in the update window and on the GitHub release. The script:

1. Checks the version is newer, the tag is unused, and `main` matches GitHub.
2. Bumps the version and build number in `build.sh`, builds an ad-hoc-signed app, and runs the self-test.
3. Runs `scripts/package-release.py`, which creates the ZIP, signs it and the feed with the Keychain key, and verifies both signatures against `release/sparkle-public-key.txt`.
4. Shows the release and asks before publishing (add `--yes` as a third argument where prompts can't be answered, such as Claude Code's `!` commands). Until then nothing is pushed, and a failure or a "no" restores `build.sh`.
5. Commits the version bump, tags it, and pushes both.
6. Publishes the GitHub release with the ZIP, `SHA256SUMS.txt`, and `appcast.xml`, then downloads the published ZIP and checks its hash.
7. Only then commits and pushes `release/appcast.xml`. Installed apps read the feed from `main`, so this is the moment the update goes live.
8. Updates `Casks/desknames.rb` in `Kipung/homebrew-desknames`.

If a later step fails, the script says which steps finished. Complete the rest by hand in the same order. Never push an edited `release/appcast.xml` unless its ZIP is already published.

After a release, check for updates from an older installed version and record what was tested. A valid signature or an “up to date” response alone does not prove the install-and-relaunch cycle.

## Signing key

The dedicated Sparkle key is in the release Mac’s login Keychain, account **local.desknames.app**. Only `release/sparkle-public-key.txt` is public. The `generate_keys` and `sign_update` tools come from the pinned official Sparkle distribution.

Do not regenerate or overwrite that key for each release. Keep a secure backup through the Keychain owner's normal backup process. Losing the key can prevent unnotarized installations from accepting future updates. The key never leaves this Mac: releases are signed locally, and GitHub Actions is not used for releasing. Do not put private keys in workflow logs, artifacts, Git, or the app bundle.

Sparkle is pinned to 2.10.1 in `scripts/fetch-sparkle.sh`, including the SHA-256 from its official GitHub release metadata. Review and update both together when upgrading the dependency. The build signs nested Sparkle helpers inside-out, then the framework, then the app. Normal app startup creates the updater; tests and rendering branches do not start it.

## Sample-only media

```sh
./build.sh
./scripts/render-demo.sh
```

Requires `ffmpeg` for GIF/MP4 encoding. `--render-marketing` creates isolated preference/layout stores and substitutes fictional desktops before creating the views. The control-panel PNG renders the production SwiftUI view. The animated scene is an **illustrated demonstration**, using synthetic sample windows and the production geometry/interpolation functions. It is not a screen recording or a claim that choosing a preset immediately tiles existing windows.

No screenshot of the user's display, real app content, personal saved layout, or runtime preference export is included. Inspect the generated PNG and representative animation frames before publication. Never use the older `--render-preview` entry point for public media; it reads normal app settings.

## Future notarization

When Developer ID is available, sign all bundled code with the distribution identity and Hardened Runtime, notarize the archive using `xcrun notarytool`, staple the app, verify with `stapler validate` and `spctl --assess`, then recreate and Sparkle-sign the final ZIP. Add notarization automation only after the identity and credential storage are provisioned. Never publish an Apple Development build as a notarized release.
