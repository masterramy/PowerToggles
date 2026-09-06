#!/usr/bin/env bash
set -euo pipefail

OUT="runtime-evidence/write-settings"
mkdir -p "$OUT/screens" "$OUT/state" "$OUT/logs"
PKG="com.painless.pc"
PROBE="$PKG/.tracker.Gate2aProbeActivity"

set_write_settings_mode() {
  local mode="$1"
  adb shell appops set "$PKG" WRITE_SETTINGS "$mode" >/dev/null
  adb shell appops get "$PKG" WRITE_SETTINGS > "$OUT/state/appops-${mode}.txt" 2>&1 || true
}

capture_state() {
  local slug="$1"
  adb shell dumpsys activity activities > "$OUT/state/${slug}-activities.txt"
  adb shell dumpsys window windows > "$OUT/state/${slug}-windows.txt"
  adb exec-out screencap -p > "$OUT/screens/${slug}.png"
  adb logcat -d > "$OUT/logs/${slug}.logcat.txt"
  if grep -E "FATAL EXCEPTION|Process: ${PKG//./\\.}.*has died|ANR in ${PKG//./\\.}|am_crash.*${PKG//./\\.}|am_anr.*${PKG//./\\.}" "$OUT/logs/${slug}.logcat.txt"; then
    echo "$slug: fatal Power Toggles signal" >&2
    exit 1
  fi
}

run_probe() {
  local name="$1"
  adb logcat -c || true
  adb shell am force-stop "$PKG"
  adb shell am start -W -n "$PROBE" --es probe "$name" >/dev/null
  sleep 2
}

# Denied/revoked WRITE_SETTINGS must not silently mutate system state and must
# expose the app's user-facing permission explanation instead.
set_write_settings_mode deny
brightness_before="$(adb shell settings get system screen_brightness | tr -d '\r')"
run_probe brightness_toggle
brightness_denied_after="$(adb shell settings get system screen_brightness | tr -d '\r')"
capture_state 31-write-settings-denied
if [ "$brightness_before" != "$brightness_denied_after" ]; then
  echo "Brightness changed while WRITE_SETTINGS was denied" >&2
  exit 1
fi
if ! grep -Eq 'com\.painless\.pc/.?PermissionDialog|com\.painless\.pc.*PermissionDialog' \
    "$OUT/state/31-write-settings-denied-activities.txt" "$OUT/state/31-write-settings-denied-windows.txt"; then
  echo "WRITE_SETTINGS denial did not expose PermissionDialog" >&2
  exit 1
fi
adb shell input keyevent KEYCODE_BACK
sleep 1

# Grant the legitimate special app-op, exercise real shipping implementations,
# prove actual system state changes, and restore every mutated emulator setting.
set_write_settings_mode allow

brightness_before="$(adb shell settings get system screen_brightness | tr -d '\r')"
brightness_mode_before="$(adb shell settings get system screen_brightness_mode | tr -d '\r')"
run_probe brightness_toggle
brightness_after="$(adb shell settings get system screen_brightness | tr -d '\r')"
brightness_mode_after="$(adb shell settings get system screen_brightness_mode | tr -d '\r')"
if [ "$brightness_before" = "$brightness_after" ] && [ "$brightness_mode_before" = "$brightness_mode_after" ]; then
  echo "Brightness tracker made no observable change with WRITE_SETTINGS granted" >&2
  exit 1
fi
adb shell settings put system screen_brightness "$brightness_before"
adb shell settings put system screen_brightness_mode "$brightness_mode_before"

# Timeout cycles among configured 30/60/300 second values.
timeout_before="$(adb shell settings get system screen_off_timeout | tr -d '\r')"
run_probe timeout_toggle
timeout_after="$(adb shell settings get system screen_off_timeout | tr -d '\r')"
if [ "$timeout_before" = "$timeout_after" ]; then
  echo "Screen Timeout tracker made no observable change with WRITE_SETTINGS granted" >&2
  exit 1
fi
case "$timeout_after" in
  30000|60000|300000) ;;
  *) echo "Unexpected Screen Timeout value: $timeout_after" >&2; exit 1 ;;
esac
adb shell settings put system screen_off_timeout "$timeout_before"

# Auto Brightness must flip manual/automatic and be restorable.
auto_before="$(adb shell settings get system screen_brightness_mode | tr -d '\r')"
run_probe auto_brightness_toggle
auto_after="$(adb shell settings get system screen_brightness_mode | tr -d '\r')"
if [ "$auto_before" = "$auto_after" ]; then
  echo "Auto Brightness tracker did not toggle brightness mode" >&2
  exit 1
fi
adb shell settings put system screen_brightness_mode "$auto_before"

# Brightness Slider is a customer-visible panel gated by the same legitimate
# WRITE_SETTINGS access. Retain its rendered state for sequential review.
run_probe brightness_slider
capture_state 32-brightness-slider
if ! grep -Eq 'com\.painless\.pc/.?acts\.BrightnessSlider|com\.painless\.pc.*BrightnessSlider' \
    "$OUT/state/32-brightness-slider-activities.txt" "$OUT/state/32-brightness-slider-windows.txt"; then
  echo "Brightness Slider did not render its real app panel" >&2
  exit 1
fi
adb shell input keyevent KEYCODE_BACK
sleep 1

# Revoke again to prove the special access is not sticky or bypassed.
set_write_settings_mode deny
slider_before="$(adb shell settings get system screen_brightness | tr -d '\r')"
run_probe brightness_slider
slider_denied_after="$(adb shell settings get system screen_brightness | tr -d '\r')"
capture_state 33-write-settings-revoked
if [ "$slider_before" != "$slider_denied_after" ]; then
  echo "Brightness changed after WRITE_SETTINGS revocation" >&2
  exit 1
fi
if ! grep -Eq 'com\.painless\.pc/.?PermissionDialog|com\.painless\.pc.*PermissionDialog' \
    "$OUT/state/33-write-settings-revoked-activities.txt" "$OUT/state/33-write-settings-revoked-windows.txt"; then
  echo "WRITE_SETTINGS revocation was bypassed" >&2
  exit 1
fi
adb shell input keyevent KEYCODE_BACK || true

printf '%s\n' \
  "brightness_before=$brightness_before" \
  "brightness_after=$brightness_after" \
  "brightness_mode_before=$brightness_mode_before" \
  "brightness_mode_after=$brightness_mode_after" \
  "timeout_before=$timeout_before" \
  "timeout_after=$timeout_after" \
  "auto_brightness_before=$auto_before" \
  "auto_brightness_after=$auto_after" \
  'brightness=PASS' \
  'screen_timeout=PASS' \
  'auto_brightness=PASS' \
  'brightness_slider=PASS' \
  'write_settings_denial_revoke=PASS' \
  > "$OUT/summary.txt"

echo "Publication WRITE_SETTINGS control QA: PASS"
