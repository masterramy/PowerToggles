#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MANIFEST="$ROOT/AndroidManifest.xml"
SHORTCUT="$ROOT/src/com/painless/pc/tracker/SimpleShortcut.java"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

# Public publication builds must not retain direct-call authority merely to
# preserve legacy launcher/folder shortcuts. Historical CALL_PRIVILEGED and
# already-normalized ACTION_CALL shortcuts must both become user-confirmed
# ACTION_DIAL intents when SimpleShortcut is reconstructed.
! grep -q 'android.permission.CALL_PHONE' "$MANIFEST" || fail "CALL_PHONE remains declared"
grep -q 'android.intent.action.CALL_PRIVILEGED' "$SHORTCUT" || fail "legacy CALL_PRIVILEGED migration missing"
grep -q 'Intent.ACTION_CALL.equals(action)' "$SHORTCUT" || fail "persisted ACTION_CALL migration missing"
grep -q 'intent.setAction(Intent.ACTION_DIAL)' "$SHORTCUT" || fail "legacy call shortcuts are not routed through the system dialer"

# Do not regress to direct-call execution anywhere in the publication source.
# The legacy action string may exist only in the migration predicate above.
if grep -R --include='*.java' -n 'Intent.ACTION_CALL' "$ROOT/src" | grep -v 'SimpleShortcut.java:.*Intent.ACTION_CALL.equals(action)' >/dev/null; then
  fail "direct ACTION_CALL execution restored outside the shortcut migration gate"
fi

if grep -R --include='*.java' -n 'android.intent.action.CALL_PRIVILEGED' "$ROOT/src" | grep -v 'SimpleShortcut.java:.*CALL_PRIVILEGED' >/dev/null; then
  fail "CALL_PRIVILEGED usage restored outside the shortcut migration gate"
fi

echo "PASS: legacy call shortcuts are user-confirmed and CALL_PHONE-free"
