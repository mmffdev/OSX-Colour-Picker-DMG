#!/bin/bash
# Build and install Colorgain.app into /Applications.
# Re-run after editing any .swift file here.
#
# /Applications, not ~/Applications: the Adobe helper only works from there, and the .pkg installs
# there too, so one copy of the app is kept, not two. No password is needed: /Applications lets any
# administrator write to it, and the app is left owned by whoever built it.
set -euo pipefail
cd "$(dirname "$0")"
source ./signing.sh

APP="/Applications/Colorgain.app"

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
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
cp MMFFDevColour3 "$APP/Contents/MacOS/MMFFDevColour3"
cp -R ProofingResources "$APP/Contents/Resources/"
cp -R Help/Resources "$APP/Contents/Resources/HelpResources"
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp ColorgainLogo.png "$APP/Contents/Resources/ColorgainLogo.png"
cp ColorgainLogo.pdf "$APP/Contents/Resources/ColorgainLogo.pdf"
# The icon of each kind of file the app keeps: colproject.icns, colpalette.icns and the rest.
cp icons/*.icns "$APP/Contents/Resources/"
chmod +x "$APP/Contents/MacOS/MMFFDevColour3"
stamp_version "$APP"
add_sparkle "$APP"
add_helper "$APP"
sign_app "$APP"

rm MMFFDevColour3

echo "installed: $APP"

# Rick’s development machine has one visible installed edition. Retire only known
# Colorgain predecessors after the new app has built, passed and been signed.
python3 - "$APP" <<'PY_CLEANUP'
import datetime, os, plistlib, shutil, signal, subprocess, sys
from pathlib import Path
keep = Path(sys.argv[1])
trash = Path.home() / '.Trash'
identities = {'com.mmffdev.mmffdevcolour', 'com.mmffdev.mmffdevcolour2', 'com.mmffdev.mmffdevcolour3'}
for root in [Path('/Applications'), Path.home() / 'Applications']:
    if not root.is_dir():
        continue
    for candidate in root.glob('*.app'):
        if candidate == keep or candidate.is_symlink():
            continue
        try:
            metadata = plistlib.loads((candidate / 'Contents/Info.plist').read_bytes())
        except (OSError, plistlib.InvalidFileException):
            continue
        if metadata.get('CFBundleIdentifier') not in identities:
            continue
        for process in subprocess.check_output(['ps', '-axo', 'pid=,command='], text=True).splitlines():
            fields = process.strip().split(None, 1)
            if len(fields) == 2 and fields[1].startswith(str(candidate) + '/Contents/MacOS/'):
                try:
                    os.kill(int(fields[0]), signal.SIGTERM)
                except ProcessLookupError:
                    pass
        trash.mkdir(exist_ok=True)
        destination = trash / candidate.name
        if destination.exists():
            destination = trash / (candidate.stem + ' ' + datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f') + '.app')
        try:
            shutil.move(str(candidate), str(destination))
            print('moved old app to Trash:', candidate)
        except PermissionError:
            print('old app requires Finder authentication to remove:', candidate, file=sys.stderr)
PY_CLEANUP

# What Rick sees after every build is the Studio window, Colorgain's own. OPEN=0 skips it.
if [ "${OPEN:-1}" = "1" ]; then
    pkill -f "$APP/Contents/MacOS/" 2>/dev/null && sleep 1 || true
    open -n -a "$APP"
fi
