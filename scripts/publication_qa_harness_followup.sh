#!/usr/bin/env bash
set -euo pipefail

# QA-only follow-up normalization for defects independently observed in the
# c7364fe9 hosted evidence. Shipping source is intentionally untouched.
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

# 1) The core Gate-2A widget interaction still used synthetic IDs 1002/1003.
# Modern shipping code correctly rejects unbound IDs. Allocate/bind one genuine
# framework widget through the existing debug-only host probe, exercise the same
# configurator/picker flow against it, then delete it and revoke bind authority.
widget_old = r'''# Widget configurator and picker evidence.
adb shell am force-stop com.painless.pc
adb logcat -c
adb shell am start -W -a android.appwidget.action.APPWIDGET_CONFIGURE \
  -n com.painless.pc/.cfg.WidgetConfigActivity --ei appWidgetId 1002 \
  > "$OUT/state/widget-config-interaction-start.txt" 2>&1
sleep 2
adb shell input tap 540 451
sleep 1
capture "17-widget-style-expanded"
grep -Eqi 'Full height|Huge icons|Indicator|Labels' "$OUT/ui/17-widget-style-expanded.xml"

adb shell am force-stop com.painless.pc
adb shell am start -W -a android.appwidget.action.APPWIDGET_CONFIGURE \
  -n com.painless.pc/.cfg.WidgetConfigActivity --ei appWidgetId 1003 \
  > "$OUT/state/widget-add-toggle-start.txt" 2>&1
'''
widget_new = r'''# Widget configurator and picker evidence against a genuine framework-bound ID.
RUNTIME_WIDGET_USER="$(adb shell am get-current-user | tr -d '\r')"
case "$RUNTIME_WIDGET_USER" in
  ''|*[!0-9]*) echo "Unable to resolve numeric Android user: $RUNTIME_WIDGET_USER" >&2; exit 1 ;;
esac
adb shell appwidget grantbind --package com.painless.pc --user "$RUNTIME_WIDGET_USER" > "$OUT/state/runtime-widget-grantbind.txt"
adb shell am force-stop com.painless.pc
adb logcat -c
adb shell am start -W -n com.painless.pc/.tracker.PublicationWidgetHostProbeActivity \
  --es probe allocate_bind > "$OUT/state/runtime-widget-allocate-bind.txt"
sleep 1
adb shell run-as com.painless.pc cat shared_prefs/publication_widget_host_probe.xml > "$OUT/state/runtime-widget-probe-prefs.xml"
RUNTIME_WIDGET_ID="$(python3 -c 'import sys,xml.etree.ElementTree as ET; r=ET.parse(sys.argv[1]).getroot(); print(next(n.attrib["value"] for n in r if n.attrib.get("name")=="widget_id"))' "$OUT/state/runtime-widget-probe-prefs.xml")"
test "$RUNTIME_WIDGET_ID" -gt 0
grep -Eq 'name="bound" value="true"|value="true" name="bound"' "$OUT/state/runtime-widget-probe-prefs.xml"
grep -Eq 'name="provider_info_present" value="true"|value="true" name="provider_info_present"' "$OUT/state/runtime-widget-probe-prefs.xml"

adb shell am force-stop com.painless.pc
adb logcat -c
adb shell am start -W -a android.appwidget.action.APPWIDGET_CONFIGURE \
  -n com.painless.pc/.cfg.WidgetConfigActivity --ei appWidgetId "$RUNTIME_WIDGET_ID" \
  > "$OUT/state/widget-config-interaction-start.txt" 2>&1
sleep 2
adb shell input tap 540 451
sleep 1
capture "17-widget-style-expanded"
grep -Eqi 'Full height|Huge icons|Indicator|Labels' "$OUT/ui/17-widget-style-expanded.xml"

adb shell am force-stop com.painless.pc
adb shell am start -W -a android.appwidget.action.APPWIDGET_CONFIGURE \
  -n com.painless.pc/.cfg.WidgetConfigActivity --ei appWidgetId "$RUNTIME_WIDGET_ID" \
  > "$OUT/state/widget-add-toggle-start.txt" 2>&1
'''
replace_once('scripts/gate2a_runtime_qa.sh', widget_old, widget_new,
             'core widget interaction moved to genuine framework-bound ID')

cleanup_old = r'''capture "18b-widget-battery-visible"
grep -qi 'Battery Info' "$OUT/ui/18b-widget-battery-visible.xml"
adb shell input keyevent KEYCODE_BACK || true
'''
cleanup_new = cleanup_old + r'''adb shell am force-stop com.painless.pc >/dev/null 2>&1 || true
adb shell am start -W -n com.painless.pc/.tracker.PublicationWidgetHostProbeActivity \
  --es probe delete --ei widget_id "$RUNTIME_WIDGET_ID" > "$OUT/state/runtime-widget-delete.txt"
adb shell appwidget revokebind --package com.painless.pc --user "$RUNTIME_WIDGET_USER" >/dev/null 2>&1 || true
'''
replace_once('scripts/gate2a_runtime_qa.sh', cleanup_old, cleanup_new,
             'genuine runtime widget cleanup')

# 2) The import/export suite repaired its first tracker-33 reopen but retained a
# second stale WidgetConfigActivity assertion after process death. Existing
# widgets correctly reopen in EditWidgetConfigActivity.
replace_once(
    'scripts/publication_import_export_qa.sh',
    "grep -q 'com.painless.pc/.cfg.WidgetConfigActivity' \"$OUT/state/22-roundtrip-persistence-reopen.activities.txt\"",
    "grep -q 'com.painless.pc/.cfg.EditWidgetConfigActivity' \"$OUT/state/22-roundtrip-persistence-reopen.activities.txt\"",
    'import/export persistence reopen assertion repaired')

# 3) The previous positive folder-share probe attempted to manufacture a URI
# grant from the adb-shell sender. Shell does not own Power Toggles' provider and
# cannot confer that capability. Instead, select the QA consumer from the real
# Power Toggles ShareActionProvider chooser so Android propagates the owning
# app's FLAG_GRANT_READ_URI_PERMISSION/ClipData grant to the recipient.
share_old = r'''adb shell run-as "$CONSUMER_PKG" rm -f files/result.txt >/dev/null 2>&1 || true
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
share_new = r'''adb shell run-as "$CONSUMER_PKG" rm -f files/result.txt >/dev/null 2>&1 || true
adb logcat -c
tap_node "02-share-source" "Share"
sleep 2
# ShareActionProvider may first show a compact submenu. Prefer a direct target;
# otherwise open the full chooser through its rendered "Choose an app" affordance.
if ! wait_for_node "02-share-target-wait" "QA Folder Share Consumer" 3; then
  if wait_for_node "02-share-choose-app-wait" "Choose an app" 5; then
    capture "02-share-compact-targets"
    tap_node "02-share-choose-app-source" "Choose an app"
    sleep 2
  fi
fi
wait_for_node "02-share-consumer-wait" "QA Folder Share Consumer" 10
capture "02-share-target-list"
tap_node "02-share-target-source" "QA Folder Share Consumer"
sleep 2
adb shell run-as "$CONSUMER_PKG" cat files/result.txt > "$OUT/state/share-positive-result.txt"
grep -Eq '^PASS bytes=[1-9][0-9]* uri=content://com\.painless\.pc\.file/folder-share$' "$OUT/state/share-positive-result.txt"
adb exec-out run-as com.painless.pc cat files/folder.pcf > "$OUT/state/customer-share-created-folder.pcf"
test -s "$OUT/state/customer-share-created-folder.pcf"
unzip -t "$OUT/state/customer-share-created-folder.pcf" | tee "$OUT/state/customer-share-created-unzip-test.txt"
'''
replace_once('scripts/publication_folder_backup_share_qa.sh', share_old, share_new,
             'folder-share positive proof moved to true owner-originated URI grant')

print('Publication QA harness follow-up: PASS')
PY

echo "Publication QA harness follow-up: PASS"
