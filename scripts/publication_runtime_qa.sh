#!/usr/bin/env bash
set -euo pipefail

# Publication-only transport hardening around the already-certified Gate 2A
# runtime probe. The underlying assertions and app interactions are unchanged.
# Retry ONLY adb's transport-style rc=255. Any ordinary shell/app/assertion
# failure is returned immediately and remains red.
REAL_ADB="$(command -v adb)"
if [ -z "$REAL_ADB" ]; then
  echo "adb not found" >&2
  exit 127
fi
export REAL_ADB

adb() {
  local rc=0
  local attempt
  for attempt in 1 2 3 4 5; do
    set +e
    "$REAL_ADB" "$@"
    rc=$?
    set -e
    if [ "$rc" -eq 0 ]; then
      return 0
    fi
    if [ "$rc" -ne 255 ]; then
      return "$rc"
    fi
    echo "Transient adb rc=255 for: adb $* (attempt $attempt/5)" >&2
    "$REAL_ADB" wait-for-device >/dev/null 2>&1 || true
    sleep 1
  done
  echo "adb remained unavailable after bounded rc=255 retries: adb $*" >&2
  return 255
}
export -f adb

bash scripts/gate2a_runtime_qa.sh
