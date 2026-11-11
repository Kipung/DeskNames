#!/bin/zsh
# Release DeskNames from this Mac in one command.
# Usage: scripts/release.sh 0.6.1 "What changed. Blank lines separate paragraphs." [--yes]
# --yes publishes without the final question (for places that cannot answer prompts).
#
# Everything that can fail locally (build, self-test, signing) happens before anything is pushed.
# Installed apps read release/appcast.xml from main, so the feed is pushed only after the
# download is published and verified. Rerunning a finished version is refused.
set -eu
cd "${0:A:h}/.."
die() { print -u2 "\n$1"; exit 1 }
step() { print "\n→ $1" }

version=${1:-}; notes=${2:-}; confirmed=${3:-}
[[ -n $version && -n $notes && ( -z $confirmed || $confirmed == --yes ) ]] || die 'Usage: scripts/release.sh VERSION "Release notes" [--yes]'
[[ $version =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || die "Use a version like 0.6.1."
[[ $(git branch --show-current) == main ]] || die "Release from the main branch."
[[ -z $(git status --porcelain) ]] || die "Commit or stash your changes first."
git fetch --quiet --tags origin main
[[ $(git rev-parse HEAD) == $(git rev-parse origin/main) ]] || die "Sync main with GitHub first (git pull / git push)."
git rev-parse --quiet --verify "refs/tags/v$version" >/dev/null && die "v$version already exists."
gh auth status >/dev/null 2>&1 || die "Sign in to GitHub first: gh auth login"
# A stable certificate keeps users' Accessibility approval across updates. See docs/releasing.md.
identity=${DESKNAMES_RELEASE_IDENTITY:-DeskNames Release}
security find-identity -p codesigning | grep -qF "\"$identity\"" || die "The '$identity' signing certificate is missing from your Keychain. See docs/releasing.md."

current=$(sed -nE 's#.*<key>CFBundleShortVersionString</key><string>([0-9.]+)</string>.*#\1#p' build.sh)
build=$(sed -nE 's#.*<key>CFBundleVersion</key><string>([0-9]+)</string>.*#\1#p' build.sh)
[[ -n $current && -n $build ]] || die "Could not read the current version from build.sh."
[[ $version != $current && $(printf '%s\n' $current $version | sort -V | tail -1) == $version ]] || die "$version must be newer than $current."
next=$((build + 1))
zip="DeskNames-$version-arm64.zip"

step "Building DeskNames $version (build $next)"
sed -i '' -E "s#(<key>CFBundleShortVersionString</key><string>)[0-9.]+#\1$version#; s#(<key>CFBundleVersion</key><string>)[0-9]+#\1$next#" build.sh
undo() { git checkout -- build.sh release/appcast.xml 2>/dev/null; print -u2 "\nStopped before publishing; nothing was pushed." }
trap undo ERR INT
rm -rf dist
DESKNAMES_SIGN_IDENTITY=$identity ./build.sh >/dev/null
codesign --verify --deep --strict build/DeskNames.app
build/DeskNames.app/Contents/MacOS/DeskNames --self-test >/dev/null

step "Signing the update (macOS may ask to use the DeskNames key in your Keychain)"
mkdir -p build
print -r -- "$notes" > build/release-notes.txt
DESKNAMES_RELEASE_NOTES_FILE=build/release-notes.txt python3 scripts/package-release.py

print "\nReady to publish DeskNames $current → $version:\n\n$notes\n"
if [[ $confirmed != --yes ]]; then
  [[ -t 0 ]] || { undo; die "Can't ask for confirmation here. Add --yes to the end of the command to publish."; }
  if ! read -q "?Publish it to everyone now? [y/N] "; then print; undo; exit 1; fi
  print
fi
trap - ERR INT
published() { print -u2 "\nStopped after: $1. Fix the problem, then finish the remaining steps in docs/releasing.md."; }

step "Tagging v$version"
git checkout -- release/appcast.xml  # the signed feed is pushed last, after the download is live
git commit --quiet -m "Release DeskNames $version" build.sh
git tag -a "v$version" -m "$notes"
git push --quiet origin main "v$version" || { published "local commit and tag (not pushed)"; exit 1 }

step "Publishing the download"
{ print -r -- "$notes"; print; print "This is an unnotarized Apple Silicon preview. See the README before installing." } > build/release-body.md
gh release create "v$version" --verify-tag --title "DeskNames $version" --notes-file build/release-body.md \
  "dist/$zip" dist/SHA256SUMS.txt dist/appcast.xml || { published "pushing the tag"; exit 1 }
curl -fsSL --retry 5 --retry-delay 3 -o build/published.zip "https://github.com/Kipung/DeskNames/releases/download/v$version/$zip"
[[ $(shasum -a 256 build/published.zip | cut -d' ' -f1) == $(cut -d' ' -f1 dist/SHA256SUMS.txt) ]] || {
  published "uploading the release, but the downloaded file does not match. Do not publish the feed"; exit 1 }

step "Publishing the update feed (installed apps see the update from now on)"
cp dist/appcast.xml release/appcast.xml
git commit --quiet -m "Publish the v$version update feed" release/appcast.xml
git push --quiet origin main || { published "publishing the download (feed committed locally, not pushed)"; exit 1 }

step "Updating Homebrew"
rm -rf build/tap
gh repo clone Kipung/homebrew-desknames build/tap -- --quiet
cp dist/desknames.rb build/tap/Casks/desknames.rb
ruby -c build/tap/Casks/desknames.rb >/dev/null
git -C build/tap commit --quiet -am "Update DeskNames to $version"
git -C build/tap push --quiet || { published "publishing the feed (Homebrew update not pushed)"; exit 1 }

print "\n✓ DeskNames $version is live: https://github.com/Kipung/DeskNames/releases/tag/v$version"
