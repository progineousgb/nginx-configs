#!/usr/bin/env bash
# Run nginx -t against every config in this repo without touching /etc/nginx.
# Builds a throwaway prefix, swaps cert paths for a self-signed cert,
# moves cache paths into the temp dir and listen ports above 1024 so it runs
# without root.
#
# Usage: test/run.sh    (needs nginx and openssl; NGINX_BIN overrides the binary)
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
nginx_bin="${NGINX_BIN:-$(command -v nginx || echo /usr/sbin/nginx)}"
[ -x "$nginx_bin" ] || { echo "nginx not found"; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/conf/snippets" "$tmp/conf/conf.d" "$tmp/conf/sites" "$tmp/cache/fastcgi" "$tmp/cache/proxy" "$tmp/logs" "$tmp/ssl"

openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj "/CN=test.invalid" \
    -keyout "$tmp/ssl/privkey.pem" -out "$tmp/ssl/fullchain.pem" 2>/dev/null

for f in /etc/nginx/fastcgi_params /etc/nginx/mime.types; do
    if [ -f "$f" ]; then
        cp "$f" "$tmp/conf/"
    fi
done
[ -f "$tmp/conf/mime.types" ] || echo 'types { text/html html; }' > "$tmp/conf/mime.types"
[ -f "$tmp/conf/fastcgi_params" ] || touch "$tmp/conf/fastcgi_params"

rewrite() {
    sed -e "s#/etc/letsencrypt/live/[^/]*/fullchain.pem#$tmp/ssl/fullchain.pem#" \
        -e "s#/etc/letsencrypt/live/[^/]*/privkey.pem#$tmp/ssl/privkey.pem#" \
        -e "s#/var/cache/nginx/#$tmp/cache/#" \
        -e "s#listen 80;#listen 18080;#; s#listen \[::\]:80;#listen [::]:18080;#" \
        -e "s#listen 443 ssl;#listen 18443 ssl;#; s#listen \[::\]:443 ssl;#listen [::]:18443 ssl;#" "$1" > "$2"
}

for f in "$repo"/snippets/*.conf; do rewrite "$f" "$tmp/conf/snippets/$(basename "$f")"; done
for f in "$repo"/conf.d/*.conf;   do rewrite "$f" "$tmp/conf/conf.d/$(basename "$f")"; done
for f in "$repo"/sites/*.conf;    do rewrite "$f" "$tmp/conf/sites/$(basename "$f")"; done

cat > "$tmp/conf/nginx.conf" <<CONF
pid $tmp/nginx.pid;
error_log $tmp/logs/error.log;
events {}
http {
    include mime.types;
    access_log $tmp/logs/access.log;
    client_body_temp_path $tmp/cache/body;
    proxy_temp_path $tmp/cache/proxy_temp;
    fastcgi_temp_path $tmp/cache/fastcgi_temp;
    uwsgi_temp_path $tmp/cache/uwsgi_temp;
    scgi_temp_path $tmp/cache/scgi_temp;
    include conf.d/*.conf;
    include sites/*.conf;
}
CONF

"$nginx_bin" -t -p "$tmp" -c "$tmp/conf/nginx.conf"
