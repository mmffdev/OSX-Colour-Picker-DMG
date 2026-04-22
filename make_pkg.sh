#!/bin/bash
# Build MMFFDev Colour.app and package it as a .pkg installer
# that deposits the app into /Applications.
# Output: ./MMFFDev-Colour.pkg
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="MMFFDev Colour"
PKG_IDENTIFIER="com.mmffdev.colour"
PKG_VERSION="1.0.1"
PKG="./MMFFDev-Colour.pkg"

STAGE="$(mktemp -d -t mmffdev-colour-pkg)"
trap 'rm -rf "$STAGE"' EXIT

ROOT="$STAGE/root"
APP="$ROOT/Applications/$APP_NAME.app"
mkdir -p "$ROOT/Applications"

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

echo "building component pkg..."
COMPONENT="$STAGE/component.pkg"
pkgbuild \
    --root "$ROOT" \
    --identifier "$PKG_IDENTIFIER" \
    --version "$PKG_VERSION" \
    --install-location "/" \
    "$COMPONENT" > /dev/null

echo "wrapping distribution pkg..."
rm -f "$PKG"
productbuild \
    --package "$COMPONENT" \
    --identifier "$PKG_IDENTIFIER" \
    --version "$PKG_VERSION" \
    "$PKG" > /dev/null

echo "created: $PKG"
