#!/usr/bin/env bash
## Pushes theme.css into Wiki.js (Administration > Theme > CSS Injection) through its GraphQL API.
## Reads the API key from .env.docs beside this script (never committed). Run from anywhere: web/docs/apply-theme.sh
set -euo pipefail
cd "$(dirname "$0")"
KEY="$(grep '^apiKey:' .env.docs | cut -d' ' -f2- | tr -d '\n')"
URL="$(grep '^docsUrl:' .env.docs | awk '{print $2}')"
python3 - "$KEY" "$URL" <<'PY'
import json, sys, urllib.request
key, url = sys.argv[1], sys.argv[2].rstrip('/')
css = open('theme.css').read()
q = 'mutation($css:String!){theming{setConfig(theme:"default",iconset:"mdi",darkMode:false,tocPosition:"left",injectCSS:$css,injectHead:"",injectBody:""){responseResult{succeeded message}}}}'
req = urllib.request.Request(url + '/graphql', data=json.dumps({'query': q, 'variables': {'css': css}}).encode(),
                             headers={'Content-Type': 'application/json', 'Authorization': 'Bearer ' + key})
r = json.load(urllib.request.urlopen(req))['data']['theming']['setConfig']['responseResult']
print('theme:', r, f'({len(css)} bytes of CSS)')
check = urllib.request.Request(url + '/graphql', data=json.dumps({'query': '{theming{config{injectCSS}}}'}).encode(),
                               headers={'Content-Type': 'application/json', 'Authorization': 'Bearer ' + key})
live = json.load(urllib.request.urlopen(check))['data']['theming']['config']['injectCSS']
import re
rules=lambda t: len(re.findall(r'\{', t))
print('stored:', len(live), 'bytes after Wiki.js reformatting;', rules(live), 'rules live,', rules(css), 'in the file')
PY
