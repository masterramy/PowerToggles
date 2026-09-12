#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STORAGE="$ROOT/src/com/painless/pc/singleton/SettingStorage.java"
MANAGER="$ROOT/src/com/painless/pc/TrackerManager.java"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

# Persisted/imported/widget/tile definitions are data. Numeric tracker IDs may
# address only the stable TrackerManager range; malformed negative/oversized
# values must take the historical Wi-Fi compatibility fallback instead of ever
# becoming an array index.
grep -q 'if (id < 0 || id >= trackerList.length)' "$STORAGE" || fail "numeric tracker definition bounds check missing"
grep -A3 'if (id < 0 || id >= trackerList.length)' "$STORAGE" | grep -q 'id = 3;' || fail "out-of-range numeric tracker does not use compatibility fallback ID 3"
grep -q 'if (trackerId < 0 || trackerId >= trackerList.length)' "$STORAGE" || fail "maybeGetTracker cache accessor is not bounds-safe"
grep -A3 'if (trackerId < 0 || trackerId >= trackerList.length)' "$STORAGE" | grep -q 'return null;' || fail "invalid maybeGetTracker ID does not fail closed"

# Keep stable historical IDs and the existing ss_/pl_ compatibility parsers.
grep -q 'def.startsWith("ss_")' "$STORAGE" || fail "shortcut tracker-definition compatibility path missing"
grep -q 'def.startsWith("pl_")' "$STORAGE" || fail "plugin tracker-definition compatibility path missing"
grep -q 'new AbstractTracker\[TrackerManager.TRACKER_LIST.length\]' "$STORAGE" || fail "tracker cache no longer follows canonical tracker registry length"
grep -q 'return new WifiStateTracker(3, pref);' "$MANAGER" || fail "TrackerManager compatibility fallback drifted"

# Direct array indexing must occur only after the explicit range check in the
# same getTracker method. Enforce ordering rather than merely marker presence.
python3 - "$STORAGE" <<'PY'
import sys
text = open(sys.argv[1], encoding='utf-8').read()
start = text.index('public static AbstractTracker getTracker(String def, Context context, SharedPreferences pref, ShortcutIdParser shortcutParser)')
end = text.index('/**\n\t * Adds a widget definition', start)
body = text[start:end]
check = body.index('if (id < 0 || id >= trackerList.length)')
index = body.index('AbstractTracker tracker = trackerList[id]')
if check >= index:
    raise SystemExit('FAIL: trackerList is indexed before numeric ID bounds validation')
print('PASS: tracker definition bounds precede cache indexing')
PY

echo "PASS: malformed numeric tracker definitions fail closed without disturbing stable ss_/pl_/0..47 compatibility"
