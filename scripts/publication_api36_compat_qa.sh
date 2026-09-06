#!/usr/bin/env bash
set -u

OUT="runtime-evidence/api36-compat"
mkdir -p "$OUT/screens" "$OUT/state" "$OUT/logs" "$OUT/ui"
PKG="com.painless.pc"
PROBE="$PKG/.tracker.PublicationCompatProbeActivity"
fail=0
screen_on_result="UNKNOWN"
bt_state_result="UNKNOWN"
bt_toggle_result="UNKNOWN"

run_probe() {
  local name="$1"
  adb shell am start -W -n "$PROBE" --es probe "$name" > "$OUT/state/${name}-start.txt" 2>&1
  local rc=$?
  sleep 2
  return $rc
}

capture_log() {
  local slug="$1"
  adb logcat -d > "$OUT/logs/${slug}.logcat.txt"
  adb shell dumpsys activity activities > "$OUT/state/${slug}-activities.txt" 2>&1 || true
  adb shell dumpsys window windows > "$OUT/state/${slug}-windows.txt" 2>&1 || true
}

app_fatal() {
  local file="$1"
  grep -E "FATAL EXCEPTION|Process: ${PKG//./\\.}|ANR in ${PKG//./\\.}|am_crash.*${PKG//./\\.}|am_anr.*${PKG//./\\.}|MissingForegroundServiceTypeException|ForegroundServiceStartNotAllowedException|SecurityException.*(FOREGROUND_SERVICE|BLUETOOTH_)" "$file" >/dev/null 2>&1
}

dump_ui() {
  local slug="$1"
  local remote="/sdcard/${slug}.xml"
  adb shell rm -f "$remote" >/dev/null 2>&1 || true
  for attempt in 1 2 3 4 5; do
    adb shell uiautomator dump "$remote" >/dev/null 2>&1 || true
    if adb shell test -s "$remote" >/dev/null 2>&1; then
      adb pull "$remote" "$OUT/ui/${slug}.xml" >/dev/null 2>&1 || true
      [ -s "$OUT/ui/${slug}.xml" ] && return 0
    fi
    sleep 1
  done
  return 1
}

# ID 13 Screen Always On. Force the real customer foreground-notification branch,
# preserving the user's original notification preference. This intentionally
# exercises the targetSdk-36 service/startForeground compatibility boundary.
adb shell am force-stop "$PKG" || true
adb logcat -c || true
run_probe screen_on_prepare_notification || true
adb logcat -c || true
run_probe screen_on_enable || true
sleep 3
adb shell dumpsys activity services "$PKG" > "$OUT/state/screen-on-enabled-services.txt" 2>&1 || true
adb shell dumpsys notification --noredact > "$OUT/state/screen-on-enabled-notification.txt" 2>&1 || true
capture_log 46-screen-on-enabled
if app_fatal "$OUT/logs/46-screen-on-enabled.logcat.txt"; then
  screen_on_result="FAIL_FATAL"
  fail=1
elif ! grep -q "ScreenOnService" "$OUT/state/screen-on-enabled-services.txt"; then
  screen_on_result="FAIL_SERVICE_NOT_RUNNING"
  fail=1
else
  screen_on_result="PASS_ENABLED"
  adb shell cmd statusbar expand-notifications >/dev/null 2>&1 || true
  sleep 2
  dump_ui 46-screen-on-notification || true
  adb exec-out screencap -p > "$OUT/screens/46-screen-on-notification.png"
  adb shell cmd statusbar collapse >/dev/null 2>&1 || true
  sleep 1
fi
adb logcat -c || true
run_probe screen_on_disable || true
sleep 2
adb shell dumpsys activity services "$PKG" > "$OUT/state/screen-on-disabled-services.txt" 2>&1 || true
capture_log 47-screen-on-disabled
if grep -q "ScreenOnService" "$OUT/state/screen-on-disabled-services.txt"; then
  screen_on_result="${screen_on_result}+FAIL_DISABLE"
  fail=1
fi
run_probe screen_on_restore_notification_pref || true
adb exec-out run-as "$PKG" cat shared_prefs/widget_preference.xml > "$OUT/state/screen-on-restored-widget-prefs.xml" 2>/dev/null || true

# ID 22 Bluetooth Discovery. Exercise both state read and the exact shipping
# discoverability-consent launch independently so one crash does not hide the
# other publication-relevant result.
adb shell am force-stop "$PKG" || true
adb logcat -c || true
run_probe bluetooth_discovery_state || true
sleep 2
capture_log 48-bluetooth-discovery-state
adb exec-out run-as "$PKG" cat shared_prefs/publication_compat_probe.xml > "$OUT/state/bluetooth-discovery-probe.xml" 2>/dev/null || true
if app_fatal "$OUT/logs/48-bluetooth-discovery-state.logcat.txt"; then
  bt_state_result="FAIL_FATAL"
  fail=1
elif grep -q "bluetooth_discovery_state" "$OUT/state/bluetooth-discovery-probe.xml" 2>/dev/null; then
  bt_state_result="PASS_STATE_READ"
else
  bt_state_result="NO_STATE_RECORDED"
fi

adb shell am force-stop "$PKG" || true
adb logcat -c || true
run_probe bluetooth_discovery_toggle || true
sleep 2
capture_log 49-bluetooth-discovery-consent
if app_fatal "$OUT/logs/49-bluetooth-discovery-consent.logcat.txt"; then
  bt_toggle_result="FAIL_FATAL"
  fail=1
else
  dump_ui 49-bluetooth-discovery-consent || true
  adb exec-out screencap -p > "$OUT/screens/49-bluetooth-discovery-consent.png"
  bt_toggle_result="PASS_NO_FATAL"
  adb shell input keyevent KEYCODE_BACK || true
  sleep 1
fi

printf '%s\n' \
  "screen_always_on=$screen_on_result" \
  "bluetooth_discovery_state=$bt_state_result" \
  "bluetooth_discovery_toggle=$bt_toggle_result" \
  > "$OUT/summary.txt"

cat "$OUT/summary.txt"
if [ "$fail" -ne 0 ]; then
  echo "Publication API-36 compatibility QA: RED" >&2
  exit 1
fi

echo "Publication API-36 compatibility QA: PASS"
