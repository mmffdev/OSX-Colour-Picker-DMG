#!/bin/bash
# Shared signing/notarisation helpers for v2 build scripts. Source, don't run.
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
