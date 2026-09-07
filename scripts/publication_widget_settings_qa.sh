#!/usr/bin/env bash
set -euo pipefail

OUT="runtime-evidence/widget-settings"
mkdir -p "$OUT" runtime-evidence/screens runtime-evidence/ui runtime-evidence/state runtime-evidence/logs
USER_ID="$(adb shell am get-current-user | tr -d '\r')"
case "$USER_ID" in
  ''|*[!0-9]*) echo "Unable to resolve numeric Android user: $USER_ID"; exit 1 ;;
esac
printf 'android_user_id=%s\n' "$USER_ID" > "$OUT/android-user.txt"

cleanup() {
  adb shell am force-stop com.painless.pc >/dev/null 2>&1 || true
  adb shell appwidget revokebind --package com.painless.pc --user "$USER_ID" >/dev/null 2>&1 || true
}
trap cleanup EXIT

probe() {
  local action="$1"
  shift || true
  adb shell am start -W -n com.painless.pc/.tracker.PublicationWidgetHostProbeActivity \
    --es probe "$action" "$@"
}

pull_prefs() {
  adb shell run-as com.painless.pc cat shared_prefs/publication_widget_host_probe.xml
}

dump_ui() {
  local name="$1"
  local remote="/sdcard/${name}.xml"
  adb shell uiautomator dump "$remote" >/dev/null
  adb pull "$remote" "runtime-evidence/ui/${name}.xml" >/dev/null
  test -s "runtime-evidence/ui/${name}.xml"
}

capture() {
  local name="$1"
  dump_ui "$name"
  adb exec-out screencap -p > "runtime-evidence/screens/${name}.png"
  adb shell dumpsys activity activities > "runtime-evidence/state/${name}.activities.txt"
  adb shell dumpsys window windows > "runtime-evidence/state/${name}.windows.txt"
}

assert_no_fatal() {
  local name="$1"
  adb logcat -d > "runtime-evidence/logs/${name}.logcat.txt"
  if grep -E "FATAL EXCEPTION|Process: com\\.painless\\.pc.*has died|ANR in com\\.painless\\.pc|am_crash.*com\\.painless\\.pc|am_anr.*com\\.painless\\.pc" \
      "runtime-evidence/logs/${name}.logcat.txt"; then
    echo "Fatal runtime signal during Widget Settings QA: $name"
    exit 1
  fi
}

read_pref() {
  local key="$1"
  python3 - "$OUT/prefs.xml" "$key" <<'PY'
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

# The debug APK is acting as a real AppWidgetHost for this proof. Android's
# framework shell command grants only the bind permission needed for the isolated
# emulator host; the grant is revoked by the EXIT trap. Android 16's appwidget
# shell path does not resolve the special USER_CURRENT (-2) token here, so use the
# actual numeric foreground user returned by ActivityManager.
adb shell appwidget grantbind --package com.painless.pc --user "$USER_ID" | tee "$OUT/grantbind.txt"
adb logcat -c
probe allocate_bind > "$OUT/allocate-bind.txt"
pull_prefs > "$OUT/prefs.xml"
WIDGET_ID="$(read_pref widget_id)"
BOUND="$(read_pref bound)"
PROVIDER_PRESENT="$(read_pref provider_info_present)"
PROVIDER="$(read_pref provider)"
ALLOCATE_ERROR="$(read_pref allocate_error)"

test "$WIDGET_ID" -gt 0
test "$BOUND" = "true"
test "$PROVIDER_PRESENT" = "true"
test -z "$ALLOCATE_ERROR"
case "$PROVIDER" in
  com.painless.pc/.PCWidgetActivity|com.painless.pc/com.painless.pc.PCWidgetActivity) ;;
  *) echo "Unexpected bound provider: $PROVIDER"; exit 1 ;;
esac
printf 'widget_id=%s\nbound=%s\nprovider=%s\n' "$WIDGET_ID" "$BOUND" "$PROVIDER" > "$OUT/binding-summary.txt"
assert_no_fatal allocate-bind

# Configure the genuine framework-allocated ID through the shipping configuration
# activity. This is the normal APPWIDGET_CONFIGURE entry path, not a synthetic ID.
adb logcat -c
adb shell am start -W -a android.appwidget.action.APPWIDGET_CONFIGURE \
  -n com.painless.pc/.cfg.WidgetConfigActivity --ei appWidgetId "$WIDGET_ID" \
  > "$OUT/configure-start.txt"
sleep 2
capture "30-widget-settings-genuine-create"

DONE_COORDS="$(python3 - runtime-evidence/ui/30-widget-settings-genuine-create.xml <<'PY'
import re
import sys
import xml.etree.ElementTree as ET
for node in ET.parse(sys.argv[1]).iter():
    text = (node.attrib.get('text') or '').strip().lower()
    desc = (node.attrib.get('content-desc') or '').strip().lower()
    if text != 'done' and desc != 'done':
        continue
    m = re.fullmatch(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]', node.attrib.get('bounds', ''))
    if not m:
        continue
    x1,y1,x2,y2 = map(int,m.groups())
    print((x1+x2)//2, (y1+y2)//2)
    raise SystemExit(0)
raise SystemExit('Rendered Done control not found')
PY
)"
read -r DONE_X DONE_Y <<< "$DONE_COORDS"
adb shell input tap "$DONE_X" "$DONE_Y"
sleep 2
assert_no_fatal configure-save

probe status --ei widget_id "$WIDGET_ID" > "$OUT/status-after-config.txt"
pull_prefs > "$OUT/prefs.xml"
test "$(read_pref status_widget_id)" = "$WIDGET_ID"
test "$(read_pref status_provider_info_present)" = "true"
test "$(read_pref settings_present)" = "true"
test "$(read_pref status_error)" = ""
SETTINGS_LENGTH="$(read_pref settings_length)"
test "$SETTINGS_LENGTH" -gt 2
printf 'configured_widget_id=%s\nsettings_length=%s\n' "$WIDGET_ID" "$SETTINGS_LENGTH" > "$OUT/configured-summary.txt"

# Reopen through the exact shipping widget-button transport: RVFactory.makeIntent
# -> CATEGORY_ALTERNATIVE -> CommandReceiver -> tracker 33 -> showWidgetConfig.
adb logcat -c
probe reopen --ei widget_id "$WIDGET_ID" > "$OUT/reopen-dispatch.txt"
sleep 2
capture "31-widget-settings-genuine-reopen"
grep -q 'com.painless.pc/.cfg.WidgetConfigActivity' runtime-evidence/state/31-widget-settings-genuine-reopen.activities.txt
pull_prefs > "$OUT/prefs.xml"
test "$(read_pref reopen_widget_id)" = "$WIDGET_ID"
grep -Fq "#$WIDGET_ID" "$OUT/prefs.xml"
assert_no_fatal genuine-reopen
adb shell input keyevent KEYCODE_BACK
sleep 1

# Delete the genuine hosted ID, then send the same shipping tracker-33 route with
# the now-stale numeric ID. The legacy app may render a fallback edit surface, but
# it must remain bounded and non-fatal; the framework binding must stay deleted.
probe delete --ei widget_id "$WIDGET_ID" > "$OUT/delete.txt"
pull_prefs > "$OUT/prefs.xml"
test "$(read_pref deleted_widget_id)" = "$WIDGET_ID"
test "$(read_pref provider_present_after_delete)" = "false"
test "$(read_pref delete_error)" = ""

adb logcat -c
probe reopen --ei widget_id "$WIDGET_ID" > "$OUT/stale-reopen-dispatch.txt"
sleep 2
adb shell dumpsys activity activities > "$OUT/stale-reopen-activities.txt"
adb exec-out screencap -p > runtime-evidence/screens/32-widget-settings-stale-reopen.png
assert_no_fatal stale-reopen
probe status --ei widget_id "$WIDGET_ID" > "$OUT/status-after-stale.txt"
pull_prefs > "$OUT/prefs.xml"
test "$(read_pref status_provider_info_present)" = "false"
adb shell input keyevent KEYCODE_BACK >/dev/null 2>&1 || true
sleep 1

# Malformed fragments are caught inside the shipping CommandReceiver. Prove the
# process remains healthy and no fatal/ANR is emitted.
adb logcat -c
probe malformed > "$OUT/malformed-dispatch.txt"
sleep 1
assert_no_fatal malformed-id
adb shell pidof com.painless.pc > "$OUT/process-after-malformed.txt"
test -s "$OUT/process-after-malformed.txt"

printf 'ID33_WIDGET_SETTINGS=PASS\nwidget_id=%s\nbound_provider=%s\ngenuine_reopen=PASS\nstale_numeric=PASS_NO_FATAL\nmalformed_fragment=PASS_NO_FATAL\n' \
  "$WIDGET_ID" "$PROVIDER" | tee "$OUT/summary.txt"
