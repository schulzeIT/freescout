#!/bin/sh
# Runs on every container start (as root), then hands over to supervisord.
set -e
APP=/var/www/html
DATA=/data
cd "$APP"

# ---- required settings -------------------------------------------------------------------
for v in APP_URL APP_KEY DB_HOST DB_DATABASE DB_USERNAME DB_PASSWORD; do
  eval "val=\${$v:-}"
  if [ -z "$val" ]; then
    echo "ERROR: environment variable $v is not set." >&2
    [ "$v" = "APP_KEY" ] && echo "Generate one with: php -r 'echo \"base64:\".base64_encode(random_bytes(32)).PHP_EOL;'" >&2
    exit 1
  fi
done

# ---- persistent folders on the Railway volume --------------------------------------------
mkdir -p "$DATA/storage" "$DATA/Modules"
if [ ! -d "$DATA/storage/framework" ]; then
  echo "First boot: creating storage skeleton"
  cp -a /opt/storage.dist/. "$DATA/storage/"
fi
mkdir -p "$DATA/storage/framework/cache/data" "$DATA/storage/framework/sessions" \
         "$DATA/storage/framework/views" "$DATA/storage/logs" "$DATA/storage/app/public"

rm -rf "$APP/storage" "$APP/Modules"
ln -sfn "$DATA/storage" "$APP/storage"
ln -sfn "$DATA/Modules" "$APP/Modules"

# ---- .env is rebuilt from Railway variables on every start (single source of truth) -------
php -r '
$keys = ["APP_URL","APP_KEY","APP_TIMEZONE","APP_TRUSTED_PROXIES","SESSION_SECURE_COOKIE","APP_REMOTE_HOST_WHITE_LIST","APP_DEBUG"];
$map  = ["DB_CONNECTION"=>getenv("DB_CONNECTION")?:"mysql","DB_HOST"=>getenv("DB_HOST"),"DB_PORT"=>getenv("DB_PORT")?:"3306","DB_DATABASE"=>getenv("DB_DATABASE"),"DB_USERNAME"=>getenv("DB_USERNAME"),"DB_PASSWORD"=>getenv("DB_PASSWORD")];
foreach ($keys as $k) { $v = getenv($k); if ($v !== false && $v !== "") $map[$k] = $v; }
if (!isset($map["APP_TRUSTED_PROXIES"])) $map["APP_TRUSTED_PROXIES"] = "**";
if (!isset($map["SESSION_SECURE_COOKIE"])) $map["SESSION_SECURE_COOKIE"] = "true";
$out = "";
foreach ($map as $k => $v) $out .= $k . "=\"" . str_replace(["\\", "\""], ["\\\\", "\\\""], $v) . "\"\n";
file_put_contents("/var/www/html/.env", $out);
'

# ---- permissions ---------------------------------------------------------------------------
chown -R www-data:www-data "$DATA" "$APP/bootstrap/cache" "$APP/public/css/builds" "$APP/public/js/builds" "$APP/public/modules" "$APP/.env"
chmod -R u+rwX,g+rwX "$DATA"

as_www() { su -s /bin/sh www-data -c "cd $APP && $*"; }

# ---- database, caches, module links --------------------------------------------------------
as_www "php artisan migrate --force"
as_www "php artisan freescout:clear-cache"
[ -e "$APP/public/storage" ] || ln -sfn "$DATA/storage/app/public" "$APP/public/storage"
touch "$APP/storage/.installed" && chown www-data:www-data "$APP/storage/.installed"

# Recreate public asset links of installed modules (Modules/<Name>/Public -> public/modules/<alias>).
# NOTE: unverified until the first module is installed; check public/modules if a module has no CSS/JS.
for m in "$APP"/Modules/*/; do
  [ -f "${m}module.json" ] || continue
  alias=$(php -r '$j=json_decode(file_get_contents($argv[1]),true); echo $j["alias"] ?? "";' "${m}module.json")
  [ -n "$alias" ] && [ -d "${m}Public" ] && ln -sfn "../../Modules/$(basename "$m")/Public" "$APP/public/modules/$alias"
done

# ---- first admin user (only once) ----------------------------------------------------------
if [ -n "${ADMIN_EMAIL:-}" ] && [ -n "${ADMIN_PASSWORD:-}" ] && [ ! -f "$DATA/.admin-created" ]; then
  as_www "php artisan freescout:create-user --role=admin --firstName='${ADMIN_FIRST_NAME:-Admin}' --lastName='${ADMIN_LAST_NAME:-User}' --email='${ADMIN_EMAIL}' --password='${ADMIN_PASSWORD}'" \
    && touch "$DATA/.admin-created" || echo "WARNING: admin user was not created (may already exist)." >&2
fi

exec /usr/bin/supervisord -c /etc/supervisord.conf
