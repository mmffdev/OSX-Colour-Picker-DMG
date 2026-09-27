#!/bin/bash
# Build MMFFDev Colour 2.app and package it as a .pkg installer
# that deposits the app into /Applications.
# Output: ./MMFFDev-Colour-2.pkg
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="MMFFDev Colour 2"
PKG_IDENTIFIER="com.mmffdev.colour2"
PKG_VERSION="2.0.0"
PKG="./MMFFDev-Colour-2.pkg"

STAGE="$(mktemp -d -t mmffdev-colour2-pkg)"
trap 'rm -rf "$STAGE"' EXIT

ROOT="$STAGE/root"
APP="$ROOT/Applications/$APP_NAME.app"
mkdir -p "$ROOT/Applications"

echo "compiling swift..."
swiftc -O Model.swift Helpers.swift LibraryWindow.swift SelfTest.swift main.swift -o "$STAGE/MMFFDevColour2"

echo "running self-test..."
"$STAGE/MMFFDevColour2" --self-test > /dev/null || { "$STAGE/MMFFDevColour2" --self-test; exit 1; }

echo "assembling bundle..."
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
mv "$STAGE/MMFFDevColour2" "$APP/Contents/MacOS/MMFFDevColour2"
cp ../AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
chmod +x "$APP/Contents/MacOS/MMFFDevColour2"
codesign --force --deep --sign - "$APP" 2>&1 | grep -v "replacing existing signature" || true

# Without this the installer "relocates": if a copy of the app already exists
# elsewhere (e.g. ~/Applications from build.sh) it updates that one and
# /Applications never gets the app.
echo "pinning install location..."
COMPONENTS="$STAGE/components.plist"
pkgbuild --analyze --root "$ROOT" "$COMPONENTS" > /dev/null
/usr/libexec/PlistBuddy -c "Set :0:BundleIsRelocatable false" "$COMPONENTS"

echo "building component pkg..."
COMPONENT="$STAGE/component.pkg"
pkgbuild \
    --root "$ROOT" \
    --component-plist "$COMPONENTS" \
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
