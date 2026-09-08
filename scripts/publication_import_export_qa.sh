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

wait_for_node() {
  local name="$1"
  local needle="$2"
  local attempts="${3:-10}"
  for attempt in $(seq 1 "$attempts"); do
    dump_ui "$name" || true
    if python3 - "$OUT/ui/${name}.xml" "$needle" <<'PY'
import sys, xml.etree.ElementTree as ET
path, needle = sys.argv[1:]
for node in ET.parse(path).iter():
    if needle in (node.attrib.get('text',''), node.attrib.get('content-desc','')):
        raise SystemExit(0)
raise SystemExit(1)
PY
    then
      return 0
    fi
    sleep 1
  done
  echo "Rendered node did not appear: ${needle}" >&2
  return 1
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

# First preserve the exact customer-visible picker and cancel-return proof.
launch_config
tap_node "01-overflow-source" "More options"
sleep 1
capture "01-overflow"
grep -Fq 'text="Create Backup"' "$OUT/ui/01-overflow.xml"
grep -Fq 'text="Restore Backup"' "$OUT/ui/01-overflow.xml"

adb logcat -c
tap_node "02-backup-menu-source" "Create Backup"
sleep 2
capture "02-backup-destination"
assert_document_picker "02-backup-destination"
grep -Fq 'text="power-toggles-backup.zip"' "$OUT/ui/02-backup-destination.xml"
grep -Fq 'text="SAVE"' "$OUT/ui/02-backup-destination.xml"

adb shell input keyevent KEYCODE_BACK || true
sleep 1
capture "03-backup-cancel-return"
grep -Fq 'package="com.painless.pc"' "$OUT/ui/03-backup-cancel-return.xml"

# Re-open the exact customer overflow path and require modern document-open UI.
tap_node "04-overflow-source" "More options"
sleep 1
capture "04-overflow"
adb logcat -c
tap_node "05-restore-menu-source" "Restore Backup"
sleep 2
capture "05-restore-source"
assert_document_picker "05-restore-source"

adb shell input keyevent KEYCODE_BACK || true
sleep 1
capture "06-restore-cancel-return"
grep -Fq 'package="com.painless.pc"' "$OUT/ui/06-restore-cancel-return.xml"

# End-to-end round-trip proof uses a genuine framework-bound widget. Harness-only
# mutation creates a known persisted divergence; backup creation, document picking,
# import, Done-save, and post-process persistence all use shipping customer paths.
USER_ID="$(adb shell am get-current-user | tr -d '\r')"
case "$USER_ID" in
  ''|*[!0-9]*) echo "Unable to resolve numeric Android user: $USER_ID" >&2; exit 1 ;;
esac
printf 'android_user_id=%s\n' "$USER_ID" > "$OUT/state/android-user.txt"

cleanup_roundtrip() {
  adb shell am force-stop com.painless.pc >/dev/null 2>&1 || true
  adb shell appwidget revokebind --package com.painless.pc --user "$USER_ID" >/dev/null 2>&1 || true
  adb shell rm -f /sdcard/Download/power-toggles-backup.zip >/dev/null 2>&1 || true
}
trap cleanup_roundtrip EXIT

probe() {
  local action="$1"
  shift || true
  adb shell am force-stop com.painless.pc >/dev/null
  adb shell am start -W -n com.painless.pc/.tracker.PublicationWidgetHostProbeActivity \
    --es probe "$action" "$@"
}

pull_probe_prefs() {
  adb shell run-as com.painless.pc cat shared_prefs/publication_widget_host_probe.xml
}

read_probe_pref() {
  local key="$1"
  python3 - "$OUT/state/probe-prefs.xml" "$key" <<'PY'
import sys
import xml.etree.ElementTree as ET
path, key = sys.argv[1:]
root = ET.parse(path).getroot()
for node in root:
    if node.attrib.get('name') != key:
        continue
    if node.tag == 'string':
        print(node.text or '')
    else:
        print(node.attrib.get('value', ''))
    raise SystemExit(0)
raise SystemExit(f'missing preference: {key}')
PY
}

pull_widget_prefs() {
  local dest="$1"
  adb shell run-as com.painless.pc cat shared_prefs/widget_preference.xml > "$dest"
  test -s "$dest"
}

extract_widget_settings() {
  local prefs="$1"
  local widget_id="$2"
  local dest="$3"
  python3 - "$prefs" "$widget_id" "$dest" <<'PY'
import sys, xml.etree.ElementTree as ET
prefs, widget_id, dest = sys.argv[1:]
key = 'widget' + widget_id
root = ET.parse(prefs).getroot()
for node in root:
    if node.tag == 'string' and node.attrib.get('name') == key:
        value = node.text or ''
        if not value:
            raise SystemExit('empty widget settings: ' + key)
        open(dest, 'w', encoding='utf-8').write(value)
        raise SystemExit(0)
raise SystemExit('missing widget settings: ' + key)
PY
}

compare_json() {
  local left="$1"
  local right="$2"
  local label="$3"
  python3 - "$left" "$right" "$label" <<'PY'
import json, sys
left, right, label = sys.argv[1:]
a = json.load(open(left, encoding='utf-8'))
b = json.load(open(right, encoding='utf-8'))
if a != b:
    print(label + ' semantic JSON mismatch', file=sys.stderr)
    print('left = ' + json.dumps(a, sort_keys=True), file=sys.stderr)
    print('right= ' + json.dumps(b, sort_keys=True), file=sys.stderr)
    raise SystemExit(1)
print(label + '=PASS')
PY
}

adb shell rm -f /sdcard/Download/power-toggles-backup.zip >/dev/null 2>&1 || true
adb shell appwidget grantbind --package com.painless.pc --user "$USER_ID" | tee "$OUT/state/grantbind.txt"
adb logcat -c
probe allocate_bind > "$OUT/state/allocate-bind.txt"
pull_probe_prefs > "$OUT/state/probe-prefs.xml"
WIDGET_ID="$(read_probe_pref widget_id)"
BOUND="$(read_probe_pref bound)"
PROVIDER_PRESENT="$(read_probe_pref provider_info_present)"
test "$WIDGET_ID" -gt 0
test "$BOUND" = "true"
test "$PROVIDER_PRESENT" = "true"
printf 'roundtrip_widget_id=%s\n' "$WIDGET_ID" > "$OUT/state/roundtrip-widget.txt"

# Save a genuine initial widget definition through the customer Done control.
adb logcat -c
adb shell am start -W -a android.appwidget.action.APPWIDGET_CONFIGURE \
  -n com.painless.pc/.cfg.WidgetConfigActivity --ei appWidgetId "$WIDGET_ID" \
  > "$OUT/state/roundtrip-configure-start.txt"
sleep 2
capture "10-roundtrip-genuine-create"
tap_node "11-roundtrip-done-source" "Done"
sleep 2
fatal_scan "11-roundtrip-initial-save"
pull_widget_prefs "$OUT/state/widget-prefs-baseline.xml"
extract_widget_settings "$OUT/state/widget-prefs-baseline.xml" "$WIDGET_ID" "$OUT/state/baseline-settings.json"
python3 -m json.tool "$OUT/state/baseline-settings.json" > "$OUT/state/baseline-settings.pretty.json"

# Reopen through the exact shipping tracker-33 widget-settings route.
adb logcat -c
probe reopen --ei widget_id "$WIDGET_ID" > "$OUT/state/roundtrip-reopen-dispatch.txt"
sleep 2
capture "12-roundtrip-reopen"
grep -q 'com.painless.pc/.cfg.WidgetConfigActivity' "$OUT/state/12-roundtrip-reopen.activities.txt"

# Create an actual backup document in Downloads using the shipping SAF path.
tap_node "13-roundtrip-overflow-source" "More options"
sleep 1
capture "13-roundtrip-overflow"
tap_node "14-roundtrip-create-source" "Create Backup"
sleep 2
capture "14-roundtrip-create-document"
assert_document_picker "14-roundtrip-create-document"
grep -Fq 'text="power-toggles-backup.zip"' "$OUT/ui/14-roundtrip-create-document.xml"
grep -Fq 'text="SAVE"' "$OUT/ui/14-roundtrip-create-document.xml"
adb logcat -c
tap_node "15-roundtrip-save-source" "SAVE"
sleep 4
capture "15-roundtrip-save-return"
grep -Fq 'package="com.painless.pc"' "$OUT/ui/15-roundtrip-save-return.xml"
fatal_scan "15-roundtrip-save-return"

for attempt in $(seq 1 10); do
  if adb shell test -s /sdcard/Download/power-toggles-backup.zip >/dev/null 2>&1; then
    break
  fi
  sleep 1
done
adb shell test -s /sdcard/Download/power-toggles-backup.zip
adb shell ls -l /sdcard/Download/power-toggles-backup.zip > "$OUT/state/backup-file-ls.txt"
adb pull /sdcard/Download/power-toggles-backup.zip "$OUT/state/power-toggles-backup.zip" >/dev/null
unzip -t "$OUT/state/power-toggles-backup.zip" | tee "$OUT/state/backup-unzip-test.txt"
unzip -p "$OUT/state/power-toggles-backup.zip" config.txt | sed -n '1p' > "$OUT/state/backup-config.json"
python3 -m json.tool "$OUT/state/backup-config.json" > "$OUT/state/backup-config.pretty.json"
compare_json "$OUT/state/baseline-settings.json" "$OUT/state/backup-config.json" "backup_config_matches_saved_widget"
sha256sum "$OUT/state/power-toggles-backup.zip" > "$OUT/state/backup-sha256.txt"

# Harness-only fixture mutation: invert a real persisted customer setting. If
# restore is not genuinely applied, pressing Done will preserve this divergence.
python3 - "$OUT/state/widget-prefs-baseline.xml" "$WIDGET_ID" "$OUT/state/widget-prefs-mutated.xml" "$OUT/state/mutation-summary.txt" <<'PY'
import json, sys, xml.etree.ElementTree as ET
src, widget_id, dest, summary = sys.argv[1:]
key = 'widget' + widget_id
tree = ET.parse(src)
root = tree.getroot()
for node in root:
    if node.tag != 'string' or node.attrib.get('name') != key:
        continue
    data = json.loads(node.text or '{}')
    original = bool(data.get('hide_dividers', False))
    mutated = not original
    data['hide_dividers'] = mutated
    node.text = json.dumps(data, separators=(',', ':'))
    tree.write(dest, encoding='utf-8', xml_declaration=True)
    open(summary, 'w', encoding='utf-8').write(
        f'baseline_hide_dividers={str(original).lower()}\nmutated_hide_dividers={str(mutated).lower()}\n')
    raise SystemExit(0)
raise SystemExit('widget preference not found for mutation: ' + key)
PY
adb shell am force-stop com.painless.pc
cat "$OUT/state/widget-prefs-mutated.xml" | adb shell run-as com.painless.pc sh -c 'cat > shared_prefs/widget_preference.xml'
adb shell run-as com.painless.pc chmod 600 shared_prefs/widget_preference.xml
adb shell run-as com.painless.pc rm -f shared_prefs/widget_preference.xml.bak
pull_widget_prefs "$OUT/state/widget-prefs-mutated-readback.xml"
extract_widget_settings "$OUT/state/widget-prefs-mutated-readback.xml" "$WIDGET_ID" "$OUT/state/mutated-settings.json"
python3 - "$OUT/state/baseline-settings.json" "$OUT/state/mutated-settings.json" <<'PY'
import json, sys
a=json.load(open(sys.argv[1], encoding='utf-8'))
b=json.load(open(sys.argv[2], encoding='utf-8'))
a_val=bool(a.get('hide_dividers', False)); b_val=bool(b.get('hide_dividers', False))
if a_val == b_val:
    raise SystemExit('Harness mutation did not create a semantic divergence')
print(f'mutation_diverged=PASS baseline={a_val} mutated={b_val}')
PY

# Reopen mutated widget, then restore the actual file through ACTION_OPEN_DOCUMENT.
adb logcat -c
probe reopen --ei widget_id "$WIDGET_ID" > "$OUT/state/roundtrip-mutated-reopen-dispatch.txt"
sleep 2
capture "16-roundtrip-mutated-reopen"
tap_node "17-roundtrip-restore-overflow-source" "More options"
sleep 1
capture "17-roundtrip-restore-overflow"
tap_node "18-roundtrip-restore-source" "Restore Backup"
sleep 2
capture "18-roundtrip-open-document"
assert_document_picker "18-roundtrip-open-document"

if ! wait_for_node "19-roundtrip-backup-file-wait" "power-toggles-backup.zip" 5; then
  tap_node "19-roundtrip-roots-source" "Show roots"
  sleep 1
  wait_for_node "19-roundtrip-downloads-wait" "Downloads" 5
  tap_node "19-roundtrip-downloads-source" "Downloads"
  sleep 2
  wait_for_node "19-roundtrip-backup-file-wait-downloads" "power-toggles-backup.zip" 8
fi
capture "19-roundtrip-backup-visible"
adb logcat -c
tap_node "20-roundtrip-backup-select-source" "power-toggles-backup.zip"
sleep 4
capture "20-roundtrip-after-import"
grep -Fq 'package="com.painless.pc"' "$OUT/ui/20-roundtrip-after-import.xml"
fatal_scan "20-roundtrip-after-import"

# Persist the imported in-memory definition through the real Done control.
tap_node "21-roundtrip-restored-done-source" "Done"
sleep 3
fatal_scan "21-roundtrip-restored-save"
pull_widget_prefs "$OUT/state/widget-prefs-restored.xml"
extract_widget_settings "$OUT/state/widget-prefs-restored.xml" "$WIDGET_ID" "$OUT/state/restored-settings.json"
python3 -m json.tool "$OUT/state/restored-settings.json" > "$OUT/state/restored-settings.pretty.json"
compare_json "$OUT/state/baseline-settings.json" "$OUT/state/restored-settings.json" "restored_settings_match_baseline"

# Force a fresh process and reopen the exact shipping widget-settings route to
# prove the restored preference survives process death and remains consumable.
adb shell am force-stop com.painless.pc
sleep 1
adb logcat -c
probe reopen --ei widget_id "$WIDGET_ID" > "$OUT/state/roundtrip-persistence-reopen-dispatch.txt"
sleep 2
capture "22-roundtrip-persistence-reopen"
grep -q 'com.painless.pc/.cfg.WidgetConfigActivity' "$OUT/state/22-roundtrip-persistence-reopen.activities.txt"
fatal_scan "22-roundtrip-persistence-reopen"
pull_widget_prefs "$OUT/state/widget-prefs-persistence-readback.xml"
extract_widget_settings "$OUT/state/widget-prefs-persistence-readback.xml" "$WIDGET_ID" "$OUT/state/persistence-settings.json"
compare_json "$OUT/state/baseline-settings.json" "$OUT/state/persistence-settings.json" "restored_settings_survive_process_restart"
adb shell input keyevent KEYCODE_BACK >/dev/null 2>&1 || true

probe delete --ei widget_id "$WIDGET_ID" > "$OUT/state/roundtrip-delete.txt" || true

echo "backup_destination=PASS_SAF_DOCUMENT_CREATE" > "$OUT/summary.txt"
echo "restore_source=PASS_SAF_DOCUMENT_OPEN" >> "$OUT/summary.txt"
echo "cancel_return=PASS" >> "$OUT/summary.txt"
echo "actual_backup_file=PASS_NONEMPTY_VALID_ZIP" >> "$OUT/summary.txt"
echo "backup_config_integrity=PASS" >> "$OUT/summary.txt"
echo "known_setting_mutation=PASS" >> "$OUT/summary.txt"
echo "restore_data_integrity=PASS" >> "$OUT/summary.txt"
echo "restore_process_persistence=PASS" >> "$OUT/summary.txt"
echo "roundtrip_widget_id=$WIDGET_ID" >> "$OUT/summary.txt"
cat "$OUT/summary.txt"
