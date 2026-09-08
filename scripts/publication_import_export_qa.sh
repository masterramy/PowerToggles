#!/usr/bin/env bash
set -euo pipefail

OUT="runtime-evidence/import-export"
mkdir -p "$OUT/screens" "$OUT/ui" "$OUT/state" "$OUT/logs"

fatal_scan() {
  local name="$1"
  adb logcat -d > "$OUT/logs/${name}.logcat.txt"
  if grep -E "FATAL EXCEPTION|Process: com\.painless\.pc.*has died|ANR in com\.painless\.pc|am_crash.*com\.painless\.pc|am_anr.*com\.painless\.pc" "$OUT/logs/${name}.logcat.txt"; then
    echo "Fatal app runtime signal during ${name}" >&2
    return 1
  fi
}

dump_ui() {
  local name="$1"
  local remote="/sdcard/${name}.xml"
  adb shell rm -f "$remote" >/dev/null 2>&1 || true
  rm -f "$OUT/ui/${name}.xml"
  for attempt in 1 2 3 4 5; do
    adb shell uiautomator dump "$remote" >/dev/null 2>&1 || true
    if adb shell test -s "$remote" >/dev/null 2>&1; then
      adb pull "$remote" "$OUT/ui/${name}.xml" >/dev/null 2>&1 || true
      test -s "$OUT/ui/${name}.xml" && return 0
    fi
    sleep 1
  done
  echo "Unable to capture UI hierarchy for ${name}" >&2
  return 1
}

capture() {
  local name="$1"
  dump_ui "$name"
  adb exec-out screencap -p > "$OUT/screens/${name}.png"
  adb shell dumpsys activity activities > "$OUT/state/${name}.activities.txt"
  adb shell dumpsys window windows > "$OUT/state/${name}.windows.txt"
  fatal_scan "$name"
}

tap_node() {
  local name="$1"
  local needle="$2"
  dump_ui "$name"
  local coords
  coords="$(python3 - "$OUT/ui/${name}.xml" "$needle" <<'PY'
import re, sys, xml.etree.ElementTree as ET
path, needle = sys.argv[1:]
for node in ET.parse(path).iter():
    if needle not in (node.attrib.get('text',''), node.attrib.get('content-desc','')):
        continue
    m = re.fullmatch(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]', node.attrib.get('bounds',''))
    if not m:
        continue
    x1,y1,x2,y2 = map(int,m.groups())
    print((x1+x2)//2, (y1+y2)//2)
    raise SystemExit(0)
raise SystemExit('Rendered node not found: ' + needle)
PY
)"
  read -r x y <<< "$coords"
  adb shell input tap "$x" "$y"
}

launch_config() {
  adb shell am force-stop com.painless.pc
  adb logcat -c
  adb shell am start -W -a android.appwidget.action.APPWIDGET_CONFIGURE \
    -n com.painless.pc/.cfg.WidgetConfigActivity --ei appWidgetId 1099 \
    > "$OUT/state/config-start.txt" 2>&1
  sleep 2
  capture "00-config"
}

assert_document_picker() {
  local name="$1"
  if ! grep -Eq 'com\.google\.android\.documentsui|com\.android\.documentsui' "$OUT/state/${name}.activities.txt"; then
    echo "Modern Storage Access Framework picker is not foreground for ${name}" >&2
    return 1
  fi
}

launch_config
tap_node "01-overflow-source" "More options"
sleep 1
capture "01-overflow"
grep -Fq 'text="Backup"' "$OUT/ui/01-overflow.xml"
grep -Fq 'text="Restore"' "$OUT/ui/01-overflow.xml"

adb logcat -c
tap_node "02-backup-menu-source" "Backup"
sleep 2
capture "02-backup-destination"
assert_document_picker "02-backup-destination"

adb shell input keyevent KEYCODE_BACK || true
sleep 1
capture "03-backup-cancel-return"
grep -Fq 'package="com.painless.pc"' "$OUT/ui/03-backup-cancel-return.xml"

# Re-open the exact customer overflow path and require modern document-open UI.
tap_node "04-overflow-source" "More options"
sleep 1
capture "04-overflow"
adb logcat -c
tap_node "05-restore-menu-source" "Restore"
sleep 2
capture "05-restore-source"
assert_document_picker "05-restore-source"

adb shell input keyevent KEYCODE_BACK || true
sleep 1
capture "06-restore-cancel-return"
grep -Fq 'package="com.painless.pc"' "$OUT/ui/06-restore-cancel-return.xml"

echo "backup_destination=PASS_SAF_DOCUMENT_CREATE" > "$OUT/summary.txt"
echo "restore_source=PASS_SAF_DOCUMENT_OPEN" >> "$OUT/summary.txt"
echo "cancel_return=PASS" >> "$OUT/summary.txt"
cat "$OUT/summary.txt"
