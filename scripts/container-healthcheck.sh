#!/usr/bin/env bash
# Container-native healthcheck for the GitHub Actions runner image.
set -euo pipefail

fail() {
  printf 'runner healthcheck failed: %s\n' "$*" >&2
  exit 1
}

pgrep -f 'Runner.Listener.*run' >/dev/null || fail "Runner.Listener is not running"

[ -d /runner-data ] || fail "/runner-data is missing"
[ -d /workspace ] || fail "/workspace is missing"
[ -w /runner-data ] || fail "/runner-data is not writable"
[ -w /workspace ] || fail "/workspace is not writable"

probe="/workspace/.runner-healthcheck.$$"
printf 'ok\n' > "${probe}" || fail "cannot write /workspace probe"
rm -f "${probe}"

exit 0
