#!/usr/bin/env bash
## Builds docs.colorgain.com from Help/Resources and copies the static output to the Plesk box.
##   web/docs/deploy.sh          build and deploy
##   BUILD=0 web/docs/deploy.sh  deploy the last build
set -euo pipefail
cd "$(dirname "$0")"
HOST=docs.colorgain.com
DEST="/var/www/vhosts/colorgain.com/$HOST/"   # owned by the subscription's system user, as Plesk expects
[ -d node_modules ] || npm ci --no-audit --no-fund
[ "${BUILD:-1}" = 0 ] || npm run build
rsync -az --delete --chown=colorgain.com_5uw6in0vfx:psacln dist/ "mmffdev-admin:$DEST"
echo "deployed: $(find dist -name '*.html' | wc -l | tr -d ' ') pages"
echo "https: $(curl -s -o /dev/null -w '%{http_code}' https://$HOST/)  $(curl -s https://$HOST/ | grep -o '<title>[^<]*' | head -1)"
echo "getting started: $(curl -s -o /dev/null -w '%{http_code}' https://$HOST/getting-started/)"
