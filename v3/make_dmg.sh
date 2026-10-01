#!/bin/bash
# Build MMFFDev Colour 3.app and package it as a drag-to-Applications DMG.
# Output: ./MMFFDev-Colour-3.dmg
set -euo pipefail
cd "$(dirname "$0")"
source ./signing.sh

APP_NAME="MMFFDev Colour 3"
DMG_BASENAME="MMFFDev-Colour-3"
DMG="./${DMG_BASENAME}.dmg"

STAGE="$(mktemp -d -t mmffdev-colour3-dmg)"
BUILD="$(mktemp -d -t mmffdev-colour3-build)"
trap 'rm -rf "$STAGE" "$BUILD"' EXIT

APP="$STAGE/$APP_NAME.app"

echo "compiling swift..."
swiftc -O *.swift -o "$BUILD/MMFFDevColour3"

echo "running self-test..."
"$BUILD/MMFFDevColour3" --self-test > /dev/null || { "$BUILD/MMFFDevColour3" --self-test; exit 1; }

echo "assembling bundle..."
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
mv "$BUILD/MMFFDevColour3" "$APP/Contents/MacOS/MMFFDevColour3"
cp ../AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
chmod +x "$APP/Contents/MacOS/MMFFDevColour3"
sign_app "$APP"

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

sign_dmg "$DMG"
notarize "$DMG"

echo "created: $DMG"
