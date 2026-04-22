#!/bin/bash
# Build MMFFDev Colour.app and package it as a drag-to-Applications DMG.
# Output: ./MMFFDev-Colour.dmg
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="MMFFDev Colour"
DMG_BASENAME="MMFFDev-Colour"
DMG="./${DMG_BASENAME}.dmg"

STAGE="$(mktemp -d -t mmffdev-colour-dmg)"
trap 'rm -rf "$STAGE"' EXIT

APP="$STAGE/$APP_NAME.app"

# Rebuild icon only if sources changed or .icns is missing
if [ ! -f AppIcon.icns ] || [ make_icon.swift -nt AppIcon.icns ]; then
    echo "building icon..."
    rm -rf AppIcon.iconset
    swift make_icon.swift > /dev/null
    iconutil -c icns AppIcon.iconset -o AppIcon.icns
    rm -rf AppIcon.iconset
fi

echo "compiling swift..."
swiftc -O main.swift -o "$STAGE/MMFFDevColour"

echo "assembling bundle..."
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
mv "$STAGE/MMFFDevColour" "$APP/Contents/MacOS/MMFFDevColour"
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
chmod +x "$APP/Contents/MacOS/MMFFDevColour"
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
