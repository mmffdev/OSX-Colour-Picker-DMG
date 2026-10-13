#!/bin/zsh
# Load ten empty, session-only dockable panels into the installed app.
# Quit Colorgain first; normal launches do not load this fixture.
set -eu
app="${1:-/Applications/MMFFDev - Colorgain.app}"
if [[ ! -d "$app" ]]; then
    print -u2 "App not found: $app"
    exit 1
fi
if pgrep -x MMFFDevColour3 >/dev/null; then
    print -u2 "Quit Colorgain, then run this script again to load the panel UI test."
    exit 1
fi
open -a "$app" --args --ui-test-panels
