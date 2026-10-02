#!/bin/bash
# Build MMFFDev Colour 3.app and package it as a drag-to-Applications DMG, then write the Sparkle
# update feed for it into release/. Outputs: ./MMFFDev-Colour-3.dmg, release/<build>/{dmg, appcast.xml}.
#
# To publish: create a GitHub release tagged b<build> and upload both files from release/<build>.
# The app reads .../releases/latest/download/appcast.xml, so the newest release is the feed.
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
swiftc -O *.swift "${SPARKLE_FLAGS[@]}" -o "$BUILD/MMFFDevColour3"

echo "running self-test..."
"$BUILD/MMFFDevColour3" --self-test > /dev/null || { "$BUILD/MMFFDevColour3" --self-test; exit 1; }

echo "assembling bundle..."
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
mv "$BUILD/MMFFDevColour3" "$APP/Contents/MacOS/MMFFDevColour3"
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
chmod +x "$APP/Contents/MacOS/MMFFDevColour3"
stamp_version "$APP"
add_sparkle "$APP"
add_helper "$APP"
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

# The update feed. generate_appcast signs the dmg with the key in the keychain (vendor/Sparkle/bin/generate_keys).
BUILD="$(git rev-list --count HEAD)"
OUT="release/$BUILD"
rm -rf "$OUT"; mkdir -p "$OUT"
cp "$DMG" "$OUT/${DMG_BASENAME}-b${BUILD}.dmg"
./vendor/Sparkle/bin/generate_appcast \
    --download-url-prefix "https://github.com/mmffdev/OSX-Colour-Picker-DMG/releases/download/b${BUILD}/" \
    --maximum-versions 1 "$OUT" > /dev/null
echo "update feed: $OUT/appcast.xml  (publish as GitHub release b$BUILD with the dmg)"
