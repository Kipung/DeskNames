# DeskNames 0.8.0 release evidence

Published November 16, 2026 as version 0.8.0, build 32. [GitHub release](https://github.com/Kipung/DeskNames/releases/tag/v0.8.0).

## Revision and review

Application head `ba78f4715057437b695db73590a872b36008f6d6` was reviewed against `6cc6c0360f9713d6953371e5fd02b80f1bdc20fc`. Stable patch-id `bb42ffc467ff01bf7cb76b6929a4df77c080aa32`. An independent release verifier returned PASS+NOTES after an optimized build, isolated full self-test, native control-center session, fixture rendering, strict signature verification and bundled notice comparison. No blocker was found. The user explicitly authorized direct main publication. No force push or protection change was used.

The release tag points to `e8417dbb89f3bba3ef90795cefd7086071faa9aa`. The feed was published in `403843033f831bd8078a457f79ecc1810f1ddf6e`. Only version/build stamping separates the reviewed application commit from the release tag.

## Publication checks

`scripts/release.sh` completed successfully using the stable DeskNames Release certificate and existing Sparkle Keychain key. It built the final release, ran self-tests, verified code signing, verified the archive and feed signatures, uploaded the assets, downloaded the public ZIP and compared its hash before publishing the update feed. It then updated `Kipung/homebrew-desknames`.

The public archive SHA-256 is `30a1003f00be211a73075d6aa4cd5131fbca6b2c5e9947f6eede8b3d54888ca2`. An independent post-publication ZIP integrity check passed. The public raw main appcast matched the generated signed feed byte-for-byte and passed public-key signature verification. The published Homebrew cask matched the generated cask and passed Ruby syntax checking. Remote main and the annotated release tag were read back.

The older installed 0.7.0 app's Check for Updates displayed an offer for 0.8.0 with the new release notes. The offer was closed without installation. This verifies update discovery, not installation or relaunch. Personal shortcut and layout settings were not changed.

## Limits

The GitHub Actions workflow was already manually disabled and was left unchanged. Build and test results above are local macOS 26.6.2 arm64 results. The app remains an unnotarized Apple Silicon preview. Physical key delivery, the friend's exact single-desktop state, actual login startup, live hide-on-deactivate and multiple-monitor behavior retain the limits recorded in [the feature report](control-center-and-shortcut-checks.md).
