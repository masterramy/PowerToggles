#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MANIFEST="$ROOT/AndroidManifest.xml"
SHORTCUT="$ROOT/src/com/painless/pc/tracker/SimpleShortcut.java"
COMMAND="$ROOT/src/com/painless/pc/tracker/AbstractCommand.java"

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

# Keep a second fail-safe at the shared command boundary. It may recognize an
# unexpected ACTION_CALL only in order to copy-and-downgrade it to ACTION_DIAL;
# the app must not regain CALL_PHONE or a direct-call execution path.
grep -q 'Intent.ACTION_CALL.equals(intent.getAction())' "$COMMAND" || fail "shared ACTION_CALL safety gate missing"
grep -q 'new Intent(intent).setAction(Intent.ACTION_DIAL)' "$COMMAND" || fail "shared command safety gate does not copy-and-dial"
! grep -R --include='*.java' -q 'Manifest.permission.CALL_PHONE' "$ROOT/src" || fail "CALL_PHONE permission dependency restored in source"
! grep -R --include='*.java' -q '"android.intent.action.CALL"' "$ROOT/src" || fail "literal direct ACTION_CALL execution restored"

if grep -R --include='*.java' -n 'Intent.ACTION_CALL' "$ROOT/src" \
    | grep -v 'SimpleShortcut.java:.*Intent.ACTION_CALL.equals(action)' \
    | grep -v 'AbstractCommand.java:.*Intent.ACTION_CALL.equals(intent.getAction())' >/dev/null; then
  fail "direct ACTION_CALL usage restored outside the two dial-migration gates"
fi

if grep -R --include='*.java' -n 'android.intent.action.CALL_PRIVILEGED' "$ROOT/src" \
    | grep -v 'SimpleShortcut.java:.*CALL_PRIVILEGED' >/dev/null; then
  fail "CALL_PRIVILEGED usage restored outside the shortcut migration gate"
fi

echo "PASS: legacy/direct call shortcuts are user-confirmed and CALL_PHONE-free"
