#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SERVICE="$ROOT/src/com/painless/pc/ImmersiveService.java"
TRACKER="$ROOT/src/com/painless/pc/tracker/ImmersiveTracker.java"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

# Immersive is an intentionally retained pre-O compatibility control. Its legacy
# TYPE_TOAST window can still be rejected by OEM/platform window policy. A failed
# attach must never crash the app or advertise a false enabled state.
grep -q 'Build.VERSION.SDK_INT >= Build.VERSION_CODES.O' "$TRACKER" || fail "Immersive tracker lost Android O cutoff"
grep -q 'windowManager.addView(mBlockerView, params);' "$SERVICE" || fail "Immersive service no longer has the reviewed window attach path"
grep -q 'catch (RuntimeException e)' "$SERVICE" || fail "Immersive window-policy denial can escape into an app-process crash"
grep -q 'IMMERSIVE_ON = false;' "$SERVICE" || fail "Immersive attach failure does not preserve disabled state"
grep -q 'broadcastState();' "$SERVICE" || fail "Immersive attach failure is not reflected to toggle observers"
grep -q 'stopSelf();' "$SERVICE" || fail "Immersive attach failure does not stop the failed service"
grep -q 'if (mBlockerView != null)' "$SERVICE" || fail "Immersive teardown/callback path assumes blocker initialization"
grep -q 'if (mHandler != null)' "$SERVICE" || fail "Immersive teardown assumes handler initialization"

echo "PASS: immersive legacy-window fail-closed contract"
