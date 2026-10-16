#!/usr/bin/env bash
## Stands up docs.colorgain.com (Wiki.js) on the Plesk box. Copy this folder to /root/docs-setup and run as root:
##   ssh mmffdev-admin bash /root/docs-setup/install.sh
## Idempotent. The first visit to https://docs.colorgain.com runs Wiki.js's own setup, where the admin account is made.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
HOST=docs.colorgain.com
SYS=/var/www/vhosts/system/$HOST/conf
step() { printf '\n== %s ==\n' "$*"; }

step "1 subdomain and certificate"
if plesk bin subdomain --list | grep -qx "$HOST"; then echo "exists"; else
  plesk bin subdomain --create docs -domain colorgain.com -www-root $HOST | tail -1
fi
plesk bin site --update $HOST -certificate-name "Lets Encrypt colorgain.com" | tail -1
plesk bin site --update $HOST -ssl-redirect true | tail -1
echo "status: $(plesk bin site --info $HOST | grep 'Domain status' | sed 's/Domain status: *//')"

step "2 wiki.js and postgres in docker"
mkdir -p /var/wiki/db /var/wiki/data
if [ ! -s /var/wiki/.env ]; then
  umask 077; printf 'WIKI_DB_PASSWORD=%s\n' "$(openssl rand -base64 24 | tr -d '/+=' | cut -c1-28)" > /var/wiki/.env
fi
install -m 600 "$HERE/docker-compose.yml" /var/wiki/docker-compose.yml
cd /var/wiki && docker compose up -d --quiet-pull </dev/null 2>&1 | grep -vi 'warn' || true
docker compose ps --format '{{.Name}} {{.Status}}' </dev/null

step "3 plesk nginx proxy"
plesk bin domain --update-web-server-settings $HOST -nginx-proxy-mode false | tail -1
install -m 644 "$HERE/vhost_nginx.conf" "$SYS/vhost_nginx.conf"
install -m 644 "$HERE/vhost.conf" "$SYS/vhost.conf"
plesk sbin httpdmng --reconfigure-domain $HOST
nginx -t 2>&1 | tail -1

step "4 proof"
for i in $(seq 1 30); do curl -fsS -o /dev/null http://127.0.0.1:3000/ </dev/null 2>/dev/null && break; sleep 3; done
echo "wiki:  $(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:3000/)"
echo "https: $(curl -s -o /dev/null -w '%{http_code}' https://$HOST/)  $(curl -s https://$HOST/ | grep -o '<title>[^<]*' | head -1)"
echo "cert:  $(echo | openssl s_client -connect $HOST:443 -servername $HOST 2>/dev/null | openssl x509 -noout -subject | sed 's/subject=//')"
echo "DONE"
