#!/bin/bash
# Build MMFFDev Colour 2.app and package it as a drag-to-Applications DMG.
# Output: ./MMFFDev-Colour-2.dmg
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="MMFFDev Colour 2"
DMG_BASENAME="MMFFDev-Colour-2"
DMG="./${DMG_BASENAME}.dmg"

STAGE="$(mktemp -d -t mmffdev-colour2-dmg)"
BUILD="$(mktemp -d -t mmffdev-colour2-build)"
trap 'rm -rf "$STAGE" "$BUILD"' EXIT

APP="$STAGE/$APP_NAME.app"

echo "compiling swift..."
swiftc -O Model.swift Helpers.swift LibraryWindow.swift SelfTest.swift main.swift -o "$BUILD/MMFFDevColour2"

echo "running self-test..."
"$BUILD/MMFFDevColour2" --self-test > /dev/null || { "$BUILD/MMFFDevColour2" --self-test; exit 1; }

echo "assembling bundle..."
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
mv "$BUILD/MMFFDevColour2" "$APP/Contents/MacOS/MMFFDevColour2"
cp ../AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
chmod +x "$APP/Contents/MacOS/MMFFDevColour2"
codesign --force --deep --sign - "$APP" 2>&1 | grep -v "replacing existing signature" || true

echo "staging dmg layout..."
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"

echo "creating dmg..."
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGE" \
    -fs HFS+ \
    -format UDZO \
    -ov \
    "$DMG" > /dev/null

echo "created: $DMG"
