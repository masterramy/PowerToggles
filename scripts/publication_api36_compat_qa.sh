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
sync_result="UNKNOWN"
rotation_lock_result="UNKNOWN"
pulse_result="UNKNOWN"
home_result="UNKNOWN"

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

xml_bool() {
  local file="$1"
  local key="$2"
  if grep -Eq "<boolean name=\"${key}\" value=\"true\"" "$file" 2>/dev/null; then
    printf 'true'
  elif grep -Eq "<boolean name=\"${key}\" value=\"false\"" "$file" 2>/dev/null; then
    printf 'false'
  else
    printf 'missing'
  fi
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

# ID 2 Data Sync. Exercise the real ContentResolver master-sync mutation and
# prove the exact original state is restored. This is account-independent.
adb shell am force-stop "$PKG" || true
adb logcat -c || true
run_probe sync_prepare || true
run_probe sync_state || true
adb exec-out run-as "$PKG" cat shared_prefs/publication_compat_probe.xml > "$OUT/state/sync-before.xml" 2>/dev/null || true
sync_before="$(xml_bool "$OUT/state/sync-before.xml" master_sync_state)"
adb logcat -c || true
run_probe sync_toggle || true
sleep 3
run_probe sync_state || true
adb exec-out run-as "$PKG" cat shared_prefs/publication_compat_probe.xml > "$OUT/state/sync-after.xml" 2>/dev/null || true
sync_after="$(xml_bool "$OUT/state/sync-after.xml" master_sync_state)"
capture_log 50-data-sync-toggled
if app_fatal "$OUT/logs/50-data-sync-toggled.logcat.txt"; then
  sync_result="FAIL_FATAL"
  fail=1
elif [ "$sync_before" = "missing" ] || [ "$sync_after" = "missing" ]; then
  sync_result="FAIL_STATE_MISSING"
  fail=1
elif [ "$sync_before" = "$sync_after" ]; then
  sync_result="FAIL_NO_MUTATION"
  fail=1
else
  sync_result="PASS_MUTATION"
fi
run_probe sync_restore || true
sleep 3
run_probe sync_state || true
adb exec-out run-as "$PKG" cat shared_prefs/publication_compat_probe.xml > "$OUT/state/sync-restored.xml" 2>/dev/null || true
sync_restored="$(xml_bool "$OUT/state/sync-restored.xml" master_sync_state)"
if [ "$sync_restored" != "$sync_before" ]; then
  sync_result="${sync_result}+FAIL_RESTORE"
  fail=1
fi

# IDs 38 and 40 legitimately enter through WRITE_SETTINGS. The preceding
# publication suite leaves the app-op denied, so grant it only for this bounded
# tranche and return it to denied afterward.
adb shell appops set "$PKG" WRITE_SETTINGS allow >/dev/null 2>&1 || true

# ID 38 Rotation Lock. The repaired shipping implementation no longer runs the
# obsolete null-token RLService overlay. Start from Auto, invoke the exact real
# tracker twice, require public rotation-setting transitions, then restore the
# exact original USER_ROTATION / ACCELEROMETER_ROTATION values and preferences.
rotation_original_auto="$(adb shell settings get system accelerometer_rotation | tr -d '\r')"
rotation_original_user="$(adb shell settings get system user_rotation | tr -d '\r')"
adb shell am force-stop "$PKG" || true
adb logcat -c || true
run_probe rotation_lock_prepare || true
rotation_prepared_auto="$(adb shell settings get system accelerometer_rotation | tr -d '\r')"
adb logcat -c || true
run_probe rotation_lock_enable || true
sleep 2
rotation_after_first_auto="$(adb shell settings get system accelerometer_rotation | tr -d '\r')"
rotation_after_first_user="$(adb shell settings get system user_rotation | tr -d '\r')"
capture_log 51-rotation-lock-first
if app_fatal "$OUT/logs/51-rotation-lock-first.logcat.txt"; then
  rotation_lock_result="FAIL_FATAL_FIRST"
  fail=1
elif [ "$rotation_prepared_auto" != "1" ] || [ "$rotation_after_first_auto" != "0" ]; then
  rotation_lock_result="FAIL_FIRST_TRANSITION"
  fail=1
else
  rotation_lock_result="PASS_FIRST_TRANSITION"
fi

adb logcat -c || true
run_probe rotation_lock_disable || true
sleep 2
rotation_after_second_auto="$(adb shell settings get system accelerometer_rotation | tr -d '\r')"
rotation_after_second_user="$(adb shell settings get system user_rotation | tr -d '\r')"
capture_log 52-rotation-lock-second
if app_fatal "$OUT/logs/52-rotation-lock-second.logcat.txt"; then
  rotation_lock_result="${rotation_lock_result}+FAIL_FATAL_SECOND"
  fail=1
elif [ "$rotation_after_second_auto" != "0" ] || [ "$rotation_after_second_user" = "$rotation_after_first_user" ]; then
  rotation_lock_result="${rotation_lock_result}+FAIL_SECOND_TRANSITION"
  fail=1
else
  rotation_lock_result="PASS_TRANSITIONS"
fi

run_probe rotation_lock_restore || true
sleep 1
rotation_restored_auto="$(adb shell settings get system accelerometer_rotation | tr -d '\r')"
rotation_restored_user="$(adb shell settings get system user_rotation | tr -d '\r')"
if [ "$rotation_restored_auto" != "$rotation_original_auto" ] || [ "$rotation_restored_user" != "$rotation_original_user" ]; then
  rotation_lock_result="${rotation_lock_result}+FAIL_RESTORE"
  fail=1
fi

# ID 40 Pulse Notification Light. On hardware without an LED we can still prove
# the shipping WRITE_SETTINGS behavior is safe and restorable; physical LED
# illumination remains a separate device requirement.
pulse_before="$(adb shell settings get system notification_light_pulse | tr -d '\r')"
adb shell am force-stop "$PKG" || true
adb logcat -c || true
run_probe pulse_prepare || true
run_probe pulse_toggle || true
sleep 2
pulse_after="$(adb shell settings get system notification_light_pulse | tr -d '\r')"
capture_log 53-pulse-light-toggled
if app_fatal "$OUT/logs/53-pulse-light-toggled.logcat.txt"; then
  pulse_result="FAIL_FATAL"
  fail=1
elif [ "$pulse_before" = "$pulse_after" ]; then
  pulse_result="FAIL_NO_MUTATION"
  fail=1
else
  pulse_result="PASS_SETTING_MUTATION"
fi
run_probe pulse_restore || true
sleep 1
pulse_restored="$(adb shell settings get system notification_light_pulse | tr -d '\r')"
if [ "$pulse_restored" != "$pulse_before" ]; then
  pulse_result="${pulse_result}+FAIL_RESTORE"
  fail=1
fi
adb shell appops set "$PKG" WRITE_SETTINGS deny >/dev/null 2>&1 || true

# ID 43 Home Shortcut. Invoke the exact shipping HomeCommand and require the
# resolved system home activity to become foreground rather than Power Toggles.
home_component="$(adb shell cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME 2>/dev/null | tr -d '\r' | tail -n 1)"
home_package="${home_component%%/*}"
adb shell am start -W -n "$PKG/.settings.LaunchActivity" >/dev/null 2>&1 || true
sleep 1
adb logcat -c || true
run_probe home || true
sleep 2
capture_log 54-home-shortcut
if app_fatal "$OUT/logs/54-home-shortcut.logcat.txt"; then
  home_result="FAIL_FATAL"
  fail=1
elif [ -z "$home_package" ] || [ "$home_package" = "$home_component" ]; then
  home_result="FAIL_HOME_RESOLUTION"
  fail=1
elif grep -q "$home_package" "$OUT/state/54-home-shortcut-activities.txt"; then
  home_result="PASS_HOME_FOREGROUND"
else
  home_result="FAIL_HOME_NOT_FOREGROUND"
  fail=1
fi

printf '%s\n' \
  "screen_always_on=$screen_on_result" \
  "bluetooth_discovery_state=$bt_state_result" \
  "bluetooth_discovery_toggle=$bt_toggle_result" \
  "data_sync=$sync_result" \
  "data_sync_before=$sync_before" \
  "data_sync_after=$sync_after" \
  "data_sync_restored=$sync_restored" \
  "rotation_lock=$rotation_lock_result" \
  "rotation_original_auto=$rotation_original_auto" \
  "rotation_original_user=$rotation_original_user" \
  "rotation_prepared_auto=$rotation_prepared_auto" \
  "rotation_after_first_auto=$rotation_after_first_auto" \
  "rotation_after_first_user=$rotation_after_first_user" \
  "rotation_after_second_auto=$rotation_after_second_auto" \
  "rotation_after_second_user=$rotation_after_second_user" \
  "rotation_restored_auto=$rotation_restored_auto" \
  "rotation_restored_user=$rotation_restored_user" \
  "pulse_light=$pulse_result" \
  "pulse_before=$pulse_before" \
  "pulse_after=$pulse_after" \
  "pulse_restored=$pulse_restored" \
  "home_shortcut=$home_result" \
  "home_component=$home_component" \
  > "$OUT/summary.txt"

cat "$OUT/summary.txt"
if [ "$fail" -ne 0 ]; then
  echo "Publication API-36 compatibility QA: RED" >&2
  exit 1
fi

echo "Publication API-36 compatibility QA: PASS"
