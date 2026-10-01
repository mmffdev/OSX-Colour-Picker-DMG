#!/bin/bash
# Build and install MMFFDev Colour 3.app into ~/Applications.
# Installs alongside v1 and v2 — separate app, separate library. Re-run after editing any .swift file here.
set -euo pipefail
cd "$(dirname "$0")"
source ./signing.sh

APP="$HOME/Applications/MMFFDev Colour 3.app"

echo "compiling swift..."
swiftc -O *.swift -o MMFFDevColour3

echo "running self-test..."
./MMFFDevColour3 --self-test

echo "assembling bundle..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
cp MMFFDevColour3 "$APP/Contents/MacOS/MMFFDevColour3"
cp ../AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
chmod +x "$APP/Contents/MacOS/MMFFDevColour3"
sign_app "$APP"

rm MMFFDevColour3

echo "installed: $APP"
