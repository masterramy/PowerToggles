#!/usr/bin/env bash
set -u

OUT="runtime-evidence/remaining-controls"
mkdir -p "$OUT/screens" "$OUT/state" "$OUT/logs" "$OUT/ui"
PKG="com.painless.pc"
PROBE="$PKG/.tracker.PublicationRemainingProbeActivity"
ADMIN="$PKG/.LockAdmin"
fail=0
screen_lock_result="UNKNOWN"
sync_now_result="UNKNOWN"
notify_widget_result="UNKNOWN"
two_row_result="UNKNOWN"

run_probe() {
  local name="$1"
  adb shell am start -W -n "$PROBE" --es probe "$name" > "$OUT/state/${name}-start.txt" 2>&1
  local rc=$?
  sleep 1
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
  grep -E "FATAL EXCEPTION|Process: ${PKG//./\\.}|ANR in ${PKG//./\\.}|am_crash.*${PKG//./\\.}|am_anr.*${PKG//./\\.}" "$file" >/dev/null 2>&1
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

xml_int() {
  local file="$1"
  local key="$2"
  sed -n "s/.*<int name=\"${key}\" value=\"\([^\"]*\)\".*/\1/p" "$file" | head -n 1
}

# ID 25 Screen Lock: first exercise the exact customer path with Device Admin
# absent and retain the Android consent surface. Then activate the same declared
# admin only as bounded QA setup, invoke the exact tracker again, and require
# DevicePolicyManager.lockNow() to put the emulator to sleep. The emulator is
# ephemeral; removal is attempted after evidence collection.
adb shell am force-stop "$PKG" || true
adb shell dpm remove-active-admin --user 0 "$ADMIN" > "$OUT/state/screen-lock-preclean.txt" 2>&1 || true
adb logcat -c || true
run_probe screen_lock || true
sleep 2
capture_log 55-screen-lock-admin-consent
dump_ui 55-screen-lock-admin-consent || true
adb exec-out screencap -p > "$OUT/screens/55-screen-lock-admin-consent.png"
if app_fatal "$OUT/logs/55-screen-lock-admin-consent.logcat.txt"; then
  screen_lock_result="FAIL_CONSENT_FATAL"
  fail=1
elif grep -Eqi "DeviceAdmin|device admin|ADD_DEVICE_ADMIN|Activate.*admin" \
    "$OUT/state/55-screen-lock-admin-consent-activities.txt" \
    "$OUT/state/55-screen-lock-admin-consent-windows.txt" \
    "$OUT/ui/55-screen-lock-admin-consent.xml" 2>/dev/null; then
  screen_lock_result="PASS_CONSENT_SURFACE"
else
  screen_lock_result="FAIL_CONSENT_SURFACE"
  fail=1
fi
adb shell input keyevent KEYCODE_BACK || true
sleep 1

adb shell dpm set-active-admin --user 0 "$ADMIN" > "$OUT/state/screen-lock-admin-activate.txt" 2>&1
admin_rc=$?
if [ "$admin_rc" -ne 0 ]; then
  screen_lock_result="${screen_lock_result}+FAIL_ADMIN_SETUP"
  fail=1
else
  adb logcat -c || true
  run_probe screen_lock || true
  sleep 2
  adb shell dumpsys power > "$OUT/state/screen-lock-after-lock-power.txt" 2>&1 || true
  capture_log 56-screen-lock-active
  if app_fatal "$OUT/logs/56-screen-lock-active.logcat.txt"; then
    screen_lock_result="${screen_lock_result}+FAIL_LOCK_FATAL"
    fail=1
  elif grep -Eq "Wakefulness=Asleep|mWakefulness=Asleep|Display Power: state=OFF|state=OFF" "$OUT/state/screen-lock-after-lock-power.txt"; then
    screen_lock_result="PASS_CONSENT_AND_LOCK"
  else
    screen_lock_result="${screen_lock_result}+FAIL_NOT_LOCKED"
    fail=1
  fi
fi
adb shell input keyevent KEYCODE_WAKEUP || true
adb shell wm dismiss-keyguard || true
adb shell dpm remove-active-admin --user 0 "$ADMIN" > "$OUT/state/screen-lock-admin-remove.txt" 2>&1 || true
sleep 1

# ID 28 Sync Now: exercise the exact shipping AsyncTask on the clean API-36
# emulator. This is deliberately the no-user-account branch; account-populated
# sync-adapter variants remain a device/account coverage item.
adb shell am force-stop "$PKG" || true
adb logcat -c || true
run_probe sync_now || true
sleep 1
dump_ui 57-sync-now || true
adb exec-out screencap -p > "$OUT/screens/57-sync-now.png"
sleep 5
capture_log 57-sync-now
adb exec-out run-as "$PKG" cat shared_prefs/publication_remaining_probe.xml > "$OUT/state/sync-now-probe.xml" 2>/dev/null || true
sync_immediate="$(xml_int "$OUT/state/sync-now-probe.xml" sync_now_immediate_state)"
sync_final="$(xml_int "$OUT/state/sync-now-probe.xml" sync_now_final_state)"
if app_fatal "$OUT/logs/57-sync-now.logcat.txt"; then
  sync_now_result="FAIL_FATAL"
  fail=1
elif [ -z "$sync_immediate" ] || [ -z "$sync_final" ]; then
  sync_now_result="FAIL_STATE_MISSING"
  fail=1
elif [ "$sync_immediate" = "$sync_final" ]; then
  sync_now_result="FAIL_NO_LIFECYCLE"
  fail=1
else
  sync_now_result="PASS_NO_ACCOUNT_LIFECYCLE"
fi

# IDs 32 and 34: invoke the exact shipping trackers twice, require each shared
# NotifyStatus preference to transition out and back, then restore the exact
# original presence/value of both preferences.
adb shell am force-stop "$PKG" || true
adb logcat -c || true
run_probe notify_prepare || true
adb exec-out run-as "$PKG" cat shared_prefs/publication_remaining_probe.xml > "$OUT/state/notify-original-probe.xml" 2>/dev/null || true
original_status="$(xml_bool "$OUT/state/notify-original-probe.xml" original_status)"
original_two_row="$(xml_bool "$OUT/state/notify-original-probe.xml" original_two_row)"
had_status="$(xml_bool "$OUT/state/notify-original-probe.xml" had_status)"
had_two_row="$(xml_bool "$OUT/state/notify-original-probe.xml" had_two_row)"

run_probe notify_widget_toggle || true
adb exec-out run-as "$PKG" cat shared_prefs/widget_preference.xml > "$OUT/state/notify-widget-after-first.xml" 2>/dev/null || true
status_after_first="$(xml_bool "$OUT/state/notify-widget-after-first.xml" status_bar_widget)"
run_probe notify_widget_toggle || true
adb exec-out run-as "$PKG" cat shared_prefs/widget_preference.xml > "$OUT/state/notify-widget-after-second.xml" 2>/dev/null || true
status_after_second="$(xml_bool "$OUT/state/notify-widget-after-second.xml" status_bar_widget)"
if [ "$original_status" = "missing" ] || [ "$status_after_first" = "missing" ] || \
   [ "$status_after_second" = "missing" ]; then
  notify_widget_result="FAIL_STATE_MISSING"
  fail=1
elif [ "$status_after_first" = "$original_status" ] || [ "$status_after_second" != "$original_status" ]; then
  notify_widget_result="FAIL_TRANSITION"
  fail=1
else
  notify_widget_result="PASS_TRANSITIONS"
fi

run_probe two_row_toggle || true
adb exec-out run-as "$PKG" cat shared_prefs/widget_preference.xml > "$OUT/state/two-row-after-first.xml" 2>/dev/null || true
two_row_after_first="$(xml_bool "$OUT/state/two-row-after-first.xml" nofity_two_row)"
run_probe two_row_toggle || true
adb exec-out run-as "$PKG" cat shared_prefs/widget_preference.xml > "$OUT/state/two-row-after-second.xml" 2>/dev/null || true
two_row_after_second="$(xml_bool "$OUT/state/two-row-after-second.xml" nofity_two_row)"
if [ "$original_two_row" = "missing" ] || [ "$two_row_after_first" = "missing" ] || \
   [ "$two_row_after_second" = "missing" ]; then
  two_row_result="FAIL_STATE_MISSING"
  fail=1
elif [ "$two_row_after_first" = "$original_two_row" ] || [ "$two_row_after_second" != "$original_two_row" ]; then
  two_row_result="FAIL_TRANSITION"
  fail=1
else
  two_row_result="PASS_TRANSITIONS"
fi

run_probe notify_restore || true
adb exec-out run-as "$PKG" cat shared_prefs/widget_preference.xml > "$OUT/state/notify-restored-widget-prefs.xml" 2>/dev/null || true
restored_status="$(xml_bool "$OUT/state/notify-restored-widget-prefs.xml" status_bar_widget)"
restored_two_row="$(xml_bool "$OUT/state/notify-restored-widget-prefs.xml" nofity_two_row)"
if [ "$had_status" = "false" ]; then
  [ "$restored_status" = "missing" ] || { notify_widget_result="${notify_widget_result}+FAIL_RESTORE_PRESENCE"; fail=1; }
else
  [ "$restored_status" = "$original_status" ] || { notify_widget_result="${notify_widget_result}+FAIL_RESTORE"; fail=1; }
fi
if [ "$had_two_row" = "false" ]; then
  [ "$restored_two_row" = "missing" ] || { two_row_result="${two_row_result}+FAIL_RESTORE_PRESENCE"; fail=1; }
else
  [ "$restored_two_row" = "$original_two_row" ] || { two_row_result="${two_row_result}+FAIL_RESTORE"; fail=1; }
fi
capture_log 58-notification-command-restored
if app_fatal "$OUT/logs/58-notification-command-restored.logcat.txt"; then
  notify_widget_result="${notify_widget_result}+FAIL_FATAL"
  two_row_result="${two_row_result}+FAIL_FATAL"
  fail=1
fi

printf '%s\n' \
  "screen_lock=$screen_lock_result" \
  "sync_now=$sync_now_result" \
  "sync_now_immediate=$sync_immediate" \
  "sync_now_final=$sync_final" \
  "notification_widget=$notify_widget_result" \
  "notification_original=$original_status" \
  "notification_after_first=$status_after_first" \
  "notification_after_second=$status_after_second" \
  "second_notification_row=$two_row_result" \
  "two_row_original=$original_two_row" \
  "two_row_after_first=$two_row_after_first" \
  "two_row_after_second=$two_row_after_second" \
  > "$OUT/summary.txt"

cat "$OUT/summary.txt"
if [ "$fail" -ne 0 ]; then
  echo "Publication remaining-controls QA: RED" >&2
  exit 1
fi

echo "Publication remaining-controls QA: PASS"
