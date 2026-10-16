#!/usr/bin/env bash
## Deploys colorgain.com: rsyncs this folder to /var/site/src on the Plesk box, where the container installs, migrates,
## builds and serves it (NO_BUILD=1 skips the rebuild and only finishes); creates the owner and an API key from .env.site on the first run; switches the live domain to
## the app only once it answers. Idempotent.   web/site/deploy.sh
set -euo pipefail
cd "$(dirname "$0")"
HOST=colorgain.com
## Migrations are generated on the server on a first deploy: bring any back first, or the push below would delete them.
mkdir -p src/migrations
rsync -az mmffdev-admin:/var/site/src/src/migrations/ ./src/migrations/ 2>/dev/null || true
rsync -az --delete --exclude node_modules --exclude .next --exclude .git --exclude .env.site --exclude .env \
  --exclude 'public/media' ./ mmffdev-admin:/var/site/src/
scp -q .env.site mmffdev-admin:/var/site/.env.site
ssh mmffdev-admin NO_BUILD="${NO_BUILD:-0}" bash -s <<'REMOTE'
set -euo pipefail
HOST=colorgain.com; SYS=/var/www/vhosts/system/$HOST/conf; APP=http://127.0.0.1:3002
step() { printf '\n== %s ==\n' "$*"; }
cd /var/site; chmod 600 .env.site; . ./.env
install -m 600 /var/site/src/docker-compose.yml /var/site/docker-compose.yml   # compose runs from /var/site, beside .env
step "1 runtime env"
umask 077
cat > site.env <<ENV
DATABASE_URL=postgres://site:${SITE_DB_PASSWORD}@db:5432/site
PAYLOAD_SECRET=${PAYLOAD_SECRET}
NEXT_PUBLIC_SERVER_URL=https://colorgain.com
PREVIEW_SECRET=${PREVIEW_SECRET}
CRON_SECRET=${CRON_SECRET}
SMTP_HOST=mmffdev.com
SMTP_PORT=465
SMTP_USER=hello@colorgain.com
SMTP_PASS=${SITE_SMTP_PASSWORD}
SMTP_FROM_ADDRESS=hello@colorgain.com
ENV
umask 022
chown -R 1000:1000 /var/site/src /var/site/media
echo "written"
step "2 containers (install, migrate, build, serve: several minutes on a fresh deploy)"
if [ "${NO_BUILD:-0}" = 1 ]; then docker compose up -d site </dev/null 2>&1 | grep -vi warn || true   # NO_BUILD=1: finish a deploy already running
else docker compose up -d --force-recreate site </dev/null 2>&1 | grep -vi warn || true; fi
for i in $(seq 1 120); do curl -fsS -o /dev/null "$APP/admin/login" </dev/null 2>/dev/null && break; sleep 5; done
docker compose ps --format '{{.Name}} {{.Status}}' </dev/null
echo "app: $(curl -s -o /dev/null -w '%{http_code}' $APP/admin/login)"
step "3 owner and api key"
python3 - <<'PY'
import json, urllib.request, uuid, pathlib
env = {k.strip(): v.strip() for k, v in (l.split(':', 1) for l in open('/var/site/.env.site') if ':' in l and not l.startswith('#'))}
API = 'http://127.0.0.1:3002/api'
def call(path, data=None, token=None, method=None):
    req = urllib.request.Request(API + path, data=json.dumps(data).encode() if data is not None else None,
        headers={'Content-Type': 'application/json', **({'Authorization': 'JWT ' + token} if token else {})}, method=method or ('POST' if data is not None else 'GET'))
    try: return json.load(urllib.request.urlopen(req))
    except urllib.error.HTTPError as e: return {'error': e.code, 'body': e.read().decode()[:200]}
r = call('/users/first-register', {'email': env['accountName'], 'password': env['password'], 'name': env['accountUsername']})
print('owner:', 'created' if 'user' in r else ('exists' if r.get('error') in (400, 403) else r))
login = call('/users/login', {'email': env['accountName'], 'password': env['password']})
tok, uid = login.get('token'), login.get('user', {}).get('id')
print('login:', 'ok' if tok else login)
keyfile = pathlib.Path('/root/.colorgain-site-api')
if not keyfile.exists():
    key = str(uuid.uuid4())
    r = call(f'/users/{uid}', {'enableAPIKey': True, 'apiKey': key}, tok, 'PATCH')
    if 'doc' in r: keyfile.write_text(key + '\n'); keyfile.chmod(0o600); print('api key: created')
    else: print('api key:', r)
else: print('api key: exists')
me = call('/users/me', token=None)
import urllib.request as u
req = u.Request(API + '/users/me', headers={'Authorization': 'users API-Key ' + keyfile.read_text().strip()})
print('api key proof:', json.load(u.urlopen(req)).get('user', {}).get('email'))
PY
step "4 plesk nginx proxy on the live domain"
if curl -fsS -o /dev/null "$APP/admin/login" </dev/null 2>/dev/null; then
  plesk bin domain --update-web-server-settings $HOST -nginx-proxy-mode false </dev/null | tail -1
  install -m 644 /var/site/src/vhost_nginx.conf "$SYS/vhost_nginx.conf"
  install -m 644 /var/site/src/vhost.conf "$SYS/vhost.conf"
  plesk sbin httpdmng --reconfigure-domain $HOST </dev/null; nginx -t 2>&1 </dev/null | tail -1
else echo "app not answering: live domain left as it was"; fi
step "5 proof"
echo "https: $(curl -s -o /dev/null -w '%{http_code}' https://$HOST/)  $(curl -s https://$HOST/ | grep -o '<title>[^<]*' | head -1)"
echo "admin: $(curl -s -o /dev/null -w '%{http_code}' -L https://$HOST/admin)"
echo "cert:  $(echo | openssl s_client -connect $HOST:443 -servername $HOST 2>/dev/null | openssl x509 -noout -subject | sed 's/subject=//')"
echo "DONE"
REMOTE
## Bring the migrations the server generated back into the repo so they are versioned.
rsync -az mmffdev-admin:/var/site/src/src/migrations/ ./src/migrations/ 2>/dev/null || true
