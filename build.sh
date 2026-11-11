#!/bin/zsh
set -eu
cd "${0:A:h}"
SIGNING_IDENTITY="${DESKNAMES_SIGN_IDENTITY:-}"
SIGNING_IDENTITY_FILE="${DESKNAMES_SIGN_IDENTITY_FILE:-$HOME/Library/Application Support/DeskNames Development/signing-identity.txt}"
if [[ -z "$SIGNING_IDENTITY" && -e "$SIGNING_IDENTITY_FILE" ]]; then
  [[ -f "$SIGNING_IDENTITY_FILE" && -r "$SIGNING_IDENTITY_FILE" ]] || { print -u2 'Cannot read the configured DeskNames signing identity.'; exit 1; }
  SIGNING_IDENTITY="$(<"$SIGNING_IDENTITY_FILE")"
  [[ "$SIGNING_IDENTITY" =~ '^[[:xdigit:]]{40}$' ]] || { print -u2 'The DeskNames signing identity file must contain one certificate SHA-1 fingerprint.'; exit 1; }
fi
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"
if [[ "$SIGNING_IDENTITY" != - ]]; then
  identities="$(security find-identity -p codesigning)"
  [[ "$identities" == *" $SIGNING_IDENTITY "* || "$identities" == *\"$SIGNING_IDENTITY\"* ]] || { print -u2 'The configured code-signing identity is unavailable. Restore it instead of falling back to ad-hoc signing.'; exit 1; }
fi
./scripts/fetch-sparkle.sh
DEST="${1:-$PWD/build}"
mkdir -p "$DEST/DeskNames.app/Contents/MacOS" "$DEST/DeskNames.app/Contents/Resources"
mkdir -p "$DEST/DeskNames.app/Contents/Frameworks"
ditto .build-deps/sparkle/Sparkle.framework "$DEST/DeskNames.app/Contents/Frameworks/Sparkle.framework"
cp .build-deps/sparkle/LICENSE "$DEST/DeskNames.app/Contents/Resources/Sparkle-LICENSE.txt"
cp DeskNames.icns "$DEST/DeskNames.app/Contents/Resources/DeskNames.icns"
xcrun clang -target arm64-apple-macos14.0 -fblocks -fno-objc-arc -Wall -Wextra -Werror -c NativeSpaceMove.m -o "$DEST/NativeSpaceMove.o"
cp THIRD_PARTY_NOTICES.txt "$DEST/DeskNames.app/Contents/Resources/THIRD_PARTY_NOTICES.txt"
xcrun swiftc -j 4 -target arm64-apple-macos14.0 -swift-version 5 -O -framework AppKit -framework SwiftUI -framework Carbon -F .build-deps/sparkle -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks AppUpdater.swift MarketingPreview.swift main.swift MissionControlGeometry.swift AlignmentDiagnostics.swift WindowManager.swift WorkspaceViews.swift Shortcuts.swift PaneModel.swift PaneViews.swift SmartPanes.swift Tests.swift GeometryTests.swift PaneTests.swift WindowActions.swift WindowActionTests.swift PaneInteraction.swift LinkedPanes.swift PaneInteractionTests.swift MovementTests.swift DesktopNavigation.swift DisplayProfiles.swift ScreenAwareWindows.swift LayoutSnapshots.swift WindowRouting.swift WindowRoutingView.swift ScreenLayoutTests.swift "$DEST/NativeSpaceMove.o" -o "$DEST/DeskNames.app/Contents/MacOS/DeskNames"
cat > "$DEST/DeskNames.app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>DeskNames</string>
<key>CFBundleIdentifier</key><string>local.desknames.app</string>
<key>CFBundleIconFile</key><string>DeskNames.icns</string>
<key>CFBundleName</key><string>DeskNames</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.6.0</string>
<key>CFBundleVersion</key><string>28</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>SUFeedURL</key><string>https://raw.githubusercontent.com/Kipung/DeskNames/main/release/appcast.xml</string>
<key>SUEnableAutomaticChecks</key><false/>
<key>SUAutomaticallyUpdate</key><false/>
<key>SUVerifyUpdateBeforeExtraction</key><true/>
<key>SURequireSignedFeed</key><true/>
<key>SUEnableSystemProfiling</key><false/>
<key>SUSignedFeedFailureExpirationInterval</key><integer>0</integer>
</dict></plist>
PLIST
/usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $(cat release/sparkle-public-key.txt)" "$DEST/DeskNames.app/Contents/Info.plist"
SPARKLE="$DEST/DeskNames.app/Contents/Frameworks/Sparkle.framework/Versions/B"
for component in "$SPARKLE/XPCServices/Installer.xpc" "$SPARKLE/XPCServices/Downloader.xpc" "$SPARKLE/Autoupdate" "$SPARKLE/Updater.app" "$DEST/DeskNames.app/Contents/Frameworks/Sparkle.framework"; do
  codesign --force --sign "$SIGNING_IDENTITY" --options runtime "$component"
done
if [[ "$SIGNING_IDENTITY" == - ]]; then
  print -u2 'Ad-hoc signing: Accessibility approval may need renewal after a changed build. See docs/development-signing.md.'
fi
if [[ "$SIGNING_IDENTITY" == - ]]; then
  codesign --force --sign - "$DEST/DeskNames.app"
else
  codesign --force --sign "$SIGNING_IDENTITY" --options runtime --timestamp "$DEST/DeskNames.app"
fi
codesign --verify --deep --strict "$DEST/DeskNames.app"
