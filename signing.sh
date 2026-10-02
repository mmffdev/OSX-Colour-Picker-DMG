#!/bin/bash
# Shared signing/notarisation helpers for the build scripts. Source, don't run.
#
# Picks up "Developer ID Application" / "Developer ID Installer" identities
# from the keychain; falls back to ad-hoc signing if absent. Notarises when a
# notarytool keychain profile exists (see store_notary_credentials.sh).
# Override with env vars: APP_IDENTITY, INSTALLER_IDENTITY, NOTARY_PROFILE, NOTARIZE=0.

NOTARY_PROFILE="${NOTARY_PROFILE:-AC_PASSWORD}"

_find_identity() {
    security find-identity -v -p "$1" 2>/dev/null \
        | grep -o "\"$2: [^\"]*\"" | head -1 | tr -d '"'
}

APP_IDENTITY="${APP_IDENTITY:-$(_find_identity codesigning "Developer ID Application")}"
INSTALLER_IDENTITY="${INSTALLER_IDENTITY:-$(_find_identity basic "Developer ID Installer")}"

if [ -z "${NOTARIZE:-}" ]; then
    if [ -n "$APP_IDENTITY" ] && xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
        NOTARIZE=1
    else
        NOTARIZE=0
    fi
fi

# Compiler flags that link Sparkle. The second rpath lets the bare binary run the self-test from the
# build folder before it is put in a bundle.
SPARKLE_FLAGS=(-F vendor/Sparkle -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks
               -Xlinker -rpath -Xlinker "$PWD/vendor/Sparkle")

# stamp_version <path/to/App.app>  — the build number is the commit count, so every build is newer than the last.
stamp_version() {
    local build
    build="$(git rev-list --count HEAD)"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build" "$1/Contents/Info.plist"
    echo "build $build"
}

# add_sparkle <path/to/App.app>  — puts Sparkle.framework in the bundle and signs each of its parts
# with our identity, innermost first, as notarisation requires. Call before sign_app.
add_sparkle() {
    local fw="$1/Contents/Frameworks/Sparkle.framework"
    mkdir -p "$1/Contents/Frameworks"
    rm -rf "$fw"
    cp -R vendor/Sparkle/Sparkle.framework "$fw"
    local v="$fw/Versions/B"
    if [ -n "$APP_IDENTITY" ]; then
        for part in "$v/XPCServices/Installer.xpc" "$v/XPCServices/Downloader.xpc" "$v/Autoupdate" "$v/Updater.app" "$fw"; do
            codesign --force --options runtime --timestamp --sign "$APP_IDENTITY" "$part"
        done
    else
        codesign --force --deep --sign - "$fw"
    fi
}

# add_helper <path/to/App.app>  — builds the Adobe helper into the bundle and signs it. Call before sign_app.
# The helper is what the system runs as root once the user allows it; see AdobeHelperRules.swift.
add_helper() {
    local helper="$1/Contents/MacOS/MMFFDevColour3Helper"
    local id="com.mmffdev.mmffdevcolour3.helper"
    echo "compiling helper..."
    swiftc -O helper/main.swift AdobeHelperRules.swift -o "$helper"
    mkdir -p "$1/Contents/Library/LaunchDaemons"
    cp "helper/$id.plist" "$1/Contents/Library/LaunchDaemons/$id.plist"
    if [ -n "$APP_IDENTITY" ]; then
        codesign --force --options runtime --timestamp --identifier "$id" --sign "$APP_IDENTITY" "$helper"
    else
        codesign --force --identifier "$id" --sign - "$helper"
    fi
}

# sign_app <path/to/App.app>
sign_app() {
    if [ -n "$APP_IDENTITY" ]; then
        echo "signing app: $APP_IDENTITY"
        codesign --force --options runtime --timestamp --sign "$APP_IDENTITY" "$1"
    else
        echo "signing app: ad-hoc (no Developer ID Application identity found)"
        codesign --force --sign - "$1"
    fi
    codesign --verify --strict "$1"
}

# sign_dmg <path/to/file.dmg>
sign_dmg() {
    [ -n "$APP_IDENTITY" ] || return 0
    echo "signing dmg..."
    codesign --force --timestamp --sign "$APP_IDENTITY" "$1"
}

# notarize <path/to/file.dmg|.pkg>  — submits, waits, staples.
notarize() {
    if [ "$NOTARIZE" != "1" ]; then
        echo "notarisation skipped (no '$NOTARY_PROFILE' keychain profile, or NOTARIZE=0)"
        return 0
    fi
    echo "notarising $(basename "$1") (this can take a few minutes)..."
    xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait
    echo "stapling..."
    xcrun stapler staple "$1"
}
