#!/bin/bash
# make-app-bundle.sh
# Builds SessionHawk in release mode and packages it into a proper .app bundle
# so UNUserNotificationCenter (native notifications) works.
#
# Usage: ./scripts/make-app-bundle.sh [output-dir]
#   output-dir defaults to ./dist

set -euo pipefail

cd "$(dirname "$0")/.."

OUT_DIR="${1:-dist}"
APP="$OUT_DIR/SessionHawk.app"

# Universal binary (arm64 + x86_64) so one release zip serves both Apple
# Silicon and Intel Macs. Built as two per-triple slices + lipo because
# `swift build --arch --arch` requires full Xcode (xcbuild), not just CLT.
echo "▸ Building arm64 slice..."
swift build -c release --triple arm64-apple-macosx14.0
echo "▸ Building x86_64 slice..."
swift build -c release --triple x86_64-apple-macosx14.0
BINARY=".build/SessionHawk-universal"
lipo -create -output "$BINARY" \
    .build/arm64-apple-macosx/release/SessionHawk \
    .build/x86_64-apple-macosx/release/SessionHawk
echo "▸ Universal binary: $(lipo -archs "$BINARY")"

echo "▸ Assembling $APP ..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BINARY" "$APP/Contents/MacOS/SessionHawk"
cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp assets/menubar-hawk.png "$APP/Contents/Resources/menubar-hawk.png"

# Embed the helper scripts and launchd templates so an installed app is fully
# self-contained — hooks and agents reference stable /Applications paths.
mkdir -p "$APP/Contents/Resources/scripts" "$APP/Contents/Resources/launchd"
cp scripts/sessionhawk-claude-hook.sh \
   scripts/sessionhawk-heh.sh \
   scripts/feed-live-sessions.sh \
   scripts/install-hooks.sh \
   scripts/uninstall.sh \
   scripts/sessionhawk-hook.sh \
   "$APP/Contents/Resources/scripts/"
cp launchd/*.plist "$APP/Contents/Resources/launchd/"
chmod +x "$APP/Contents/Resources/scripts/"*.sh

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>SessionHawk</string>
    <key>CFBundleIdentifier</key>
    <string>com.sessionhawk.sessionhawk</string>
    <key>CFBundleName</key>
    <string>SessionHawk</string>
    <key>CFBundleDisplayName</key>
    <string>SessionHawk</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.3.0</string>
    <key>CFBundleVersion</key>
    <string>2</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>SessionHawk focuses your terminal window when you click a session.</string>
</dict>
</plist>
PLIST

# Ad-hoc codesign so macOS treats the bundle as a stable identity
# (required for notification permission to persist across rebuilds)
codesign --force --deep --sign - "$APP"

# Install to /Applications: Notification Center resolves icons through the
# LaunchServices registration, so the app needs a stable path — a repeatedly
# deleted/rebuilt dist/ bundle leaves stale registrations (generic icon with
# a prohibitory overlay on notification banners).
INSTALL_APP="/Applications/SessionHawk.app"
rm -rf "$INSTALL_APP"
ditto "$APP" "$INSTALL_APP"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$INSTALL_APP"

echo "✅ Done: $INSTALL_APP (build artifact: $APP)"
echo "   Launch with: open $INSTALL_APP"
