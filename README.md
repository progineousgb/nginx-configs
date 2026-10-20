<p align="center"><img src="assets/logo.png" alt="Pro Gineous" width="360"></p>

# nginx-configs

Nginx server blocks and snippets we reuse on Debian and Ubuntu servers. They assume the stock Debian layout (`/etc/nginx/conf.d`, `/etc/nginx/snippets`, `sites-available`/`sites-enabled`) and Let's Encrypt certificates from certbot.

Tested with nginx 1.26 (Debian 13). `http2 on;` needs 1.25.1 or newer; on older nginx, drop that line and add `http2` to the `listen 443` lines instead.

## Layout

```
conf.d/                     http-level settings, loaded once
  00-http-tuning.conf       server_tokens, timeouts, gzip, websocket map
  10-rate-limit-zones.conf  limit_req / limit_conn zones
  20-fastcgi-cache.conf     PHP page cache zone
  21-proxy-cache.conf       proxy cache zone
snippets/                   included from server or location blocks
  ssl-params.conf           Mozilla intermediate TLS settings
  security-headers.conf     HSTS, nosniff, frame options, referrer, permissions
  deny-hidden.conf          blocks dotfiles except /.well-known
  static-cache.conf         expires headers for assets
  proxy-params.conf         headers and timeouts for proxy_pass
  fastcgi-php.conf          PHP-FPM pass (socket path for PHP 8.3)
  rate-limit-general.conf   10 r/s per IP with burst
  rate-limit-login.conf     5 r/min per IP for login endpoints
  acme-redirect.conf        port 80: ACME challenges, redirect everything else
sites/
  static-site.conf          static files, www to apex redirect
  wordpress.conf            WordPress + FastCGI cache with sensible bypass rules
  laravel.conf              Laravel front controller, release symlinks
  reverse-proxy.conf        app on 127.0.0.1:3000, websockets, microcache
test/run.sh                 nginx -t harness
```

## Install

```bash
sudo cp conf.d/*.conf /etc/nginx/conf.d/
sudo cp snippets/*.conf /etc/nginx/snippets/
sudo mkdir -p /var/cache/nginx/fastcgi /var/cache/nginx/proxy /var/www/letsencrypt
sudo cp sites/wordpress.conf /etc/nginx/sites-available/blog.example.com
sudo $EDITOR /etc/nginx/sites-available/blog.example.com
sudo ln -s /etc/nginx/sites-available/blog.example.com /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
```

Debian's `snippets/fastcgi-php.conf` from the nginx package has the same name as ours. Ours replaces it; if you rely on the stock one elsewhere, rename ours.

The server blocks reference certificates under `/etc/letsencrypt/live/`. Getting the first certificate is a chicken-and-egg problem, because nginx will not start with a missing cert. Either comment out the 443 server until certbot has run:

```bash
sudo certbot certonly --webroot -w /var/www/letsencrypt -d blog.example.com
```

or use `certbot --nginx` for the first issue and then swap in these files.

## Things that bite

- `add_header` is not merged. A location with any `add_header` loses every header set at server level. That is why some locations include `security-headers.conf` again.
- `if` inside `location` is unsafe for anything other than `return` and `rewrite`. The WordPress cache bypass uses `if` at server level only, setting a variable.
- HSTS is one year without `includeSubDomains` or `preload`. Add those only when every subdomain serves HTTPS; the preload list is hard to get off.
- The FastCGI cache serves the same page to every anonymous visitor. Plugins that personalise pages for logged-out users (geo pricing, some cookie banners) need extra bypass rules.
- Rate limits are per IP. Behind Cloudflare or another proxy, set up `real_ip_header` and `set_real_ip_from` first or every visitor shares the proxy's IP.
- `fastcgi-php.conf` points at `/run/php/php8.3-fpm.sock`. Change it for other PHP versions.

## Testing

```bash
./test/run.sh
```

The script copies everything into a temp directory, generates a throwaway self-signed certificate, rewrites certificate and cache paths and the listen ports (80/443 to 18080/18443) so it runs without root, and calls `nginx -t` on the result. It needs `nginx` and `openssl` installed. It does not start nginx or serve traffic.

## License

MIT, see [LICENSE](LICENSE).

---

From [Pro Gineous](https://progineous.com/). Server scripts that go with these configs: [server-toolkit](https://gitlab.com/pro-gineous-group/server-toolkit).
