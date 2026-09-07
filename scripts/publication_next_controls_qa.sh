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

# ID 15 Battery Info: invoke the exact shipping BatteryTracker and require its
# ACTION_POWER_USAGE_SUMMARY route to land on a real Android Settings battery/power surface.
adb shell am force-stop "$PKG" || true
adb logcat -c || true
run_probe battery_info || true
sleep 2
capture_log 60-battery-info
dump_ui 60-battery-info || true
adb exec-out screencap -p > "$OUT/screens/60-battery-info.png"
if app_fatal "$OUT/logs/60-battery-info.logcat.txt"; then
  battery_result="FAIL_FATAL"
  fail=1
elif grep -Eqi "com\.android\.settings.*(Battery|Power|fuelgauge)|Battery|Power usage" \
    "$OUT/state/60-battery-info-activities.txt" \
    "$OUT/state/60-battery-info-windows.txt" \
    "$OUT/ui/60-battery-info.xml" 2>/dev/null; then
  battery_result="PASS_SETTINGS_SURFACE"
else
  battery_result="FAIL_SETTINGS_SURFACE"
  fail=1
fi
adb shell input keyevent KEYCODE_BACK || true
sleep 1

# IDs 18-20 Media transport: the debug-only probe hosts a real active Android
# MediaSession, then invokes the exact shipping MediaPlayPause/MediaNext/MediaPrev
# trackers. Require ACTION_DOWN delivery for all three transport keys.
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
  media_result="FAIL_FATAL"
  fail=1
elif [ "$media_supported" != "true" ]; then
  media_result="FAIL_SESSION_UNSUPPORTED"
  fail=1
elif [ -z "$media_play_pause" ] || [ -z "$media_next" ] || [ -z "$media_prev" ]; then
  media_result="FAIL_STATE_MISSING"
  fail=1
elif [ "$media_play_pause" -lt 1 ] || [ "$media_next" -lt 1 ] || [ "$media_prev" -lt 1 ]; then
  media_result="FAIL_DELIVERY"
  fail=1
else
  media_result="PASS_ACTIVE_MEDIA_SESSION_DELIVERY"
fi

# ID 10 Volume Toggle: on the clean API-36 emulator, invoke the exact shipping
# VolumeTracker without Notification Policy access. Require a real ringer-mode
# transition, no exception, and exact restoration of the original ringer mode.
adb shell am force-stop "$PKG" || true
adb logcat -c || true
run_probe volume_toggle || true
sleep 1
capture_log 62-volume-toggle
adb exec-out run-as "$PKG" cat shared_prefs/publication_remaining_probe.xml > "$OUT/state/volume-toggle-probe.xml" 2>/dev/null || true
volume_before="$(xml_int "$OUT/state/volume-toggle-probe.xml" volume_before)"
volume_after="$(xml_int "$OUT/state/volume-toggle-probe.xml" volume_after)"
volume_restored="$(xml_int "$OUT/state/volume-toggle-probe.xml" volume_restored)"
volume_policy_access="$(xml_bool "$OUT/state/volume-toggle-probe.xml" volume_policy_access)"
volume_threw="$(xml_bool "$OUT/state/volume-toggle-probe.xml" volume_threw)"
volume_restore_threw="$(xml_bool "$OUT/state/volume-toggle-probe.xml" volume_restore_threw)"
if app_fatal "$OUT/logs/62-volume-toggle.logcat.txt"; then
  volume_result="FAIL_FATAL"
  fail=1
elif [ -z "$volume_before" ] || [ -z "$volume_after" ] || [ -z "$volume_restored" ]; then
  volume_result="FAIL_STATE_MISSING"
  fail=1
elif [ "$volume_threw" != "false" ]; then
  volume_result="FAIL_TRACKER_EXCEPTION"
  fail=1
elif [ "$volume_after" = "$volume_before" ]; then
  volume_result="FAIL_NO_TRANSITION"
  fail=1
elif [ "$volume_restore_threw" != "false" ] || [ "$volume_restored" != "$volume_before" ]; then
  volume_result="FAIL_RESTORE"
  fail=1
else
  volume_result="PASS_TRANSITION_AND_RESTORE"
fi

printf '%s\n' \
  "battery_info=$battery_result" \
  "media_transport=$media_result" \
  "media_session_supported=$media_supported" \
  "media_play_pause_count=$media_play_pause" \
  "media_next_count=$media_next" \
  "media_prev_count=$media_prev" \
  "volume_toggle=$volume_result" \
  "volume_policy_access=$volume_policy_access" \
  "volume_before=$volume_before" \
  "volume_after=$volume_after" \
  "volume_restored=$volume_restored" \
  "volume_threw=$volume_threw" \
  > "$OUT/summary.txt"

cat "$OUT/summary.txt"
if [ "$fail" -ne 0 ]; then
  echo "Publication next-controls QA: RED" >&2
  exit 1
fi

echo "Publication next-controls QA: PASS"
