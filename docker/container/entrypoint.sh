#!/bin/sh
set -eu

for value in "$PUID" "$PGID"; do
    case "$value" in
        ''|*[!0-9]*) echo 'PUID and PGID must be non-negative integers.' >&2; exit 1 ;;
    esac
done
case "$DEBUG" in
    true|false) ;;
    *) echo 'DEBUG must be true or false.' >&2; exit 1 ;;
esac
case "$TZ" in
    ''|/*|*..*) echo 'TZ must name a zone in /usr/share/zoneinfo.' >&2; exit 1 ;;
esac
if [ ! -f "/usr/share/zoneinfo/$TZ" ]; then
    echo "Unknown timezone: $TZ" >&2
    exit 1
fi
ln -snf "/usr/share/zoneinfo/$TZ" /etc/localtime
printf '%s\n' "$TZ" > /etc/timezone

if [ "$(id -g www-data)" != "$PGID" ]; then
    groupmod -o -g "$PGID" www-data
fi
if [ "$(id -u www-data)" != "$PUID" ]; then
    usermod -o -u "$PUID" www-data
fi

mkdir -p /app/web/config /app/web/i /app/web/admin/logs /logs /run/php
for directory in config i; do
    for source in /opt/easyimage-defaults/"$directory"/* /opt/easyimage-defaults/"$directory"/.[!.]*; do
        [ -f "$source" ] || continue
        target="/app/web/$directory/$(basename "$source")"
        # Never replace existing files, including dangling symlinks.
        if [ ! -e "$target" ] && [ ! -L "$target" ]; then
            cp -- "$source" "$target"
        fi
    done
done

# Change ownership only in writable data directories; preserve existing modes.
for directory in /app/web/config /app/web/i /app/web/admin/logs /logs; do
    find "$directory" -xdev \( ! -uid "$PUID" -o ! -gid "$PGID" \) \
        -exec chown --no-dereference "$PUID:$PGID" '{}' +
done

if [ "$DEBUG" = true ]; then
    printf 'access_log /dev/stdout combined;\n' > /etc/nginx/easyimage-access-log.conf
else
    printf 'access_log /logs/nginx_access.log combined;\n' > /etc/nginx/easyimage-access-log.conf
fi

php /usr/local/share/easyimage/check-runtime.php
php-fpm --test --allow-to-run-as-root
nginx -t
exec "$@"
