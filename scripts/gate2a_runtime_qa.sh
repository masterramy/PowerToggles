#!/usr/bin/env bash
set -euo pipefail

# Reproducible API 36 release-readiness runtime probe.
OUT="runtime-evidence"
mkdir -p "$OUT/screens" "$OUT/ui" "$OUT/state" "$OUT/logs"

fatal_scan() {
  local name="$1"
  adb logcat -d > "$OUT/logs/${name}.logcat.txt"
  if grep -E "FATAL EXCEPTION|Process: com\.painless\.pc.*has died|ANR in com\.painless\.pc" "$OUT/logs/${name}.logcat.txt"; then
    echo "Fatal runtime signal during ${name}"
    return 1
  fi
}

capture() {
  local name="$1"
  adb exec-out screencap -p > "$OUT/screens/${name}.png"
  adb shell uiautomator dump "/sdcard/${name}.xml" >/dev/null || true
  adb pull "/sdcard/${name}.xml" "$OUT/ui/${name}.xml" >/dev/null 2>&1 || true
  adb shell dumpsys activity activities > "$OUT/state/${name}.activities.txt"
  adb shell dumpsys window windows > "$OUT/state/${name}.windows.txt"
  adb shell dumpsys package com.painless.pc > "$OUT/state/${name}.package.txt"
  grep -q "com.painless.pc" "$OUT/state/${name}.activities.txt"
  fatal_scan "$name"
}

launch_root() {
  adb shell am force-stop com.painless.pc
  adb logcat -c
  adb shell am start -W -n com.painless.pc/.settings.LaunchActivity
  sleep 2
}

open_row() {
  local name="$1"
  local y="$2"
  launch_root > "$OUT/state/${name}.launch.txt"
  adb logcat -c
  adb shell input tap 540 "$y"
  sleep 2
  capture "$name"
}

# Root launch and screenshot.
launch_root | tee "$OUT/am-start.txt"
capture "00-launch"

# Main navigation rows on the fixed API-36 Pixel 6 test image.
open_row "01-homescreen" 422
open_row "02-notification" 548
open_row "03-folders" 674
open_row "04-quick-settings" 800
open_row "05-settings" 1010
open_row "06-stats-info" 1136

# Background/resume lifecycle check.
launch_root > "$OUT/state/lifecycle.launch.txt"
adb logcat -c
adb shell input keyevent KEYCODE_HOME
sleep 1
adb shell am start -W -n com.painless.pc/.settings.LaunchActivity > "$OUT/state/lifecycle.resume.txt"
sleep 2
capture "07-background-resume"

# Cold process restart check.
adb shell am force-stop com.painless.pc
sleep 1
adb logcat -c
adb shell am start -W -n com.painless.pc/.settings.LaunchActivity > "$OUT/state/cold-restart.txt"
sleep 2
capture "08-cold-restart"

# Basic configuration-activity survivability. A synthetic appWidgetId is used only
# to prove that the configuration entry point can be constructed on API 36 without
# immediately crashing; it is not claimed as an end-to-end launcher-hosted widget test.
adb shell am force-stop com.painless.pc
adb logcat -c
set +e
adb shell am start -W -a android.appwidget.action.APPWIDGET_CONFIGURE \
  -n com.painless.pc/.cfg.WidgetConfigActivity --ei appWidgetId 1001 \
  > "$OUT/state/widget-config-start.txt" 2>&1
WIDGET_START_RC=$?
set -e
sleep 2
adb exec-out screencap -p > "$OUT/screens/09-widget-config-entry.png" || true
adb shell uiautomator dump /sdcard/widget-config-entry.xml >/dev/null || true
adb pull /sdcard/widget-config-entry.xml "$OUT/ui/09-widget-config-entry.xml" >/dev/null 2>&1 || true
adb shell dumpsys activity activities > "$OUT/state/09-widget-config-entry.activities.txt"
adb logcat -d > "$OUT/logs/09-widget-config-entry.logcat.txt"
echo "$WIDGET_START_RC" > "$OUT/state/widget-config-start.rc"
if grep -E "FATAL EXCEPTION|Process: com\.painless\.pc.*has died|ANR in com\.painless\.pc" "$OUT/logs/09-widget-config-entry.logcat.txt"; then
  echo "Widget configuration entry point crashes on API 36"
  exit 1
fi

# Final package/install facts and permission state.
adb shell dumpsys package com.painless.pc > "$OUT/package-final.txt"
adb shell pm list packages -f | grep 'com.painless.pc' > "$OUT/package-installed.txt"
adb shell appops get com.painless.pc > "$OUT/appops.txt" 2>&1 || true

# Consolidated screenshot inventory for downstream visual QA.
find "$OUT/screens" -maxdepth 1 -type f -name '*.png' -printf '%f\n' | sort > "$OUT/screenshot-index.txt"

echo "Gate 2A runtime QA complete"
