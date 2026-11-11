# Releasing DeskNames

## Distribution status

The first downloadable release is an **unnotarized Apple Silicon preview**. A Developer ID Application certificate and notarization access require the appropriate Apple Developer membership. An Apple Development certificate is not a replacement. Do not describe these preview artifacts as notarized, and do not add quarantine-removal or Gatekeeper-disable commands to installation scripts.

Sparkle update signatures are independent of Apple code signing. They establish that updates were produced by the holder of the DeskNames update key, not Apple approval of the app.

## Build and package

1. Update the marketing version and increasing numeric build in `build.sh`. Never reuse a public tag or silently replace an existing release archive.
2. Run `DESKNAMES_SIGN_IDENTITY=- ./build.sh` for the unnotarized preview. Do not publish a personal Apple Development signature.
3. Run the self-test and relevant native session tests. Verify the installed artifact, not just source calculations.
4. Run `python3 scripts/package-release.py` on the release Mac. It validates the code signature, checks that the Keychain public key matches the app, creates the ZIP, uses Sparkle’s official `generate_appcast` to sign the archive/feed together, independently verifies both with CryptoKit and the public key, and writes `release/appcast.xml`, and emits checksums and a Homebrew cask under `dist/`.
5. Review changes and media for personal data. Commit source, docs, and the signed feed. The archive, dependency cache, and private keys stay out of Git.
6. Create an immutable tag and a draft GitHub release for that exact commit. Upload `dist/DeskNames-VERSION-arm64.zip`, `dist/SHA256SUMS.txt`, and `dist/appcast.xml`; then publish it after verifying asset hashes. Release notes must state the unnotarized preview limitation.
7. Publish the generated `dist/desknames.rb` as `Casks/desknames.rb` in `Kipung/homebrew-desknames`. Keep version, URL, and checksum together. Validate its Ruby syntax and `brew info --cask` metadata, then test downloading the published archive.
8. Confirm the public feed and asset URLs resolve. Check for updates from the release app and record what was tested. A valid signature or “up to date” response alone does not prove an older-version installation/relaunch cycle.

The feed URL is `https://raw.githubusercontent.com/Kipung/DeskNames/main/release/appcast.xml`. GitHub may cache changes briefly. The feed contains the latest full archive; older compatible installations can update directly. Do not edit a signed XML feed after signing it.

## Signing key

The dedicated Sparkle key is in the release Mac’s login Keychain, account **local.desknames.app**. Only `release/sparkle-public-key.txt` is public. The `generate_keys` and `sign_update` tools come from the pinned official Sparkle distribution.

Do not regenerate or overwrite that key for each release. Keep a secure backup through the Keychain owner's normal backup process. Losing the key can prevent unnotarized installations from accepting future updates. Exporting it is not part of this repository's build or CI. CI builds and tests; release signing happens locally. Do not put private keys in workflow logs, artifacts, Git, or the app bundle.

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
