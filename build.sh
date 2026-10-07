#!/bin/bash
# Build and install MMFFDev Colour 3.app into /Applications.
# Re-run after editing any .swift file here.
#
# /Applications, not ~/Applications: the Adobe helper only works from there, and the .pkg installs
# there too, so one copy of the app is kept, not two. No password is needed: /Applications lets any
# administrator write to it, and the app is left owned by whoever built it.
set -euo pipefail
cd "$(dirname "$0")"
source ./signing.sh

APP="/Applications/MMFFDev Colour 3.app"
OLD="$HOME/Applications/MMFFDev Colour 3.app"

echo "compiling swift..."
compile_app MMFFDevColour3

echo "running self-test..."
./MMFFDevColour3 --self-test

echo "assembling bundle..."
# A copy put there by the .pkg belongs to root. Ask macOS once for the password to clear it;
# the copy this script installs belongs to you, so later builds need no password.
if ! rm -rf "$APP" 2>/dev/null; then
    echo "the installed copy belongs to the system; asking for your password to replace it..."
    osascript - "$APP" > /dev/null <<'EOS'
on run argv
    do shell script "rm -rf " & quoted form of (item 1 of argv) with prompt "MMFFDev Colour 3 build wants to replace the installed app." with administrator privileges
end run
EOS
fi
[ -d "$OLD" ] && rm -rf "$OLD" && echo "removed the old copy in ~/Applications"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
cp MMFFDevColour3 "$APP/Contents/MacOS/MMFFDevColour3"
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# The icon of each kind of file the app keeps: colproject.icns, colpalette.icns and the rest.
cp icons/*.icns "$APP/Contents/Resources/"
chmod +x "$APP/Contents/MacOS/MMFFDevColour3"
stamp_version "$APP"
add_sparkle "$APP"
add_helper "$APP"
sign_app "$APP"

rm MMFFDevColour3

echo "installed: $APP"

# What Rick sees after every build is the Studio window, Colorgain's own. OPEN=0 skips it.
if [ "${OPEN:-1}" = "1" ]; then
    pkill -f "$APP/Contents/MacOS/" 2>/dev/null && sleep 1 || true
    open -n -a "$APP" --args --studio
fi
