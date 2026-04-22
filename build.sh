#!/bin/bash
# Build and install MMFFDev Colour.app into ~/Applications.
# Re-run after editing main.swift or make_icon.swift.
set -euo pipefail
cd "$(dirname "$0")"

APP="$HOME/Applications/MMFFDev Colour.app"

# Rebuild icon only if sources changed or .icns is missing
if [ ! -f AppIcon.icns ] || [ make_icon.swift -nt AppIcon.icns ]; then
    echo "building icon..."
    rm -rf AppIcon.iconset
    swift make_icon.swift > /dev/null
    iconutil -c icns AppIcon.iconset -o AppIcon.icns
    rm -rf AppIcon.iconset
fi

echo "compiling swift..."
swiftc -O main.swift -o MMFFDevColour

echo "assembling bundle..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
cp MMFFDevColour "$APP/Contents/MacOS/MMFFDevColour"
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
chmod +x "$APP/Contents/MacOS/MMFFDevColour"
codesign --force --deep --sign - "$APP" 2>&1 | grep -v "replacing existing signature" || true

rm MMFFDevColour

echo "installed: $APP"
