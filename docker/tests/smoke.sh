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
'
before=$(docker exec "$container" sh -c \
    'sha256sum /app/web/config/*.php /app/web/config/install.lock /app/web/i/keep.txt /app/web/admin/logs/keep.txt')
for path in /config/config.php /config /admin/logs/keep.txt /docs/README.md \
    /.git/config /i/.htaccess /i/probe.php /i/probe.PHP /public/probe.php; do
    expect_status "$path" 403
done
expect_status /healthz 403
expect_status /install/index.php 404
expect_status /does-not-exist.php 404
test "$(curl --silent --show-error --fail --max-time 15 "$base/i/keep.txt?quiet-marker")" = keep-image
if docker logs "$container" 2>&1 | grep -q 'GET /i/keep.txt?quiet-marker'; then
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

# The old image also allowed explicitly setting both IDs to zero.
docker rm --force "$container" >/dev/null
start false 0 0
docker exec "$container" sh -c 'test "$(id -u www-data):$(id -g www-data)" = 0:0'
after=$(docker exec "$container" sh -c \
    'sha256sum /app/web/config/*.php /app/web/config/install.lock /app/web/i/keep.txt /app/web/admin/logs/keep.txt')
test "$before" = "$after"
echo 'Smoke checks passed.'
