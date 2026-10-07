#!/bin/bash
# Build the Mac App Store edition of MMFFDev Colour 3.
#
#   ./make_appstore.sh            builds a sandboxed Release app, checks its entitlements, runs the
#                                 self-test inside it, installs it as /Applications/MMFFDev - Colorgain.app
#                                 and opens it as a brand-new user, so the Colorgain setup is what you
#                                 see every time. COLORGAIN_OPEN=0 skips the opening.
#   ./make_appstore.sh archive    archives with the Apple Distribution identity and exports the .pkg
#                                 that App Store Connect takes. Needs the Store certificates in the keychain.
#
# The project is generated from appstore/project.yml by XcodeGen (brew install xcodegen), so adding a
# .swift file at the repository root needs nothing else. The direct download keeps ./build.sh.
set -euo pipefail
cd "$(dirname "$0")"

PROJECT="appstore/MMFFDevColour3Store.xcodeproj"
SCHEME="Colorgain"
DERIVED="appstore/build"
APP="$DERIVED/Build/Products/Release/MMFFDev Colour 3.app"
MODE="${1:-build}"

command -v xcodegen >/dev/null || { echo "xcodegen is needed: brew install xcodegen"; exit 1; }
echo "generating project..."
xcodegen generate --spec appstore/project.yml --project appstore --quiet

if [ "$MODE" = "archive" ]; then
    ARCHIVE="$DERIVED/MMFFDevColour3.xcarchive"
    echo "archiving..."
    xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release -derivedDataPath "$DERIVED" \
        CODE_SIGN_STYLE=Automatic "CODE_SIGN_IDENTITY=Apple Distribution" -allowProvisioningUpdates \
        -archivePath "$ARCHIVE" archive -quiet
    echo "exporting for App Store Connect..."
    xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist appstore/ExportOptions.plist \
        -exportPath "$DERIVED/export" -quiet
    echo "exported: $DERIVED/export"
    exit 0
fi

# Signed with the Developer ID when the keychain has one, ad hoc otherwise. Developer ID matters for
# trying the app: the sandbox ties security-scoped bookmarks to a real signing identity, so an ad hoc
# copy forgets every folder the user chose as soon as it quits.
source ./signing.sh
if [ -n "$APP_IDENTITY" ]; then
    echo "building (signed: $APP_IDENTITY)..."
    SIGN=(CODE_SIGN_STYLE=Manual "CODE_SIGN_IDENTITY=$APP_IDENTITY" DEVELOPMENT_TEAM=6QVKGBRP5J PROVISIONING_PROFILE_SPECIFIER=)
else
    echo "building (ad hoc signed; folders chosen will not be remembered between launches)..."
    SIGN=(CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER=)
fi
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release -derivedDataPath "$DERIVED" \
    "${SIGN[@]}" build -quiet

echo "checking entitlements..."
codesign -d --entitlements :- "$APP" 2>/dev/null | grep -q "com.apple.security.app-sandbox" \
    || { echo "the app is not sandboxed"; exit 1; }
if otool -L "$APP/Contents/MacOS/MMFFDevColour3" | grep -q Sparkle; then echo "Sparkle is linked"; exit 1; fi
if /usr/libexec/PlistBuddy -c "Print :SUFeedURL" "$APP/Contents/Info.plist" >/dev/null 2>&1; then echo "Sparkle keys remain"; exit 1; fi

echo "running self-test..."
"$APP/Contents/MacOS/MMFFDevColour3" --self-test

# The Store edition installed beside the direct download, under its own name so the two never
# collide in the Dock or the menu bar. Same bundle identifier: it is the same app, sandboxed.
COLORGAIN="/Applications/MMFFDev - Colorgain.app"
echo "installing $COLORGAIN..."
pkill -f "$COLORGAIN/Contents/MacOS/" 2>/dev/null && sleep 1 || true
rm -rf "$COLORGAIN"
cp -R "$APP" "$COLORGAIN"
/usr/libexec/PlistBuddy -c "Set :CFBundleName MMFFDev - Colorgain" -c "Set :CFBundleDisplayName MMFFDev - Colorgain" "$COLORGAIN/Contents/Info.plist"
if [ -n "$APP_IDENTITY" ]; then
    codesign --force --options runtime --timestamp --sign "$APP_IDENTITY" --preserve-metadata=entitlements "$COLORGAIN" 2>&1 | grep -v "replacing existing signature" || true
else
    codesign --force --sign - --preserve-metadata=entitlements "$COLORGAIN" 2>&1 | grep -v "replacing existing signature" || true
fi
codesign --verify --strict "$COLORGAIN"
echo "installed: $COLORGAIN ($(/usr/libexec/PlistBuddy -c 'Print :ColourBuildCommit' "$COLORGAIN/Contents/Info.plist"))"

if [ "${COLORGAIN_OPEN:-1}" = "1" ]; then
    echo "opening as a new user..."
    open -n -a "$COLORGAIN" --args --new-user
fi
