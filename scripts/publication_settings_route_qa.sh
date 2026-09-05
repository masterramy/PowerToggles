#!/usr/bin/env bash
set -euo pipefail

OUT="runtime-evidence/settings-routes"
mkdir -p "$OUT/screens" "$OUT/ui" "$OUT/state" "$OUT/logs"

capture_route() {
  local probe="$1"
  local slug="$2"

  adb logcat -c || true
  adb shell am force-stop com.painless.pc
  adb shell am start -W -n com.painless.pc/.tracker.Gate2aProbeActivity --es probe "$probe" \
    > "$OUT/state/${slug}-start.txt" 2>&1
  sleep 2

  adb shell dumpsys activity activities > "$OUT/state/${slug}-activities.txt"
  adb shell dumpsys window windows > "$OUT/state/${slug}-windows.txt"
  adb exec-out screencap -p > "$OUT/screens/${slug}.png"

  remote="/sdcard/${slug}.xml"
  adb shell rm -f "$remote" >/dev/null 2>&1 || true
  for attempt in 1 2 3 4 5; do
    adb shell uiautomator dump "$remote" >/dev/null 2>&1 || true
    if adb shell test -s "$remote" >/dev/null 2>&1; then
      adb pull "$remote" "$OUT/ui/${slug}.xml" >/dev/null 2>&1 || true
      [ -s "$OUT/ui/${slug}.xml" ] && break
    fi
    sleep 1
  done

  adb logcat -d > "$OUT/logs/${slug}.logcat.txt"

  if ! grep -Eq 'com\.android\.settings|com\.google\.android\.settings' \
      "$OUT/state/${slug}-activities.txt" "$OUT/state/${slug}-windows.txt"; then
    echo "${slug}: expected Android Settings surface was not foreground/reachable" >&2
    exit 1
  fi

  if grep -E "FATAL EXCEPTION|Process: com\.painless\.pc.*has died|ANR in com\.painless\.pc|am_crash.*com\.painless\.pc|am_anr.*com\.painless\.pc" \
      "$OUT/logs/${slug}.logcat.txt"; then
    echo "${slug}: fatal Power Toggles signal while launching user-mediated settings route" >&2
    exit 1
  fi

  adb shell input keyevent KEYCODE_BACK
  sleep 1
}

# Exercise the exact repaired/user-mediated F2 route implementations through the
# debug-only probe. These calls invoke the real shipping tracker classes; no
# release code or customer-visible QA hook is added.
capture_route hotspot_settings 23-hotspot-settings
capture_route mobile_data_settings 24-mobile-data-settings
capture_route location_settings 25-location-settings
capture_route airplane_settings 26-airplane-settings
capture_route mobile_network_settings 27-mobile-network-settings
capture_route usb_tether_settings 28-usb-tether-settings

printf '%s\n' \
  'hotspot_settings=PASS' \
  'mobile_data_settings=PASS' \
  'location_settings=PASS' \
  'airplane_settings=PASS' \
  'mobile_network_settings=PASS' \
  'usb_tether_settings=PASS' \
  > "$OUT/summary.txt"

echo "Publication user-mediated settings-route QA: PASS"
