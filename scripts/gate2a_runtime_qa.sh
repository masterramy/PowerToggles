#!/usr/bin/env bash
set -euo pipefail

# Reproducible API 36 release-readiness runtime probe.
OUT="runtime-evidence"
mkdir -p "$OUT/screens" "$OUT/ui" "$OUT/state" "$OUT/logs"

fatal_scan() {
  local name="$1"
  adb logcat -d > "$OUT/logs/${name}.logcat.txt"
  if grep -E "FATAL EXCEPTION|Process: com\.painless\.pc.*has died|ANR in com\.painless\.pc|am_crash.*com\.painless\.pc|am_anr.*com\.painless\.pc" "$OUT/logs/${name}.logcat.txt"; then
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

capture_external() {
  local name="$1"
  adb exec-out screencap -p > "$OUT/screens/${name}.png"
  adb shell uiautomator dump "/sdcard/${name}.xml" >/dev/null || true
  adb pull "/sdcard/${name}.xml" "$OUT/ui/${name}.xml" >/dev/null 2>&1 || true
  adb shell dumpsys activity activities > "$OUT/state/${name}.activities.txt"
  adb shell dumpsys window windows > "$OUT/state/${name}.windows.txt"
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

notification_switch_state() {
  local name="$1"
  adb shell uiautomator dump "/sdcard/${name}.xml" >/dev/null
  adb pull "/sdcard/${name}.xml" "$OUT/state/${name}.xml" >/dev/null
  if grep -Eq 'resource-id="com\.painless\.pc:id/my_switch"[^>]*checked="true"' "$OUT/state/${name}.xml"; then
    printf 'true\n'
  elif grep -Eq 'resource-id="com\.painless\.pc:id/my_switch"[^>]*checked="false"' "$OUT/state/${name}.xml"; then
    printf 'false\n'
  else
    echo "Unable to determine notification switch state" >&2
    return 1
  fi
}

set_notification_switch() {
  local desired="$1"
  local name="$2"
  local current
  current="$(notification_switch_state "${name}-before")"
  echo "notification switch before ${name}: ${current}" > "$OUT/state/${name}.txt"
  if [ "$current" != "$desired" ]; then
    adb shell input tap 998 202
    sleep 2
  fi
  current="$(notification_switch_state "${name}-after")"
  echo "notification switch after ${name}: ${current}" >> "$OUT/state/${name}.txt"
  if [ "$current" != "$desired" ]; then
    echo "Notification switch failed to reach desired state ${desired}"
    return 1
  fi
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
capture "09-widget-config-entry"
echo "$WIDGET_START_RC" > "$OUT/state/widget-config-start.rc"

# Exercise a real mutable preference and prove it survives a process restart.
open_row "10-settings-before-toggle" 1010
adb shell run-as com.painless.pc cat shared_prefs/widget_preference.xml > "$OUT/state/prefs-before-haptic.xml" 2>/dev/null || true
adb logcat -c
adb shell input tap 540 506
sleep 1
capture "11-settings-haptic-on"
adb shell run-as com.painless.pc cat shared_prefs/widget_preference.xml > "$OUT/state/prefs-haptic-on.xml"
grep -Eq 'name="heptic_feedback" value="true"|value="true" name="heptic_feedback"' "$OUT/state/prefs-haptic-on.xml"

adb shell am force-stop com.painless.pc
adb shell am start -W -n com.painless.pc/.settings.LaunchActivity > "$OUT/state/settings-persistence-relaunch.txt"
sleep 1
adb shell input tap 540 1010
sleep 2
capture "12-settings-haptic-persisted"
grep -q 'text="Haptic feedback"' "$OUT/ui/12-settings-haptic-persisted.xml"
grep -Eq 'text="Haptic feedback"[^>]*checked="true"|checked="true"[^>]*text="Haptic feedback"' "$OUT/ui/12-settings-haptic-persisted.xml"

# Restore the changed preference so the remainder of the suite is clean.
adb shell input tap 540 506
sleep 1
adb shell run-as com.painless.pc cat shared_prefs/widget_preference.xml > "$OUT/state/prefs-haptic-restored.xml"
if grep -Eq 'name="heptic_feedback" value="true"|value="true" name="heptic_feedback"' "$OUT/state/prefs-haptic-restored.xml"; then
  echo "Haptic preference failed to restore"
  exit 1
fi

# Notification-widget functional path on targetSdk 36.
adb shell pm revoke com.painless.pc android.permission.POST_NOTIFICATIONS >/dev/null 2>&1 || true
launch_root > "$OUT/state/notification-permission-root.txt"
adb shell input tap 540 548
sleep 2
adb logcat -c
set_notification_switch "false" "notification-prepermission-reset"
adb shell input tap 998 202
sleep 1
capture "13-notification-permission-prompt"
grep -q 'package="com.google.android.permissioncontroller"' "$OUT/ui/13-notification-permission-prompt.xml"
grep -q 'Allow Power Toggles to send you notifications?' "$OUT/ui/13-notification-permission-prompt.xml"
grep -q 'text="Allow"' "$OUT/ui/13-notification-permission-prompt.xml"

adb shell pm grant com.painless.pc android.permission.POST_NOTIFICATIONS
adb shell input keyevent KEYCODE_BACK || true
sleep 1
launch_root > "$OUT/state/notification-enabled-root.txt"
adb shell input tap 540 548
sleep 2
adb logcat -c
set_notification_switch "true" "notification-enable"
sleep 2
capture "14-notification-enabled"
grep -Eq 'resource-id="com\.painless\.pc:id/my_switch"[^>]*checked="true"' "$OUT/ui/14-notification-enabled.xml"
adb shell dumpsys notification --noredact > "$OUT/state/notification-enabled.dumpsys.txt"
grep -Eq 'NotificationRecord\(.*pkg=com\.painless\.pc|pkg=com\.painless\.pc.*id=1' "$OUT/state/notification-enabled.dumpsys.txt"
grep -q 'power_toggles_controls' "$OUT/state/notification-enabled.dumpsys.txt"

adb shell cmd statusbar expand-notifications >/dev/null 2>&1 || true
sleep 2
capture "15-notification-shade"
grep -q 'package="com.android.systemui"' "$OUT/ui/15-notification-shade.xml"
adb shell cmd statusbar collapse >/dev/null 2>&1 || true
sleep 1

set_notification_switch "false" "notification-disable"
sleep 2
capture "16-notification-disabled"
grep -Eq 'resource-id="com\.painless\.pc:id/my_switch"[^>]*checked="false"' "$OUT/ui/16-notification-disabled.xml"
adb shell dumpsys notification --noredact > "$OUT/state/notification-disabled.dumpsys.txt"
if grep -E 'NotificationRecord\(.*pkg=com\.painless\.pc|pkg=com\.painless\.pc.*id=1' "$OUT/state/notification-disabled.dumpsys.txt"; then
  echo "Power Toggles notification remained active after disabling"
  exit 1
fi
grep -q 'power_toggles_controls' "$OUT/state/notification-disabled.dumpsys.txt"

# Widget configurator and picker evidence.
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
sleep 2
adb logcat -c
adb shell input tap 850 312
sleep 2
capture "18-widget-add-toggle-picker"
grep -Eqi 'Battery|Wi.?Fi|Bluetooth|toggle|shortcut' "$OUT/ui/18-widget-add-toggle-picker.xml"
adb shell input keyevent KEYCODE_BACK || true

# Representative fidelity slice ------------------------------------------------
# F0/F1 visual/status: the picker exposes a real Battery status control.
grep -qi 'Battery' "$OUT/ui/18-widget-add-toggle-picker.xml"

# F1 settings-write: grant the Android special-access app-op in the controlled
# emulator, invoke the real AutoRotateTracker through the debug-only probe, prove
# the system setting actually changes, and restore the exact original value.
adb shell appops set com.painless.pc WRITE_SETTINGS allow
adb shell am start -W -n com.painless.pc/com.painless.pc.tracker.Gate2aProbeActivity \
  --es probe autorotate_toggle > "$OUT/state/fidelity-autorotate-toggle.txt"
sleep 1
adb shell run-as com.painless.pc cat shared_prefs/gate2a_probe.xml > "$OUT/state/fidelity-autorotate.xml"
grep -Eq 'name="rotation_changed" value="true"|value="true" name="rotation_changed"' "$OUT/state/fidelity-autorotate.xml"
adb shell am start -W -n com.painless.pc/com.painless.pc.tracker.Gate2aProbeActivity \
  --es probe autorotate_restore > "$OUT/state/fidelity-autorotate-restore.txt"
sleep 1
adb shell run-as com.painless.pc cat shared_prefs/gate2a_probe.xml > "$OUT/state/fidelity-autorotate-restored.xml"
grep -Eq 'name="rotation_restore_ok" value="true"|value="true" name="rotation_restore_ok"' "$OUT/state/fidelity-autorotate-restored.xml"
adb shell appops set com.painless.pc WRITE_SETTINGS default || true

# F2 Wi-Fi: on Android 10+ the restored tracker must hand off to the supported
# system Wi-Fi panel rather than pretending WifiManager.setWifiEnabled succeeded.
adb logcat -c
adb shell am start -W -n com.painless.pc/com.painless.pc.tracker.Gate2aProbeActivity \
  --es probe wifi > "$OUT/state/fidelity-wifi-launch.txt"
sleep 2
capture_external "19-fidelity-wifi-panel"
grep -Eq 'com\.android\.settings|SettingsPanelActivity' "$OUT/state/19-fidelity-wifi-panel.activities.txt"
grep -Eqi 'Wi.?Fi|Internet' "$OUT/ui/19-fidelity-wifi-panel.xml"
adb shell input keyevent KEYCODE_BACK || true
sleep 1

# F2 Bluetooth: direct enable/disable is forbidden for targetSdk 33+; source must
# use the consent intent for enable and runtime must provide a system-settings
# fallback for disable without crashing.
grep -q 'ACTION_REQUEST_ENABLE' src/com/painless/pc/tracker/BluetoothTracker.java
adb logcat -c
adb shell am start -W -n com.painless.pc/com.painless.pc.tracker.Gate2aProbeActivity \
  --es probe bluetooth_disable > "$OUT/state/fidelity-bluetooth-launch.txt"
sleep 2
capture_external "20-fidelity-bluetooth-settings"
grep -Eq 'com\.android\.settings' "$OUT/state/20-fidelity-bluetooth-settings.activities.txt"
grep -qi 'Bluetooth' "$OUT/ui/20-fidelity-bluetooth-settings.xml"
adb shell input keyevent KEYCODE_BACK || true
sleep 1

# F3 retired control: historical WiMAX implementation remains in source for
# provenance, but the modern picker intentionally does not offer tracker 14.
test -f src/com/painless/pc/tracker/WiMaxTracker.java
if grep -Eq 'new int\[\][[:space:]]*\{[[:space:]]*14[[:space:]]*\}' src/com/painless/pc/picker/TogglePicker.java; then
  echo "Retired WiMAX tracker is still exposed in the modern picker"
  exit 1
fi
echo "F0/F1 Battery status: PASS" > "$OUT/state/fidelity-summary.txt"
echo "F1 Auto-rotate setting write+restore: PASS" >> "$OUT/state/fidelity-summary.txt"
echo "F2 Wi-Fi supported system-panel fallback: PASS" >> "$OUT/state/fidelity-summary.txt"
echo "F2 Bluetooth consent/settings fallback: PASS" >> "$OUT/state/fidelity-summary.txt"
echo "F3 WiMAX retired from picker: PASS" >> "$OUT/state/fidelity-summary.txt"

# Final package/install facts and permission state.
adb shell dumpsys package com.painless.pc > "$OUT/package-final.txt"
adb shell pm list packages -f | grep 'com.painless.pc' > "$OUT/package-installed.txt"
adb shell appops get com.painless.pc > "$OUT/appops.txt" 2>&1 || true
adb shell dumpsys notification --noredact > "$OUT/notification-final.txt"

find "$OUT/screens" -maxdepth 1 -type f -name '*.png' -printf '%f\n' | sort > "$OUT/screenshot-index.txt"

echo "Gate 2A runtime QA complete"
