#!/usr/bin/env bash
## Recreates the forum.colorgain.com record in Plesk when it was born suspended (customer was Off at creation).
## Discourse's data is untouched; only the Plesk vhost is rebuilt. Run as root:  bash /root/forum-setup/reactivate.sh
set -euo pipefail
H=forum.colorgain.com; SYS=/var/www/vhosts/system/$H/conf; HERE="$(cd "$(dirname "$0")" && pwd)"
plesk bin subdomain --remove forum -domain colorgain.com | tail -1
plesk bin subdomain --create forum -domain colorgain.com -www-root $H | tail -1
plesk bin site --update $H -certificate-name "Lets Encrypt colorgain.com" | tail -1
plesk bin site --update $H -ssl-redirect true | tail -1
install -m 644 "$HERE/vhost_nginx.conf" $SYS/vhost_nginx.conf
install -m 644 "$HERE/vhost.conf" $SYS/vhost.conf
plesk bin domain --update-web-server-settings $H -nginx-proxy-mode false | tail -1
plesk sbin httpdmng --reconfigure-domain $H && nginx -t 2>&1 | tail -1
echo "forum:  $(plesk bin site --info $H | grep 'Domain status' | sed 's/Domain status: *//')"
echo "listen: $(grep -o 'listen [^;]*' $SYS/nginx.conf | tr '\n' ',')"
echo "cert:   $(echo | openssl s_client -connect 87.106.44.201:443 -servername $H 2>/dev/null | openssl x509 -noout -subject | sed 's/subject=//')"
echo "https:  $(curl -s -o /dev/null -w '%{http_code}' https://$H/)  $(curl -s https://$H/ | grep -o '<title>[^<]*' | head -1)"
