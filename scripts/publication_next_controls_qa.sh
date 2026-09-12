#!/usr/bin/env bash
set -u

OUT="runtime-evidence/next-controls"
mkdir -p "$OUT/screens" "$OUT/state" "$OUT/logs" "$OUT/ui"
PKG="com.painless.pc"
PROBE="$PKG/.tracker.PublicationRemainingProbeActivity"
fail=0
battery_result="UNKNOWN"
media_result="UNKNOWN"
volume_result="UNKNOWN"

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

xml_int() {
  local file="$1"
  local key="$2"
  sed -n "s/.*<int name=\"${key}\" value=\"\([^\"]*\)\".*/\1/p" "$file" | head -n 1
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

# ID 15 Battery Info.
adb shell am force-stop "$PKG" || true
adb logcat -c || true
run_probe battery_info || true
sleep 2
capture_log 60-battery-info
dump_ui 60-battery-info || true
adb exec-out screencap -p > "$OUT/screens/60-battery-info.png"
if app_fatal "$OUT/logs/60-battery-info.logcat.txt"; then
  battery_result="FAIL_FATAL"; fail=1
elif grep -Eqi "com\.android\.settings.*(Battery|Power|fuelgauge)|Battery|Power usage" \
    "$OUT/state/60-battery-info-activities.txt" "$OUT/state/60-battery-info-windows.txt" "$OUT/ui/60-battery-info.xml" 2>/dev/null; then
  battery_result="PASS_SETTINGS_SURFACE"
else
  battery_result="FAIL_SETTINGS_SURFACE"; fail=1
fi
adb shell input keyevent KEYCODE_BACK || true
sleep 1

# IDs 18-20 Media transport against a real active MediaSession.
adb shell am force-stop "$PKG" || true
adb logcat -c || true
run_probe media_transport || true
sleep 3
capture_log 61-media-transport
adb exec-out run-as "$PKG" cat shared_prefs/publication_remaining_probe.xml > "$OUT/state/media-transport-probe.xml" 2>/dev/null || true
media_supported="$(xml_bool "$OUT/state/media-transport-probe.xml" media_session_supported)"
media_play_pause="$(xml_int "$OUT/state/media-transport-probe.xml" media_play_pause_count)"
media_next="$(xml_int "$OUT/state/media-transport-probe.xml" media_next_count)"
media_prev="$(xml_int "$OUT/state/media-transport-probe.xml" media_prev_count)"
if app_fatal "$OUT/logs/61-media-transport.logcat.txt"; then
  media_result="FAIL_FATAL"; fail=1
elif [ "$media_supported" != "true" ]; then
  media_result="FAIL_SESSION_UNSUPPORTED"; fail=1
elif [ -z "$media_play_pause" ] || [ -z "$media_next" ] || [ -z "$media_prev" ]; then
  media_result="FAIL_STATE_MISSING"; fail=1
elif [ "$media_play_pause" -lt 1 ] || [ "$media_next" -lt 1 ] || [ "$media_prev" -lt 1 ]; then
  media_result="FAIL_DELIVERY"; fail=1
else
  media_result="PASS_ACTIVE_MEDIA_SESSION_DELIVERY"
fi

# ID 10 Volume Toggle, phase A: with no Notification Policy access, a DND-crossing
# transition must not crash and must route the user to Android's policy-access screen.
adb shell cmd notification disallow_dnd "$PKG" > "$OUT/state/volume-disallow-dnd.txt" 2>&1 || true
adb shell am force-stop "$PKG" || true
adb logcat -c || true
run_probe volume_toggle || true
sleep 2
capture_log 62-volume-no-policy
dump_ui 62-volume-no-policy || true
adb exec-out screencap -p > "$OUT/screens/62-volume-no-policy.png"
adb exec-out run-as "$PKG" cat shared_prefs/publication_remaining_probe.xml > "$OUT/state/volume-no-policy-probe.xml" 2>/dev/null || true
volume_no_policy="$(xml_bool "$OUT/state/volume-no-policy-probe.xml" volume_policy_access)"
volume_no_policy_threw="$(xml_bool "$OUT/state/volume-no-policy-probe.xml" volume_threw)"
volume_no_policy_before="$(xml_int "$OUT/state/volume-no-policy-probe.xml" volume_before)"
volume_no_policy_after="$(xml_int "$OUT/state/volume-no-policy-probe.xml" volume_after)"
volume_route=false
if grep -Eqi "Notification.*policy|Do Not Disturb|Special app access|notification policy" \
    "$OUT/state/62-volume-no-policy-activities.txt" "$OUT/state/62-volume-no-policy-windows.txt" "$OUT/ui/62-volume-no-policy.xml" 2>/dev/null; then
  volume_route=true
fi
if app_fatal "$OUT/logs/62-volume-no-policy.logcat.txt" || [ "$volume_no_policy_threw" != "false" ] || \
   [ "$volume_no_policy" != "false" ] || [ "$volume_route" != "true" ]; then
  volume_result="FAIL_NO_POLICY_ROUTE"; fail=1
else
  # Return from system settings before granting QA-only access from the shell.
  adb shell input keyevent KEYCODE_BACK || true
  sleep 1
  if ! adb shell cmd notification allow_dnd "$PKG" > "$OUT/state/volume-allow-dnd.txt" 2>&1; then
    volume_result="FAIL_QA_GRANT"
    fail=1
  else
    # Phase B: once the user-grantable access exists, require a real shipping
    # ringer transition and exact restoration of the original state.
    adb shell am force-stop "$PKG" || true
    adb logcat -c || true
    run_probe volume_toggle || true
    sleep 1
    capture_log 63-volume-with-policy
    adb exec-out run-as "$PKG" cat shared_prefs/publication_remaining_probe.xml > "$OUT/state/volume-with-policy-probe.xml" 2>/dev/null || true
    volume_policy_access="$(xml_bool "$OUT/state/volume-with-policy-probe.xml" volume_policy_access)"
    volume_before="$(xml_int "$OUT/state/volume-with-policy-probe.xml" volume_before)"
    volume_after="$(xml_int "$OUT/state/volume-with-policy-probe.xml" volume_after)"
    volume_restored="$(xml_int "$OUT/state/volume-with-policy-probe.xml" volume_restored)"
    volume_threw="$(xml_bool "$OUT/state/volume-with-policy-probe.xml" volume_threw)"
    volume_restore_threw="$(xml_bool "$OUT/state/volume-with-policy-probe.xml" volume_restore_threw)"
    if app_fatal "$OUT/logs/63-volume-with-policy.logcat.txt"; then
      volume_result="FAIL_FATAL"; fail=1
    elif [ "$volume_policy_access" != "true" ] || [ "$volume_threw" != "false" ]; then
      volume_result="FAIL_GRANTED_MUTATION"; fail=1
    elif [ -z "$volume_before" ] || [ -z "$volume_after" ] || [ -z "$volume_restored" ] || [ "$volume_after" = "$volume_before" ]; then
      volume_result="FAIL_NO_TRANSITION"; fail=1
    elif [ "$volume_restore_threw" != "false" ] || [ "$volume_restored" != "$volume_before" ]; then
      volume_result="FAIL_RESTORE"; fail=1
    else
      volume_result="PASS_USER_ROUTE+GRANTED_TRANSITION_AND_RESTORE"
    fi
  fi
fi
adb shell cmd notification disallow_dnd "$PKG" > "$OUT/state/volume-final-disallow-dnd.txt" 2>&1 || true

printf '%s\n' \
  "battery_info=$battery_result" \
  "media_transport=$media_result" \
  "media_session_supported=$media_supported" \
  "media_play_pause_count=$media_play_pause" \
  "media_next_count=$media_next" \
  "media_prev_count=$media_prev" \
  "volume_toggle=$volume_result" \
  "volume_no_policy_access=$volume_no_policy" \
  "volume_no_policy_threw=$volume_no_policy_threw" \
  "volume_no_policy_route=$volume_route" \
  "volume_no_policy_before=$volume_no_policy_before" \
  "volume_no_policy_after=$volume_no_policy_after" \
  "volume_policy_access=${volume_policy_access:-missing}" \
  "volume_before=${volume_before:-missing}" \
  "volume_after=${volume_after:-missing}" \
  "volume_restored=${volume_restored:-missing}" \
  > "$OUT/summary.txt"

cat "$OUT/summary.txt"
if [ "$fail" -ne 0 ]; then
  echo "Publication next-controls QA: RED" >&2
  exit 1
fi

echo "Publication next-controls QA: PASS"
