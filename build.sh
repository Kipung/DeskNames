#!/bin/zsh
set -eu
cd "${0:A:h}"
DEST="${1:-$PWD/build}"
mkdir -p "$DEST/DeskNames.app/Contents/MacOS" "$DEST/DeskNames.app/Contents/Resources"
cp DeskNames.icns "$DEST/DeskNames.app/Contents/Resources/DeskNames.icns"
xcrun clang -target arm64-apple-macos14.0 -fblocks -fno-objc-arc -Wall -Wextra -Werror -c NativeSpaceMove.m -o "$DEST/NativeSpaceMove.o"
cp THIRD_PARTY_NOTICES.txt "$DEST/DeskNames.app/Contents/Resources/THIRD_PARTY_NOTICES.txt"
xcrun swiftc -j 4 -target arm64-apple-macos14.0 -swift-version 5 -O -framework AppKit -framework SwiftUI -framework Carbon main.swift MissionControlGeometry.swift AlignmentDiagnostics.swift WindowManager.swift WorkspaceViews.swift Shortcuts.swift PaneModel.swift PaneViews.swift SmartPanes.swift Tests.swift GeometryTests.swift PaneTests.swift WindowActions.swift WindowActionTests.swift DesktopNavigation.swift DisplayProfiles.swift ScreenAwareWindows.swift LayoutSnapshots.swift WindowRouting.swift WindowRoutingView.swift ScreenLayoutTests.swift "$DEST/NativeSpaceMove.o" -o "$DEST/DeskNames.app/Contents/MacOS/DeskNames"
cat > "$DEST/DeskNames.app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>DeskNames</string>
<key>CFBundleIdentifier</key><string>local.desknames.app</string>
<key>CFBundleIconFile</key><string>DeskNames.icns</string>
<key>CFBundleName</key><string>DeskNames</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.5.0</string>
<key>CFBundleVersion</key><string>22</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$DEST/DeskNames.app"
