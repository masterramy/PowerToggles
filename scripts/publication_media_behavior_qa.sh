#!/usr/bin/env bash
set -euo pipefail

OUT="runtime-evidence/media-behavior"
mkdir -p "$OUT/screens" "$OUT/state" "$OUT/logs" "$OUT/ui"
PKG="com.painless.pc"
PROBE="$PKG/.tracker.Gate2aProbeActivity"

fatal_check() {
  local file="$1"
  if grep -E "FATAL EXCEPTION|Process: ${PKG//./\\.}.*has died|ANR in ${PKG//./\\.}|am_crash.*${PKG//./\\.}|am_anr.*${PKG//./\\.}" "$file"; then
    echo "Fatal Power Toggles signal in $file" >&2
    exit 1
  fi
}

dump_ui() {
  local slug="$1"
  local remote="/sdcard/${slug}.xml"
  adb shell rm -f "$remote" >/dev/null 2>&1 || true
  rm -f "$OUT/ui/${slug}.xml"
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

capture() {
  local slug="$1"
  dump_ui "$slug"
  adb exec-out screencap -p > "$OUT/screens/${slug}.png"
  adb shell dumpsys activity activities > "$OUT/state/${slug}-activities.txt"
  adb shell dumpsys window windows > "$OUT/state/${slug}-windows.txt"
  adb logcat -d > "$OUT/logs/${slug}.logcat.txt"
  fatal_check "$OUT/logs/${slug}.logcat.txt"
}

run_probe() {
  local name="$1"
  adb logcat -c || true
  adb shell am force-stop "$PKG"
  adb shell am start -W -n "$PROBE" --es probe "$name" >/dev/null
  sleep 2
}

media_volume() {
  adb shell dumpsys audio | python3 -c 'import re,sys; s=sys.stdin.read(); m=re.search(r"STREAM_MUSIC:[\s\S]*?streamVolume:\s*(\d+)",s,re.I); print(m.group(1) if m else (_ for _ in ()).throw(SystemExit("cannot parse STREAM_MUSIC volume from dumpsys audio")))'
}

set_media_volume() {
  adb shell cmd media_session volume --stream 3 --set "$1" >/dev/null
}

node_bounds() {
  local xml="$1"
  local rid="$2"
  local ordinal="$3"
  python3 - "$xml" "$rid" "$ordinal" <<'PY'
import re,sys,xml.etree.ElementTree as ET
root=ET.parse(sys.argv[1]).getroot()
nodes=[n for n in root.iter() if n.attrib.get('resource-id')==sys.argv[2]]
i=int(sys.argv[3])
if i >= len(nodes): raise SystemExit(f"missing node {sys.argv[2]} ordinal {i}; found {len(nodes)}")
m=re.fullmatch(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]',nodes[i].attrib.get('bounds',''))
if not m: raise SystemExit('bad bounds')
print(*map(int,m.groups()))
PY
}

read_widget_prefs() {
  local dest="$1"
  adb exec-out run-as "$PKG" cat shared_prefs/widget_preference.xml > "$dest"
  test -s "$dest"
}

pref_value() {
  local file="$1"
  local name="$2"
  local default="$3"
  python3 - "$file" "$name" "$default" <<'PY'
import sys,xml.etree.ElementTree as ET
root=ET.parse(sys.argv[1]).getroot()
for n in root:
    if n.attrib.get('name')==sys.argv[2]:
        print(n.attrib.get('value',n.text or ''))
        raise SystemExit(0)
print(sys.argv[3])
PY
}

# ID 27 Volume Slider: drive the real STREAM_MUSIC SeekBar (second enabled row
# with current default prefs), prove two distinct system-volume mutations, then
# restore the exact original STREAM_MUSIC value.
original_media="$(media_volume)"
run_probe volume_slider
capture 37-volume-slider-before
read x0 y0 x1 y1 <<<"$(node_bounds "$OUT/ui/37-volume-slider-before.xml" 'com.painless.pc:id/vs_seek' 1)"
y=$(( (y0 + y1) / 2 ))
left=$(( x0 + (x1 - x0) / 5 ))
right=$(( x0 + 4 * (x1 - x0) / 5 ))
adb shell input swipe "$right" "$y" "$left" "$y" 450
sleep 1
low_media="$(media_volume)"
capture 38-volume-slider-low
adb shell input swipe "$left" "$y" "$right" "$y" 450
sleep 1
high_media="$(media_volume)"
capture 39-volume-slider-high
if [ "$low_media" = "$high_media" ]; then
  set_media_volume "$original_media" || true
  echo "Volume Slider did not produce distinct STREAM_MUSIC values" >&2
  exit 1
fi
set_media_volume "$original_media"
restored_media="$(media_volume)"
if [ "$restored_media" != "$original_media" ]; then
  echo "Volume Slider QA cleanup failed to restore original STREAM_MUSIC" >&2
  exit 1
fi
adb shell input keyevent KEYCODE_BACK
sleep 1

# ID 31 Screen Light: use the real customer color dialog. Its alpha channel is
# the shipping brightness control. Save original persisted color, set 0x40 alpha
# through the real EditText + Set action, retain the visibly changed state, then
# restore the exact original ARGB value through the same customer UI.
run_probe screen_light
capture 40-screen-light-before
read_widget_prefs "$OUT/state/screen-light-prefs-before.xml"
original_color="$(pref_value "$OUT/state/screen-light-prefs-before.xml" screen_light_color -1)"
original_hex="$(python3 - "$original_color" <<'PY'
import sys
v=int(sys.argv[1])
if v < 0: v=(1<<32)+v
print(f'{v & 0xffffffff:08X}')
PY
)"
read bx0 by0 bx1 by1 <<<"$(node_bounds "$OUT/ui/40-screen-light-before.xml" 'com.painless.pc:id/button_color_1' 0)"
adb shell input tap $(( (bx0+bx1)/2 )) $(( (by0+by1)/2 ))
sleep 1
dump_ui 41-screen-light-color-dialog
read ex0 ey0 ex1 ey1 <<<"$(node_bounds "$OUT/ui/41-screen-light-color-dialog.xml" 'com.painless.pc:id/txt_color_input' 0)"
adb shell input tap $(( (ex0+ex1)/2 )) $(( (ey0+ey1)/2 ))
adb shell input keyevent KEYCODE_MOVE_END
for i in 1 2 3 4 5 6 7 8; do adb shell input keyevent KEYCODE_DEL; done
adb shell input text 40FFFFFF
sleep 1
read sx0 sy0 sx1 sy1 <<<"$(node_bounds "$OUT/ui/41-screen-light-color-dialog.xml" 'android:id/button1' 0)"
adb shell input tap $(( (sx0+sx1)/2 )) $(( (sy0+sy1)/2 ))
sleep 2
capture 42-screen-light-dimmed
read_widget_prefs "$OUT/state/screen-light-prefs-dimmed.xml"
dimmed_color="$(pref_value "$OUT/state/screen-light-prefs-dimmed.xml" screen_light_color -1)"
expected_dimmed="$(python3 - <<'PY'
print(int('40FFFFFF',16))
PY
)"
if [ "$dimmed_color" != "$expected_dimmed" ]; then
  echo "Screen Light real color/brightness dialog did not persist 0x40FFFFFF" >&2
  exit 1
fi
# Restore through the same UI path.
dump_ui 43-screen-light-restore-base
read bx0 by0 bx1 by1 <<<"$(node_bounds "$OUT/ui/43-screen-light-restore-base.xml" 'com.painless.pc:id/button_color_1' 0)"
adb shell input tap $(( (bx0+bx1)/2 )) $(( (by0+by1)/2 ))
sleep 1
dump_ui 44-screen-light-restore-dialog
read ex0 ey0 ex1 ey1 <<<"$(node_bounds "$OUT/ui/44-screen-light-restore-dialog.xml" 'com.painless.pc:id/txt_color_input' 0)"
adb shell input tap $(( (ex0+ex1)/2 )) $(( (ey0+ey1)/2 ))
adb shell input keyevent KEYCODE_MOVE_END
for i in 1 2 3 4 5 6 7 8; do adb shell input keyevent KEYCODE_DEL; done
adb shell input text "$original_hex"
sleep 1
read sx0 sy0 sx1 sy1 <<<"$(node_bounds "$OUT/ui/44-screen-light-restore-dialog.xml" 'android:id/button1' 0)"
adb shell input tap $(( (sx0+sx1)/2 )) $(( (sy0+sy1)/2 ))
sleep 2
read_widget_prefs "$OUT/state/screen-light-prefs-restored.xml"
restored_color="$(pref_value "$OUT/state/screen-light-prefs-restored.xml" screen_light_color -1)"
if [ "$restored_color" != "$original_color" ]; then
  echo "Screen Light QA cleanup failed to restore original color/brightness" >&2
  exit 1
fi
capture 45-screen-light-restored
adb shell input keyevent KEYCODE_BACK
sleep 2
adb logcat -d > "$OUT/logs/45-screen-light-after-back.logcat.txt"
fatal_check "$OUT/logs/45-screen-light-after-back.logcat.txt"

printf '%s\n' \
  "volume_slider_original_media=$original_media" \
  "volume_slider_low_media=$low_media" \
  "volume_slider_high_media=$high_media" \
  "volume_slider_restored_media=$restored_media" \
  'volume_slider_behavior=PASS' \
  "screen_light_original_color=$original_color" \
  "screen_light_dimmed_color=$dimmed_color" \
  "screen_light_restored_color=$restored_color" \
  'screen_light_color_brightness_behavior=PASS' \
  'screen_light_torch_hardware=DEFERRED_TO_PHYSICAL_DEVICE' \
  > "$OUT/summary.txt"

echo "Publication media behavior QA: PASS"
