#!/bin/bash
# Build and install MMFFDev Colour 2.app into ~/Applications.
# Installs alongside v1 — separate app, separate library. Re-run after editing any .swift file here.
set -euo pipefail
cd "$(dirname "$0")"

APP="$HOME/Applications/MMFFDev Colour 2.app"

echo "compiling swift..."
swiftc -O Model.swift Helpers.swift LibraryWindow.swift SelfTest.swift main.swift -o MMFFDevColour2

echo "running self-test..."
./MMFFDevColour2 --self-test

echo "assembling bundle..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
cp MMFFDevColour2 "$APP/Contents/MacOS/MMFFDevColour2"
cp ../AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
chmod +x "$APP/Contents/MacOS/MMFFDevColour2"
codesign --force --deep --sign - "$APP" 2>&1 | grep -v "replacing existing signature" || true

rm MMFFDevColour2

echo "installed: $APP"
