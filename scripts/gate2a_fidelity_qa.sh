#!/usr/bin/env bash
set -euo pipefail

OUT="${1:-fidelity-evidence}"
mkdir -p "$OUT/screens" "$OUT/ui" "$OUT/state" "$OUT/logs"

dump_ui_retry() {
  local name="$1"
  local remote="/sdcard/$name.xml"
  local local_xml="$OUT/ui/$name.xml"
  adb shell rm -f "$remote" >/dev/null 2>&1 || true
  rm -f "$local_xml"
  for attempt in 1 2 3 4 5; do
    adb shell uiautomator dump "$remote" >/dev/null 2>&1 || true
    if adb shell test -s "$remote" >/dev/null 2>&1; then
      adb pull "$remote" "$local_xml" >/dev/null 2>&1 || true
      if [ -s "$local_xml" ]; then
        return 0
      fi
    fi
    sleep 1
  done
  echo "Unable to capture UI hierarchy for $name" >&2
  return 1
}

capture() {
  local name="$1"
  dump_ui_retry "$name"
  adb exec-out screencap -p > "$OUT/screens/$name.png"
  adb shell dumpsys activity activities > "$OUT/state/$name.activities.txt"
  adb shell dumpsys window windows > "$OUT/state/$name.windows.txt"
  adb logcat -d > "$OUT/logs/$name.logcat.txt"
}

# F0/F1 read/status representative: Battery remains a real picker control and
# the running app can read a bounded battery percentage through production code.
grep -q 'BatteryTracker.class' src/com/painless/pc/TrackerManager.java
grep -Eq 'new int\[\].*15' src/com/painless/pc/picker/TogglePicker.java
adb shell am start -W -n com.painless.pc/com.painless.pc.tracker.Gate2aProbeActivity \
  --es probe battery > "$OUT/state/battery-probe.txt"
sleep 1
adb shell run-as com.painless.pc cat shared_prefs/gate2a_probe.xml > "$OUT/state/battery.xml"
grep -Eq 'name="battery_valid" value="true"|value="true" name="battery_valid"' "$OUT/state/battery.xml"

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
capture "01-fidelity-wifi-panel"
grep -Eq 'com\.android\.settings|SettingsPanelActivity' "$OUT/state/01-fidelity-wifi-panel.activities.txt"
grep -Eqi 'Wi.?Fi|Internet' "$OUT/ui/01-fidelity-wifi-panel.xml"
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
capture "02-fidelity-bluetooth-settings"
grep -Eq 'com\.android\.settings' "$OUT/state/02-fidelity-bluetooth-settings.activities.txt"
grep -qi 'Bluetooth' "$OUT/ui/02-fidelity-bluetooth-settings.xml"
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
F0/F1 Battery production status read: PASS
F1 Auto-rotate setting write+exact restore: PASS
F2 Wi-Fi supported system-panel fallback + rendered panel: PASS
F2 Bluetooth consent/settings fallback + rendered settings: PASS
F3 WiMAX retired from modern picker with historical ID preserved: PASS
EOF

adb shell dumpsys package com.painless.pc > "$OUT/state/package-final.txt"
adb shell pm list packages -f | grep 'com.painless.pc' > "$OUT/state/package-installed.txt"
find "$OUT/screens" -maxdepth 1 -type f -name '*.png' -printf '%f\n' | sort > "$OUT/screenshot-index.txt"
cat "$OUT/state/fidelity-summary.txt"
echo "Gate 2A fidelity QA complete"
