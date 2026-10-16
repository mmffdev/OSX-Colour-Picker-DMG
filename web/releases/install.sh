#!/usr/bin/env bash
## Stands up releases.colorgain.com (Forgejo) on the Plesk box. Copy this folder to /root/releases-setup and run as root:
##   ssh mmffdev-admin bash /root/releases-setup/install.sh
## Idempotent. The admin account comes from .env.releases beside this script (accountName, accountUsername, password), never committed.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
HOST=releases.colorgain.com
SYS=/var/www/vhosts/system/$HOST/conf
step() { printf '\n== %s ==\n' "$*"; }

step "1 subdomain and certificate"
if plesk bin subdomain --list | grep -qx "$HOST"; then echo "exists"; else
  plesk bin subdomain --create releases -domain colorgain.com -www-root $HOST | tail -1
fi
plesk bin site --update $HOST -certificate-name "Lets Encrypt colorgain.com" | tail -1
plesk bin site --update $HOST -ssl-redirect true | tail -1
echo "status: $(plesk bin site --info $HOST | grep 'Domain status' | sed 's/Domain status: *//')"

step "2 mailbox releases@colorgain.com"
if [ ! -s /root/.colorgain-releases-smtp ]; then
  (umask 077; openssl rand -base64 24 | tr -d '/+=' | cut -c1-28 > /root/.colorgain-releases-smtp)
fi
if plesk bin mail --info releases@colorgain.com >/dev/null 2>&1; then echo "exists"; else
  plesk bin mail --create releases@colorgain.com -passwd "$(cat /root/.colorgain-releases-smtp)" -mailbox true | tail -1
fi

step "3 forgejo and postgres in docker"
mkdir -p /var/forgejo/db /var/forgejo/data
chmod 755 /var/forgejo /var/forgejo/data; chown 1000:1000 /var/forgejo/data   # Forgejo runs as uid 1000 inside the container
if [ ! -s /var/forgejo/.env ]; then
  (umask 077
  printf 'FORGEJO_DB_PASSWORD=%s\nFORGEJO_SMTP_PASSWORD=%s\n' "$(openssl rand -base64 24 | tr -d '/+=' | cut -c1-28)" "$(cat /root/.colorgain-releases-smtp)" > /var/forgejo/.env)
fi
install -m 600 "$HERE/docker-compose.yml" /var/forgejo/docker-compose.yml
cd /var/forgejo && docker compose up -d --quiet-pull </dev/null 2>&1 | grep -vi 'warn' || true
docker compose ps --format '{{.Name}} {{.Status}}' </dev/null

step "4 plesk nginx proxy"
plesk bin domain --update-web-server-settings $HOST -nginx-proxy-mode false | tail -1
install -m 644 "$HERE/vhost_nginx.conf" "$SYS/vhost_nginx.conf"
install -m 644 "$HERE/vhost.conf" "$SYS/vhost.conf"
plesk sbin httpdmng --reconfigure-domain $HOST
nginx -t 2>&1 | tail -1

step "5 admin account"
for i in $(seq 1 40); do curl -fsS -o /dev/null http://127.0.0.1:3001/api/healthz </dev/null 2>/dev/null && break; sleep 3; done
if [ -s "$HERE/.env.releases" ]; then
  E="$(grep -i '^accountName:' "$HERE/.env.releases" | awk '{print $2}')"
  U="$(grep -i '^accountUsername:' "$HERE/.env.releases" | awk '{print $2}')"
  P="$(grep -i '^password:' "$HERE/.env.releases" | cut -d' ' -f2-)"
  if docker compose exec -T -u git forgejo forgejo --config /data/gitea/conf/app.ini admin user list </dev/null | awk '{print $2}' | grep -qx "$U"; then echo "admin $U exists"; else
    docker compose exec -T -u git forgejo forgejo --config /data/gitea/conf/app.ini admin user create --admin --username "$U" --email "$E" --password "$P" --must-change-password=false </dev/null | tail -1
  fi
else echo "no .env.releases beside this script: admin not created yet"; fi

step "6 proof"
echo "health: $(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:3001/api/healthz)"
echo "https:  $(curl -s -o /dev/null -w '%{http_code} -> %{redirect_url}' https://$HOST/)"
echo "login:  $(curl -s -o /dev/null -w '%{http_code}' https://$HOST/user/login)  $(curl -s https://$HOST/user/login | grep -o '<title>[^<]*' | head -1)"
echo "cert:   $(echo | openssl s_client -connect $HOST:443 -servername $HOST 2>/dev/null | openssl x509 -noout -subject | sed 's/subject=//')"
echo "DONE"
