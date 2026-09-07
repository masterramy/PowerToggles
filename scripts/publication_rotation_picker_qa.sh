#!/usr/bin/env bash
set -u

OUT="runtime-evidence/rotation-picker"
mkdir -p "$OUT/screens" "$OUT/state" "$OUT/logs" "$OUT/ui"
PKG="com.painless.pc"
PROBE="$PKG/.tracker.PublicationCompatProbeActivity"
fail=0
result="UNKNOWN"

run_probe() {
  local name="$1"
  adb shell am start -W -n "$PROBE" --es probe "$name" > "$OUT/state/${name}-start.txt" 2>&1
  sleep 1
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

app_fatal() {
  grep -E "FATAL EXCEPTION|Process: ${PKG//./\\.}|ANR in ${PKG//./\\.}|am_crash.*${PKG//./\\.}|am_anr.*${PKG//./\\.}" "$1" >/dev/null 2>&1
}

adb shell am force-stop "$PKG" || true
adb logcat -c || true
run_probe rotation_picker_prepare
run_probe rotation_picker_open
sleep 2
adb shell dumpsys activity activities > "$OUT/state/rotation-picker-activities.txt" 2>&1 || true
adb shell dumpsys window windows > "$OUT/state/rotation-picker-windows.txt" 2>&1 || true
adb logcat -d > "$OUT/logs/rotation-picker.logcat.txt"
dump_ui rotation-picker || true
adb exec-out screencap -p > "$OUT/screens/rotation-picker.png"

ui="$OUT/ui/rotation-picker.xml"
if app_fatal "$OUT/logs/rotation-picker.logcat.txt"; then
  result="FAIL_FATAL"
  fail=1
elif [ ! -s "$ui" ]; then
  result="FAIL_UI_MISSING"
  fail=1
elif ! grep -Eq 'text="Auto Rotate[^\"]*"' "$ui"; then
  result="FAIL_AUTO_CHOICE_MISSING"
  fail=1
elif ! grep -Eq 'text="Portrait[^\"]*"' "$ui"; then
  result="FAIL_PORTRAIT_CHOICE_MISSING"
  fail=1
elif ! grep -Eq 'text="Landscape[^\"]*"' "$ui"; then
  result="FAIL_LANDSCAPE_CHOICE_MISSING"
  fail=1
else
  result="PASS_RENDERED_CHOICES"
fi

adb shell input keyevent KEYCODE_BACK || true
sleep 1
adb logcat -d > "$OUT/logs/rotation-picker-after-back.logcat.txt"
if app_fatal "$OUT/logs/rotation-picker-after-back.logcat.txt"; then
  result="${result}+FAIL_BACK_FATAL"
  fail=1
fi
run_probe rotation_picker_restore

printf 'rotation_picker=%s\n' "$result" | tee "$OUT/summary.txt"
if [ "$fail" -ne 0 ]; then
  echo "Publication rotation picker QA: RED" >&2
  exit 1
fi

echo "Publication rotation picker QA: PASS"
