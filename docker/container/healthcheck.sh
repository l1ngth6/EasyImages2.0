#!/bin/sh
set -eu
test "$(curl --noproxy '*' --fail --silent --show-error --max-time 3 http://127.0.0.1/healthz)" = ok
