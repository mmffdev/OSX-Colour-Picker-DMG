#!/bin/bash
# Build MMFFDev Colour 3.app and package it as a .pkg installer
# that deposits the app into /Applications.
# Output: ./MMFFDev-Colour-3.pkg
set -euo pipefail
cd "$(dirname "$0")"
source ./signing.sh

APP_NAME="MMFFDev Colour 3"
PKG_IDENTIFIER="com.mmffdev.colour3"
PKG_VERSION="3.0.0"
PKG="./MMFFDev-Colour-3.pkg"

STAGE="$(mktemp -d -t mmffdev-colour3-pkg)"
trap 'rm -rf "$STAGE"' EXIT

ROOT="$STAGE/root"
APP="$ROOT/Applications/$APP_NAME.app"
mkdir -p "$ROOT/Applications"

echo "compiling swift..."
swiftc -O *.swift -o "$STAGE/MMFFDevColour3"

echo "running self-test..."
"$STAGE/MMFFDevColour3" --self-test > /dev/null || { "$STAGE/MMFFDevColour3" --self-test; exit 1; }

echo "assembling bundle..."
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
mv "$STAGE/MMFFDevColour3" "$APP/Contents/MacOS/MMFFDevColour3"
cp ../AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
chmod +x "$APP/Contents/MacOS/MMFFDevColour3"
sign_app "$APP"

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
SIGN_ARGS=()
if [ -n "$INSTALLER_IDENTITY" ]; then
    echo "signing pkg: $INSTALLER_IDENTITY"
    SIGN_ARGS=(--sign "$INSTALLER_IDENTITY" --timestamp)
else
    echo "pkg unsigned (no Developer ID Installer identity found)"
fi
productbuild \
    --package "$COMPONENT" \
    --identifier "$PKG_IDENTIFIER" \
    --version "$PKG_VERSION" \
    "${SIGN_ARGS[@]}" \
    "$PKG" > /dev/null

notarize "$PKG"

echo "created: $PKG"
