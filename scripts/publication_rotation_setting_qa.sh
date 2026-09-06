#!/usr/bin/env bash
set -euo pipefail

OUT="runtime-evidence/rotation-setting"
mkdir -p "$OUT/state" "$OUT/logs"
PKG="com.painless.pc"
PROBE="$PKG/.tracker.PublicationCompatProbeActivity"

run_probe() {
  local name="$1"
  adb shell am start -W -n "$PROBE" --es probe "$name" > "$OUT/state/${name}-start.txt" 2>&1
  sleep 1
}

read_pref_int() {
  local key="$1"
  local file="$OUT/state/probe.xml"
  adb exec-out run-as "$PKG" cat shared_prefs/publication_compat_probe.xml > "$file" 2>/dev/null
  python3 - "$file" "$key" <<'PY'
import sys, xml.etree.ElementTree as ET
p, key = sys.argv[1:]
root = ET.parse(p).getroot()
for node in root:
    if node.attrib.get('name') == key:
        print(node.attrib.get('value', node.text or ''))
        raise SystemExit(0)
raise SystemExit(f'missing pref: {key}')
PY
}

read_pref_bool() {
  local key="$1"
  local file="$OUT/state/probe.xml"
  adb exec-out run-as "$PKG" cat shared_prefs/publication_compat_probe.xml > "$file" 2>/dev/null
  python3 - "$file" "$key" <<'PY'
import sys, xml.etree.ElementTree as ET
p, key = sys.argv[1:]
root = ET.parse(p).getroot()
for node in root:
    if node.attrib.get('name') == key:
        print(node.attrib.get('value', node.text or ''))
        raise SystemExit(0)
raise SystemExit(f'missing pref: {key}')
PY
}

adb shell appops set "$PKG" WRITE_SETTINGS allow >/dev/null
adb shell am force-stop "$PKG" || true
adb logcat -c || true

run_probe rotation_setting_prepare
before="$(read_pref_int rotation_setting_before)"
run_probe rotation_setting_toggle
after="$(read_pref_int rotation_setting_after)"
changed="$(read_pref_bool rotation_setting_changed)"
user_write="$(read_pref_bool rotation_setting_user_write)"
auto_write="$(read_pref_bool rotation_setting_auto_write)"
run_probe rotation_setting_restore
restored="$(read_pref_int rotation_setting_restored)"
auto_restored="$(read_pref_int rotation_auto_restored)"
original_auto="$(read_pref_int original_rotation_lock_rotation)"
adb logcat -d > "$OUT/logs/rotation-setting.logcat.txt"
adb shell appops set "$PKG" WRITE_SETTINGS deny >/dev/null 2>&1 || true

printf '%s\n' \
  "before=$before" \
  "after=$after" \
  "changed=$changed" \
  "user_write=$user_write" \
  "auto_write=$auto_write" \
  "restored=$restored" \
  "original_auto=$original_auto" \
  "auto_restored=$auto_restored" \
  | tee "$OUT/summary.txt"

[ "$changed" = "true" ]
[ "$user_write" = "true" ]
[ "$auto_write" = "true" ]
[ "$before" != "$after" ]
[ "$restored" = "$before" ]
[ "$auto_restored" = "$original_auto" ]
if grep -E "FATAL EXCEPTION|Process: com\.painless\.pc|ANR in com\.painless\.pc|SecurityException" "$OUT/logs/rotation-setting.logcat.txt"; then
  echo "Unexpected fatal/security signal during public rotation-setting proof" >&2
  exit 1
fi

echo "Publication USER_ROTATION proof: PASS"
