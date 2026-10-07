#!/bin/bash
# Open the installed app as a brand-new user, or as yourself. Never touches your own data.
#
#   tools/open.sh new                 a first open, clean: a throwaway home and settings of its own,
#                                     wiped each time, so the setup runs from the welcome page
#   tools/open.sh new permissions     the same, and macOS also forgets every permission it gave the
#                                     app (Screen Recording, Documents), so it asks again; this one
#                                     reaches your own copy too, which asks again next time you open it
#   tools/open.sh new 3               a new user, opened straight at setup step 3
#   tools/open.sh me                  the installed app as you, with your catalogues
#
# A new user here keeps everything in the throwaway home, so it never asks for Documents; the
# Documents question is seen as yourself, after "new permissions".
set -euo pipefail
APP="/Applications/MMFFDev Colour 3.app"
BUNDLE_ID="com.mmffdev.mmffdevcolour3"

case "${1:-}" in
  new)
    if [ "${2:-}" = "permissions" ]; then
        tccutil reset ScreenCapture "$BUNDLE_ID" >/dev/null
        tccutil reset SystemPolicyDocumentsFolder "$BUNDLE_ID" >/dev/null
        defaults delete "$BUNDLE_ID" screenRecordingAsked >/dev/null 2>&1 || true
        defaults delete "$BUNDLE_ID" documentsAllowed >/dev/null 2>&1 || true
        defaults delete "$BUNDLE_ID" documentsRefused >/dev/null 2>&1 || true
        echo "macOS has forgotten the app's Screen Recording and Documents permissions."
    fi
    # Through Launch Services, as a customer opens it, so macOS asks in the app's own name. The app's
    # own --new-user wipes and makes the throwaway home, the same as ticking it in Xcode's scheme.
    STEP=""; case "${2:-}" in [1-9]) STEP="--step $2";; esac
    open -n -a "$APP" --args --new-user $STEP
    echo "Opened as a new user, in a throwaway home that is wiped on the next new-user open."
    ;;
  me)
    open -a "$APP"
    ;;
  *)
    sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
    ;;
esac
