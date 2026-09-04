#!/usr/bin/env bash
set -euo pipefail

OUT="${1:-fidelity-evidence}"
mkdir -p "$OUT/screens" "$OUT/ui" "$OUT/state" "$OUT/logs"

capture() {
  local name="$1"
  adb exec-out screencap -p > "$OUT/screens/$name.png"
  adb shell uiautomator dump "/sdcard/$name.xml" >/dev/null
  adb pull "/sdcard/$name.xml" "$OUT/ui/$name.xml" >/dev/null
  adb shell dumpsys activity activities > "$OUT/state/$name.activities.txt"
  adb shell dumpsys window windows > "$OUT/state/$name.windows.txt"
  adb logcat -d > "$OUT/logs/$name.logcat.txt"
}

# F0/F1 visual/status: open the real toggle picker and prove Battery is present.
adb shell am force-stop com.painless.pc
adb shell am start -W -a android.appwidget.action.APPWIDGET_CONFIGURE \
  -n com.painless.pc/.cfg.WidgetConfigActivity --ei appWidgetId 2001 \
  > "$OUT/state/widget-config-start.txt" 2>&1
sleep 2
adb shell input tap 850 312
sleep 2

battery_found=0
for i in $(seq 1 8); do
  adb shell uiautomator dump "/sdcard/fidelity-picker-$i.xml" >/dev/null
  adb pull "/sdcard/fidelity-picker-$i.xml" "$OUT/ui/fidelity-picker-$i.xml" >/dev/null
  if grep -qi 'Battery' "$OUT/ui/fidelity-picker-$i.xml"; then
    capture "01-fidelity-battery-visible"
    battery_found=1
    break
  fi
  adb shell input swipe 540 2100 540 500 300
  sleep 1
done
if [ "$battery_found" -ne 1 ]; then
  echo "Battery control was not found in the rendered modern picker"
  exit 1
fi
grep -qi 'Battery' "$OUT/ui/01-fidelity-battery-visible.xml"
adb shell input keyevent KEYCODE_BACK || true
sleep 1

# F1 settings-write: invoke the real AutoRotateTracker through the debug-only
# probe, prove the Android system setting actually changes, then restore it.
adb shell appops set com.painless.pc WRITE_SETTINGS allow
adb shell am start -W -n com.painless.pc/com.painless.pc.tracker.Gate2aProbeActivity \
  --es probe autorotate_toggle > "$OUT/state/autorotate-toggle.txt"
sleep 1
adb shell run-as com.painless.pc cat shared_prefs/gate2a_probe.xml > "$OUT/state/autorotate.xml"
grep -Eq 'name="rotation_changed" value="true"|value="true" name="rotation_changed"' "$OUT/state/autorotate.xml"
adb shell am start -W -n com.painless.pc/com.painless.pc.tracker.Gate2aProbeActivity \
  --es probe autorotate_restore > "$OUT/state/autorotate-restore.txt"
sleep 1
adb shell run-as com.painless.pc cat shared_prefs/gate2a_probe.xml > "$OUT/state/autorotate-restored.xml"
grep -Eq 'name="rotation_restore_ok" value="true"|value="true" name="rotation_restore_ok"' "$OUT/state/autorotate-restored.xml"
adb shell appops set com.painless.pc WRITE_SETTINGS default || true

# F2 Wi-Fi: Android 10+ must hand off to the supported system Wi-Fi panel.
grep -q 'Settings.Panel.ACTION_WIFI' src/com/painless/pc/tracker/WifiStateTracker.java
adb logcat -c
adb shell am start -W -n com.painless.pc/com.painless.pc.tracker.Gate2aProbeActivity \
  --es probe wifi > "$OUT/state/wifi-launch.txt"
sleep 2
capture "02-fidelity-wifi-panel"
grep -Eq 'com\.android\.settings|SettingsPanelActivity' "$OUT/state/02-fidelity-wifi-panel.activities.txt"
grep -Eqi 'Wi.?Fi|Internet' "$OUT/ui/02-fidelity-wifi-panel.xml"
adb shell input keyevent KEYCODE_BACK || true
sleep 1

# F2 Bluetooth: Android 13+ must use user-mediated system UI rather than direct
# adapter enable/disable. Source proves consent intent; runtime proves settings fallback.
grep -q 'ACTION_REQUEST_ENABLE' src/com/painless/pc/tracker/BluetoothTracker.java
grep -q 'ACTION_BLUETOOTH_SETTINGS' src/com/painless/pc/tracker/BluetoothTracker.java
adb logcat -c
adb shell am start -W -n com.painless.pc/com.painless.pc.tracker.Gate2aProbeActivity \
  --es probe bluetooth_disable > "$OUT/state/bluetooth-launch.txt"
sleep 2
capture "03-fidelity-bluetooth-settings"
grep -Eq 'com\.android\.settings' "$OUT/state/03-fidelity-bluetooth-settings.activities.txt"
grep -qi 'Bluetooth' "$OUT/ui/03-fidelity-bluetooth-settings.xml"
adb shell input keyevent KEYCODE_BACK || true
sleep 1

# F3 retired control: preserve historical tracker ID 14 for old persisted
# definitions, but do not offer WiMAX in the modern picker.
test -f src/com/painless/pc/tracker/WiMaxTracker.java
grep -q 'WiMaxTracker.class' src/com/painless/pc/TrackerManager.java
if grep -Eq 'new int\[\][[:space:]]*\{[[:space:]]*14[[:space:]]*\}' src/com/painless/pc/picker/TogglePicker.java; then
  echo "Retired WiMAX tracker is still exposed in the modern picker"
  exit 1
fi

cat > "$OUT/state/fidelity-summary.txt" <<'EOF'
F0/F1 Battery rendered in modern picker: PASS
F1 Auto-rotate setting write+exact restore: PASS
F2 Wi-Fi supported system-panel fallback: PASS
F2 Bluetooth consent/settings fallback: PASS
F3 WiMAX retired from modern picker with historical ID preserved: PASS
EOF

adb shell dumpsys package com.painless.pc > "$OUT/state/package-final.txt"
adb shell pm list packages -f | grep 'com.painless.pc' > "$OUT/state/package-installed.txt"
find "$OUT/screens" -maxdepth 1 -type f -name '*.png' -printf '%f\n' | sort > "$OUT/screenshot-index.txt"
cat "$OUT/state/fidelity-summary.txt"
echo "Gate 2A fidelity QA complete"
