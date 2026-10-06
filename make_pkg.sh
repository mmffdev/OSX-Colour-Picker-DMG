#!/bin/bash
# Build MMFFDev Colour 3.app and package it as a .pkg installer. The installer offers two homes:
# /Applications for every user, or ~/Applications for the person installing. installer/welcome.html
# explains the difference; installer/distribution.xml is the installer's layout.
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
APP="$ROOT/$APP_NAME.app"

echo "compiling swift..."
compile_app "$STAGE/MMFFDevColour3"

echo "running self-test..."
"$STAGE/MMFFDevColour3" --self-test > /dev/null || { "$STAGE/MMFFDevColour3" --self-test; exit 1; }

echo "assembling bundle..."
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
mv "$STAGE/MMFFDevColour3" "$APP/Contents/MacOS/MMFFDevColour3"
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp icons/*.icns "$APP/Contents/Resources/"
chmod +x "$APP/Contents/MacOS/MMFFDevColour3"
stamp_version "$APP"
add_sparkle "$APP"
add_helper "$APP"
sign_app "$APP"

# Without this the installer "relocates": if a copy of the app already exists
# elsewhere it updates that one and the chosen folder never gets the app.
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
    --install-location "/Applications" \
    "$COMPONENT" > /dev/null

echo "wrapping distribution pkg..."
rm -f "$PKG"
cp installer/distribution.xml "$STAGE/distribution.xml"
SIGN_ARGS=()
if [ -n "$INSTALLER_IDENTITY" ]; then
    echo "signing pkg: $INSTALLER_IDENTITY"
    SIGN_ARGS=(--sign "$INSTALLER_IDENTITY" --timestamp)
else
    echo "pkg unsigned (no Developer ID Installer identity found)"
fi
productbuild \
    --distribution "$STAGE/distribution.xml" \
    --resources installer \
    --package-path "$STAGE" \
    "${SIGN_ARGS[@]}" \
    "$PKG" > /dev/null

notarize "$PKG"

echo "created: $PKG"
