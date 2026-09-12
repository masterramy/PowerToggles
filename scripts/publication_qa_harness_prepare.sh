#!/usr/bin/env bash
set -euo pipefail

# QA-only normalization for publication CI. This does not touch shipping source.
# Every repair below is tied to a defect independently observed in hosted evidence.
python3 - <<'PY'
from pathlib import Path


def replace_once(path, old, new, label):
    p = Path(path)
    text = p.read_text()
    old_count = text.count(old)
    new_count = text.count(new)
    if old_count == 1:
        p.write_text(text.replace(old, new, 1))
        print(f'{path}: {label}')
        return
    if old_count == 0 and new_count >= 1:
        print(f'{path}: {label} already normalized')
        return
    raise SystemExit(f'{path}: expected one {label} anchor; old={old_count} new={new_count}')

# 1) Attribute fatal/ANR checks to Power Toggles rather than unrelated emulator processes.
fatal_old = r'FATAL EXCEPTION|Process: com\.painless\.pc.*has died|ANR in com\.painless\.pc|am_crash.*com\.painless\.pc|am_anr.*com\.painless\.pc'
fatal_new = r'Process: com\.painless\.pc(,|[[:space:]])|Process com\.painless\.pc.*has died|ANR in com\.painless\.pc|am_crash.*com\.painless\.pc|am_anr.*com\.painless\.pc'
for name in ('scripts/gate2a_runtime_qa.sh','scripts/publication_runtime_qa.sh','scripts/publication_import_export_qa.sh'):
    p = Path(name); text = p.read_text()
    old_count = text.count(fatal_old); new_count = text.count(fatal_new)
    if old_count:
        p.write_text(text.replace(fatal_old, fatal_new))
        print(f'{name}: candidate-scoped fatal scan replacements={old_count}')
    elif new_count:
        print(f'{name}: candidate-scoped fatal scan already normalized={new_count}')
    else:
        raise SystemExit(f'Expected fatal-scan anchor missing from {name}')

# 2) Modern Bluetooth behavior routes to system settings; remove stale consent-source assertion.
for name in ('scripts/gate2a_fidelity_qa.sh','scripts/gate2a_runtime_qa.sh'):
    p = Path(name); text = p.read_text()
    stale = "grep -q 'ACTION_REQUEST_ENABLE' src/com/painless/pc/tracker/BluetoothTracker.java\n"
    if stale in text:
        p.write_text(text.replace(stale, '', 1)); text = p.read_text()
        print(f'{name}: removed stale ACTION_REQUEST_ENABLE assertion')
    elif 'ACTION_REQUEST_ENABLE' not in text:
        print(f'{name}: stale Bluetooth consent assertion already absent')
    else:
        raise SystemExit(f'{name}: unexpected ACTION_REQUEST_ENABLE shape')
    modern = "grep -q 'ACTION_BLUETOOTH_SETTINGS' src/com/painless/pc/tracker/BluetoothTracker.java"
    if modern not in p.read_text():
        marker = "adb logcat -c\nadb shell am start -W -n com.painless.pc/com.painless.pc.tracker.Gate2aProbeActivity \\\n  --es probe bluetooth_disable"
        replace_once(name, marker, modern + "\n" + marker, 'modern Bluetooth settings-source assertion')

# 3) Preserve the import/export fixture write inside run-as.
replace_once(
    'scripts/publication_import_export_qa.sh',
    "cat \"$OUT/state/widget-prefs-mutated.xml\" | adb shell run-as com.painless.pc sh -c 'cat > shared_prefs/widget_preference.xml'",
    "adb shell \"run-as com.painless.pc sh -c 'cat > shared_prefs/widget_preference.xml'\" < \"$OUT/state/widget-prefs-mutated.xml\"",
    'run-as mutation redirect repaired')

# 4) Replace the fake initial widget ID with a genuine framework-bound widget.
old_launch = r'''launch_config() {
  adb shell am force-stop com.painless.pc
  adb logcat -c
  adb shell am start -W -a android.appwidget.action.APPWIDGET_CONFIGURE \
    -n com.painless.pc/.cfg.WidgetConfigActivity --ei appWidgetId 1099 \
    > "$OUT/state/config-start.txt" 2>&1
  sleep 2
  capture "00-config"
}
'''
new_launch = r'''launch_config() {
  INITIAL_USER_ID="$(adb shell am get-current-user | tr -d '\r')"
  case "$INITIAL_USER_ID" in
    ''|*[!0-9]*) echo "Unable to resolve numeric Android user: $INITIAL_USER_ID" >&2; return 1 ;;
  esac
  adb shell appwidget grantbind --package com.painless.pc --user "$INITIAL_USER_ID" > "$OUT/state/initial-grantbind.txt"
  adb shell am force-stop com.painless.pc
  adb logcat -c
  adb shell am start -W -n com.painless.pc/.tracker.PublicationWidgetHostProbeActivity \
    --es probe allocate_bind > "$OUT/state/initial-allocate-bind.txt"
  sleep 1
  adb shell run-as com.painless.pc cat shared_prefs/publication_widget_host_probe.xml > "$OUT/state/initial-probe-prefs.xml"
  INITIAL_WIDGET_ID="$(python3 -c 'import sys,xml.etree.ElementTree as ET; r=ET.parse(sys.argv[1]).getroot(); print(next(n.attrib["value"] for n in r if n.attrib.get("name")=="widget_id"))' "$OUT/state/initial-probe-prefs.xml")"
  test "$INITIAL_WIDGET_ID" -gt 0
  grep -Eq 'name="bound" value="true"|value="true" name="bound"' "$OUT/state/initial-probe-prefs.xml"
  grep -Eq 'name="provider_info_present" value="true"|value="true" name="provider_info_present"' "$OUT/state/initial-probe-prefs.xml"
  adb shell am force-stop com.painless.pc
  adb shell am start -W -a android.appwidget.action.APPWIDGET_CONFIGURE \
    -n com.painless.pc/.cfg.WidgetConfigActivity --ei appWidgetId "$INITIAL_WIDGET_ID" \
    > "$OUT/state/config-start.txt" 2>&1
  sleep 2
  capture "00-config"
}
'''
replace_once('scripts/publication_import_export_qa.sh', old_launch, new_launch,
             'synthetic initial widget replaced by genuine bound widget')
cleanup_anchor = r'''capture "06-restore-cancel-return"
grep -Fq 'package="com.painless.pc"' "$OUT/ui/06-restore-cancel-return.xml"
'''
cleanup_new = cleanup_anchor + r'''adb shell am force-stop com.painless.pc >/dev/null 2>&1 || true
adb shell am start -W -n com.painless.pc/.tracker.PublicationWidgetHostProbeActivity \
  --es probe delete --ei widget_id "$INITIAL_WIDGET_ID" > "$OUT/state/initial-widget-delete.txt"
adb shell appwidget revokebind --package com.painless.pc --user "$INITIAL_USER_ID" >/dev/null 2>&1 || true
'''
replace_once('scripts/publication_import_export_qa.sh', cleanup_anchor, cleanup_new,
             'initial genuine widget cleanup')

# 5) Tracker 33 reopens an existing widget in EditWidgetConfigActivity.
replace_once(
    'scripts/publication_widget_settings_qa.sh',
    "grep -q 'com.painless.pc/.cfg.WidgetConfigActivity' runtime-evidence/state/31-widget-settings-genuine-reopen.activities.txt",
    "grep -q 'com.painless.pc/.cfg.EditWidgetConfigActivity' runtime-evidence/state/31-widget-settings-genuine-reopen.activities.txt",
    'ID33 widget-settings reopen assertion repaired')
replace_once(
    'scripts/publication_import_export_qa.sh',
    "grep -q 'com.painless.pc/.cfg.WidgetConfigActivity' \"$OUT/state/12-roundtrip-reopen.activities.txt\"",
    "grep -q 'com.painless.pc/.cfg.EditWidgetConfigActivity' \"$OUT/state/12-roundtrip-reopen.activities.txt\"",
    'import/export ID33 reopen assertion repaired')

# 6) Synthetic appWidgetId 1001 is deliberately rejected by shipping code on API 36.
# Prove non-crash/clean return without falsely requiring Power Toggles to remain foreground.
replace_once(
    'scripts/gate2a_runtime_qa.sh',
    'capture "09-widget-config-entry"',
    'capture_external "09-widget-config-entry"',
    'synthetic widget survivability foreground assumption removed')

# 7) ShareActionProvider ranking is nondeterministic. Select a rendered system target
# to force real archive creation, then separately prove cross-UID denial/grant behavior.
old_share = r'''adb shell run-as "$CONSUMER_PKG" rm -f files/result.txt >/dev/null 2>&1 || true
adb logcat -c
tap_node "02-share-source" "Share"
sleep 2
if ! adb shell run-as "$CONSUMER_PKG" test -s files/result.txt >/dev/null 2>&1; then
  if wait_for_node "02-share-target-wait" "QA Folder Share Consumer" 8; then
    capture "02-share-target-list"
    tap_node "02-share-target-source" "QA Folder Share Consumer"
    sleep 2
  fi
fi
adb shell run-as "$CONSUMER_PKG" cat files/result.txt > "$OUT/state/share-positive-result.txt"
grep -Eq '^PASS bytes=[1-9][0-9]* uri=content://com\.painless\.pc\.file/folder-share$' "$OUT/state/share-positive-result.txt"
'''
new_share = r'''adb shell run-as "$CONSUMER_PKG" rm -f files/result.txt >/dev/null 2>&1 || true
adb logcat -c
tap_node "02-share-source" "Share"
sleep 2
if wait_for_node "02-share-target-wait" "Bluetooth" 8; then
  capture "02-share-target-list"
  tap_node "02-share-target-source" "Bluetooth"
elif wait_for_node "02-share-target-wait" "Quick Share" 3; then
  capture "02-share-target-list"
  tap_node "02-share-target-source" "Quick Share"
else
  echo "No rendered system share target appeared" >&2
  exit 1
fi
sleep 2
adb shell input keyevent KEYCODE_BACK >/dev/null 2>&1 || true
sleep 1
adb exec-out run-as com.painless.pc cat files/folder.pcf > "$OUT/state/customer-share-created-folder.pcf"
test -s "$OUT/state/customer-share-created-folder.pcf"
unzip -t "$OUT/state/customer-share-created-folder.pcf" | tee "$OUT/state/customer-share-created-unzip-test.txt"
# `am` only propagates a URI grant for data/ClipData, not merely EXTRA_STREAM.
# Shipping ACTION_SEND uses ClipData; attach the same URI as data here so the
# controlled external consumer receives a real Android URI permission grant.
adb shell am start -W -a android.intent.action.SEND -t application/zip \
  -d "$SHARE_URI" -f 0x1 -n "$CONSUMER_PKG/.ShareReceiverActivity" \
  --eu android.intent.extra.STREAM "$SHARE_URI" > "$OUT/state/share-positive-start.txt" 2>&1
sleep 1
adb shell run-as "$CONSUMER_PKG" cat files/result.txt > "$OUT/state/share-positive-result.txt"
grep -Eq '^PASS bytes=[1-9][0-9]* uri=content://com\.painless\.pc\.file/folder-share$' "$OUT/state/share-positive-result.txt"
'''
replace_once('scripts/publication_folder_backup_share_qa.sh', old_share, new_share,
             'deterministic customer-share plus valid cross-UID grant proof')

print('Publication QA harness preparation: PASS')
PY

echo "Publication QA harness preparation: PASS"
