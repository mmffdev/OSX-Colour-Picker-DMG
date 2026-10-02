#!/bin/bash
# One-time: read .env.notarytool and save an app-specific password into the
# login keychain as notarytool profile "AC_PASSWORD". Values are never printed.
set -euo pipefail
cd "$(dirname "$0")"

ENV_FILE=".env.notarytool"
[ -f "$ENV_FILE" ] || { echo "missing $ENV_FILE"; exit 1; }
# shellcheck disable=SC1090
source "$ENV_FILE"

: "${APPLE_ID:?APPLE_ID not set in $ENV_FILE}"
: "${TEAM_ID:?TEAM_ID not set in $ENV_FILE}"
: "${APP_SPECIFIC_PASSWORD:?APP_SPECIFIC_PASSWORD not set in $ENV_FILE}"

xcrun notarytool store-credentials "${NOTARY_PROFILE:-AC_PASSWORD}" \
    --apple-id "$APPLE_ID" \
    --team-id "$TEAM_ID" \
    --password "$APP_SPECIFIC_PASSWORD"

echo "stored. verify with: xcrun notarytool history --keychain-profile ${NOTARY_PROFILE:-AC_PASSWORD}"
