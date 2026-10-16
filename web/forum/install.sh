#!/usr/bin/env bash
## Stands up forum.colorgain.com on the Plesk box. Run as root with this folder copied to /root/forum-setup:
##   ssh mmffdev-admin bash /root/forum-setup/install.sh
## The admin is admin@colorgain.com, username Colorgain; its credentials come from web/forum/.env.forum, which is never committed.
## Idempotent: every step checks before it acts. Docker calls take </dev/null so they never eat this script when it is piped in. Takes 10-15 minutes, almost all of it the Discourse bootstrap.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
HOST=forum.colorgain.com
SYS=/var/www/vhosts/system/$HOST/conf
step() { printf '\n== %s ==\n' "$*"; }

step "1 subdomain and certificate"
if plesk bin subdomain --list | grep -qx "$HOST"; then echo "exists"; else
  plesk bin subdomain --create forum -domain colorgain.com -www-root $HOST
fi
plesk bin site --update $HOST -certificate-name "Lets Encrypt colorgain.com"
plesk bin site --update $HOST -ssl-redirect true
echo "dns: $(plesk bin dns --info colorgain.com | grep '^forum' || echo MISSING)"
STATUS="$(plesk bin site --info $HOST | grep 'Domain status' | sed 's/Domain status: *//')"
echo "status: $STATUS"
case "$STATUS" in *suspend*) echo "The subdomain inherited a suspended customer (cgain). Activate the customer in Plesk, then rerun.";; esac

step "2 mailbox forum@colorgain.com"
if [ ! -s /root/.colorgain-forum-smtp ]; then
  umask 077; openssl rand -base64 24 | tr -d '/+=' | cut -c1-28 > /root/.colorgain-forum-smtp
fi
PW="$(cat /root/.colorgain-forum-smtp)"
if plesk bin mail --info forum@colorgain.com >/dev/null 2>&1; then echo "exists"; else
  plesk bin mail --create forum@colorgain.com -passwd "$PW" -mailbox true
fi

step "3 discourse launcher"
test -d /var/discourse || git clone -q https://github.com/discourse/discourse_docker.git /var/discourse
chmod 700 /var/discourse/containers
sed "s|__SMTP_PASSWORD__|$PW|" "$HERE/app.yml" > /var/discourse/containers/app.yml
chmod 600 /var/discourse/containers/app.yml
echo "app.yml written ($(grep -c . /var/discourse/containers/app.yml) lines)"

step "4 plesk nginx proxy"
install -m 644 "$HERE/vhost_nginx.conf" "$SYS/vhost_nginx.conf"
install -m 644 "$HERE/vhost.conf" "$SYS/vhost.conf"
plesk bin domain --update-web-server-settings $HOST -nginx-proxy-mode false | tail -1
plesk sbin httpdmng --reconfigure-domain $HOST
nginx -t 2>&1 | tail -1

step "5 bootstrap (the long part)"
cd /var/discourse
if docker ps -a --format '{{.Names}}' | grep -qx app; then echo "container exists, rebuilding"; ./launcher rebuild app </dev/null; else
  ./launcher bootstrap app </dev/null || { echo "BOOTSTRAP FAILED"; exit 1; }
  ./launcher start app </dev/null
fi

step "6 admin account"
if [ ! -s /root/.colorgain-forum-admin ]; then
  umask 077; openssl rand -base64 24 | tr -d '/+=' | cut -c1-24 > /root/.colorgain-forum-admin
fi
APW="$(cat /root/.colorgain-forum-admin)"
for i in $(seq 1 30); do curl -fsS -o /dev/null http://127.0.0.1:8080/srv/status && break; sleep 5; done
printf 'admin@colorgain.com\n%s\n%s\nY\n' "$APW" "$APW" | docker exec -i app bash -lc 'cd /var/www/discourse && su discourse -c "bundle exec rake admin:create"' 2>&1 | grep -vi password || true
docker exec -i app bash -lc 'cd /var/www/discourse && su discourse -c "bundle exec rails runner \"u=User.find_by_username(%q(user1)); if u then UsernameChanger.change(u,%q(Colorgain)); u.reload.update!(name: %q(Colorgain)) end; puts User.where(admin: true).pluck(:username).inspect\""' </dev/null 2>&1 | grep -v warning | tail -1

step "7 proof"
echo "status: $(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8080/srv/status)"
echo "public: $(curl -s -o /dev/null -w '%{http_code} %{redirect_url}' https://$HOST/)"
echo "cert:   $(echo | openssl s_client -connect $HOST:443 -servername $HOST 2>/dev/null | openssl x509 -noout -subject -enddate | tr '\n' ' ')"
echo "DONE"
