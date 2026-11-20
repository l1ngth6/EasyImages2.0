#!/usr/bin/env bash
# Intended for disposable GitHub-hosted runners, never production data.
set -euo pipefail

image=${1:?Usage: bash docker/tests/smoke.sh IMAGE}
work=$(mktemp -d "${RUNNER_TEMP:-/tmp}/easyimage-smoke.XXXXXX")
container="easyimage-smoke-${GITHUB_RUN_ID:-manual}-$$"

cleanup() {
    result=$?
    trap - EXIT
    if (( result != 0 )); then
        docker logs "$container" >&2 2>/dev/null || true
    fi
    docker rm --force "$container" >/dev/null 2>&1 || true
    # Startup changes ownership; delete only this script's temporary fixture.
    sudo rm -rf -- "$work"
    exit "$result"
}
trap cleanup EXIT
mkdir -p "$work/config" "$work/images/i" "$work/logs"

start() {
    docker run --detach --name "$container" \
        --platform "${TEST_PLATFORM:-linux/amd64}" \
        --publish 127.0.0.1::80 \
        --env "PUID=${2:-1000}" --env "PGID=${3:-1000}" --env TZ=Asia/Shanghai --env "DEBUG=$1" \
        --env "EASYIMAGE_MIGRATE_LEGACY_PASSWORDS=${4:-true}" \
        --mount "type=bind,src=$work/config,dst=/app/web/config" \
        --mount "type=bind,src=$work/images/i,dst=/app/web/i" \
        --mount "type=bind,src=$work/logs,dst=/app/web/admin/logs" \
        "$image" >/dev/null
    base="http://$(docker port "$container" 80/tcp)"
    ready
}

ready() {
    for (( attempt=0; attempt<60; attempt++ )); do
        if docker exec "$container" easyimage-healthcheck >/dev/null 2>&1; then
            return
        fi
        sleep 1
    done
    echo 'Container did not become healthy.' >&2
    return 1
}

expect_status() {
    local actual
    actual=$(curl --silent --show-error --max-time 15 --output /dev/null --write-out '%{http_code}' "$base$1")
    if [[ "$actual" != "$2" ]]; then
        echo "$1: expected HTTP $2, received $actual" >&2
        return 1
    fi
}

expect_header() {
    if ! curl --silent --show-error --fail --max-time 15 --dump-header - --output /dev/null "$base$1" | \
        tr -d '\r' | grep -qixF "$2"; then
        echo "$1: missing response header: $2" >&2
        return 1
    fi
}

expect_log() {
    for (( attempt=0; attempt<10; attempt++ )); do
        if docker logs "$container" 2>&1 | grep -F "$1"; then
            return
        fi
        sleep 1
    done
    echo "Missing container log: $1" >&2
    return 1
}

# Initialize empty bind mounts using the same paths as the legacy image.
start false
docker exec "$container" php /usr/local/share/easyimage/check-runtime.php
expect_status /install/index.php 200
expect_status / 200
test -f "$work/config/config.php"
test -f "$work/config/config.manager.php"
test -f "$work/config/config.guest.php"
test -f "$work/config/api_key.php"
test -f "$work/images/i/.htaccess"
test ! -e "$work/config/install.lock"
docker exec "$container" sh -c 'test "$(id -u www-data):$(id -g www-data)" = 1000:1000'
docker exec --user 1000:1000 "$container" sh -c \
    'test -w /app/web/config && test -w /app/web/i && test -w /app/web/admin/logs'

# Upload entrypoints must return clean JSON when no file was provided.
for endpoint in /app/upload.php /api/index.php; do
    curl --silent --show-error --fail --max-time 15 "$base$endpoint" | \
        python3 -c 'import json, sys; assert json.load(sys.stdin)["code"] == 204'
done

# Even application ini_set() must not expose PHP diagnostics over HTTP.
docker exec -i "$container" sh -c 'cat > /app/web/ci-diagnostic.php' <<'PHP'
<?php
ini_set('display_errors', '1');
error_reporting(E_ALL);
trigger_error('easyimage-smoke-diagnostic', E_USER_WARNING);
header('Content-Type: application/json');
echo '{"ok":true}';
PHP
test "$(curl --silent --show-error --fail --max-time 15 "$base/ci-diagnostic.php")" = '{"ok":true}'

# Synthetic existing data: no real credentials or user uploads are involved.
docker exec "$container" sh -c '
    printf "\n// existing configuration marker\n" >> /app/web/config/config.php
    printf installed > /app/web/config/install.lock
    printf keep-image > /app/web/i/keep.txt
    printf keep-log > /app/web/admin/logs/keep.txt
    printf "<?php echo 123;" > /app/web/i/probe.php
    printf "<?php echo 123;" > /app/web/i/probe.PHP
    printf "<?php echo 123;" > /app/web/public/probe.php
    printf "<?php echo 123;" > /app/web/i/probe.pht
    printf "<svg xmlns=\"http://www.w3.org/2000/svg\"/>" > /app/web/i/probe.svg
'
before=$(docker exec "$container" sh -c \
    'sha256sum /app/web/config/*.php /app/web/config/install.lock /app/web/i/keep.txt /app/web/admin/logs/keep.txt')
for path in /config/config.php /config /admin/logs/keep.txt /docs/README.md \
    /.git/config /i/.htaccess /i/probe.php /i/probe.PHP /i/probe.pht /public/probe.php; do
    expect_status "$path" 403
done
expect_header /i/probe.svg 'Content-Security-Policy: sandbox'
expect_header /i/probe.svg 'X-Content-Type-Options: nosniff'
expect_header /i/keep.txt 'X-Content-Type-Options: nosniff'
expect_status /healthz 403
expect_status /install/index.php 404
expect_status /does-not-exist.php 404
test "$(curl --silent --show-error --fail --max-time 15 "$base/i/keep.txt?quiet-marker")" = keep-image
# Neither Nginx nor PHP-FPM may log requests here, including health checks.
logs=$(docker logs "$container" 2>&1)
if grep -qE 'GET /(i/keep\.txt\?quiet-marker|healthz|ci-diagnostic\.php)' <<<"$logs"; then
    echo 'DEBUG=false unexpectedly emitted access logs.' >&2
    exit 1
fi
expect_log easyimage-smoke-diagnostic

docker stop --time 70 "$container" >/dev/null
test "$(docker inspect --format '{{.State.ExitCode}}' "$container")" = 0
docker start "$container" >/dev/null
ready
after=$(docker exec "$container" sh -c \
    'sha256sum /app/web/config/*.php /app/web/config/install.lock /app/web/i/keep.txt /app/web/admin/logs/keep.txt')
test "$before" = "$after"

# Recreate on the same mounts; DEBUG=true must expose access logs.
docker rm --force "$container" >/dev/null
start true
after=$(docker exec "$container" sh -c \
    'sha256sum /app/web/config/*.php /app/web/config/install.lock /app/web/i/keep.txt /app/web/admin/logs/keep.txt')
test "$before" = "$after"
expect_status /install/index.php 404
curl --silent --show-error --fail --max-time 15 "$base/i/keep.txt?debug-marker" >/dev/null
expect_log 'GET /i/keep.txt?debug-marker'

# Pre-2.8.7 releases stored SHA256(password); startup converts it to bcrypt.
# Synthetic passwords only. Browsers submit SHA256(password) when logging in.
admin_digest=$(printf %s smoke-admin-password | sha256sum | cut -d' ' -f1)
uploader_digest=$(printf %s smoke-uploader-password | sha256sum | cut -d' ' -f1)
sample_digest=84983c60f7daadc1cb8698621f802c0d9f9a3c3c295c810748fb048115c186ec
docker exec -i --user 1000:1000 "$container" php -- "$admin_digest" "$uploader_digest" "$sample_digest" <<'PHP'
<?php
$file = '/app/web/config/config.php';
$text = preg_replace("/'password'=>'[^']*'/", "'password'=>'$argv[1]'", file_get_contents($file), 1, $count);
$text = preg_replace("/^\s*'trusted_proxy'=>'[^']*',\R/m", '', $text, 1, $removed);
if ($count !== 1 || $removed !== 1 || file_put_contents($file, $text) === false) {
    exit(1);
}
$guests = "<?php\r\n\$guestConfig=Array\r\n\t(\r\n"
    . "\t'uploader'=>Array\r\n\t\t(\r\n\t\t'password'=>'$argv[2]',\r\n"
    . "\t\t'expired'=>" . (time() + 86400) . ",\r\n\t\t'add_time'=>" . time() . "\r\n\t\t),\r\n"
    . "\t'guest'=>Array\r\n\t\t(\r\n\t\t'password'=>'$argv[3]',\r\n"
    . "\t\t'expired'=>1765301956,\r\n\t\t'add_time'=>1678988356\r\n\t\t)\r\n\t);";
exit(file_put_contents('/app/web/config/config.guest.php', $guests) === false ? 1 : 0);
PHP
accounts() {
    docker exec "$container" sha256sum /app/web/config/config.php /app/web/config/config.guest.php
}
legacy=$(accounts)

docker rm --force "$container" >/dev/null
start false 1000 1000 false
test "$(accounts)" = "$legacy"

docker rm --force "$container" >/dev/null
start false
expect_log 'config.php: converted 1 legacy SHA256 password(s) to bcrypt'
expect_log 'config.guest.php: converted 1 legacy SHA256 password(s) to bcrypt'
expect_log "left example uploader 'guest' unconverted"
expect_log 'config.php lacks settings that the bundled defaults define: trusted_proxy.'
docker exec "$container" php -r '
    include "/app/web/config/config.php";
    include "/app/web/config/config.guest.php";
    exit(password_verify($argv[1], $config["password"])
        && password_verify($argv[2], $guestConfig["uploader"]["password"])
        && $guestConfig["guest"]["password"] === $argv[3] ? 0 : 1);
' "$admin_digest" "$uploader_digest" "$sample_digest"
docker exec "$container" grep -qF "$admin_digest" /app/web/config/config.php.legacy-sha256.bak
test "$(docker exec "$container" stat -c '%a %u:%g' /app/web/config/config.php.legacy-sha256.bak)" = '600 1000:1000'
expect_status /config/config.php.legacy-sha256.bak 403

login() {
    curl --silent --show-error --fail --max-time 30 \
        --data-urlencode "user=$1" --data-urlencode "password=$2" "$base/admin/index.php"
}
response=$(login admin "$admin_digest")
grep -qF '管理员登录成功' <<<"$response"
response=$(login uploader "$uploader_digest")
grep -qF 'uploader用户登录成功' <<<"$response"
response=$(login admin "$uploader_digest")
grep -qF '账号或密码错误' <<<"$response"

# Converted files are left alone on later starts.
migrated=$(accounts)
docker restart --time 70 "$container" >/dev/null
ready
test "$(accounts)" = "$migrated"
before=$(docker exec "$container" sh -c \
    'sha256sum /app/web/config/*.php /app/web/config/install.lock /app/web/i/keep.txt /app/web/admin/logs/keep.txt')

# The old image also allowed explicitly setting both IDs to zero.
docker rm --force "$container" >/dev/null
start false 0 0
docker exec "$container" sh -c 'test "$(id -u www-data):$(id -g www-data)" = 0:0'
after=$(docker exec "$container" sh -c \
    'sha256sum /app/web/config/*.php /app/web/config/install.lock /app/web/i/keep.txt /app/web/admin/logs/keep.txt')
test "$before" = "$after"
echo 'Smoke checks passed.'
