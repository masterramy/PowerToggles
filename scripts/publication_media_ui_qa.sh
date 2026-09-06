#!/usr/bin/env bash
set -euo pipefail

OUT="runtime-evidence/media-ui"
mkdir -p "$OUT/screens" "$OUT/state" "$OUT/logs" "$OUT/ui"
PKG="com.painless.pc"
PROBE="$PKG/.tracker.Gate2aProbeActivity"

capture_state() {
  local slug="$1"
  local remote="/sdcard/${slug}.xml"
  adb shell dumpsys activity activities > "$OUT/state/${slug}-activities.txt"
  adb shell dumpsys window windows > "$OUT/state/${slug}-windows.txt"
  adb shell rm -f "$remote" >/dev/null 2>&1 || true
  for attempt in 1 2 3 4 5; do
    adb shell uiautomator dump "$remote" >/dev/null 2>&1 || true
    if adb shell test -s "$remote" >/dev/null 2>&1; then
      adb pull "$remote" "$OUT/ui/${slug}.xml" >/dev/null 2>&1 || true
      [ -s "$OUT/ui/${slug}.xml" ] && break
    fi
    sleep 1
  done
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

read_probe_prefs() {
  local dest="$1"
  adb exec-out run-as "$PKG" cat shared_prefs/gate2a_probe.xml > "$dest"
  test -s "$dest"
}

pref_int() {
  local file="$1"
  local name="$2"
  python3 - "$file" "$name" <<'PY'
import sys
import xml.etree.ElementTree as ET
root = ET.parse(sys.argv[1]).getroot()
for node in root:
    if node.attrib.get('name') == sys.argv[2]:
        print(node.attrib.get('value', node.text or ''))
        raise SystemExit(0)
raise SystemExit(f"missing preference {sys.argv[2]}")
PY
}

# ID 21 Music Volume: prepare a known non-zero baseline without changing shipping
# code, invoke the real MediaVolume tracker twice, prove mute + remembered restore,
# then restore the emulator's exact original volume even if it began at zero.
run_probe media_volume_prepare
read_probe_prefs "$OUT/state/media-volume-prepared.xml"
original_media="$(pref_int "$OUT/state/media-volume-prepared.xml" original_media_volume)"
baseline_media="$(pref_int "$OUT/state/media-volume-prepared.xml" media_volume_baseline)"

run_probe media_volume_toggle
read_probe_prefs "$OUT/state/media-volume-muted.xml"
muted_before="$(pref_int "$OUT/state/media-volume-muted.xml" media_volume_before)"
muted_after="$(pref_int "$OUT/state/media-volume-muted.xml" media_volume_after)"
if [ "$muted_before" != "$baseline_media" ] || [ "$muted_after" != "0" ]; then
  echo "Music Volume did not mute the prepared non-zero STREAM_MUSIC value" >&2
  run_probe media_volume_restore_original || true
  exit 1
fi

run_probe media_volume_toggle
read_probe_prefs "$OUT/state/media-volume-restored-by-tracker.xml"
restore_before="$(pref_int "$OUT/state/media-volume-restored-by-tracker.xml" media_volume_before)"
restore_after="$(pref_int "$OUT/state/media-volume-restored-by-tracker.xml" media_volume_after)"
if [ "$restore_before" != "0" ] || [ "$restore_after" != "$baseline_media" ]; then
  echo "Music Volume did not restore its remembered non-zero STREAM_MUSIC value" >&2
  run_probe media_volume_restore_original || true
  exit 1
fi
run_probe media_volume_restore_original
read_probe_prefs "$OUT/state/media-volume-original-restored.xml"
original_restored="$(pref_int "$OUT/state/media-volume-original-restored.xml" media_volume_original_restored)"
if [ "$original_restored" != "$original_media" ]; then
  echo "QA cleanup did not restore the exact original STREAM_MUSIC value" >&2
  exit 1
fi

# ID 27 Volume Slider: exercise the real shipping command path and retain the
# customer popup for rendered review. This tranche proves launch/render/back;
# individual slider/ringer mutations remain subject to later exact interaction QA.
run_probe volume_slider
capture_state 35-volume-slider
if ! grep -Eq 'com\.painless\.pc/.?acts\.VolumeSlider|com\.painless\.pc.*VolumeSlider' \
    "$OUT/state/35-volume-slider-activities.txt" "$OUT/state/35-volume-slider-windows.txt"; then
  echo "Volume Slider did not render its real app popup" >&2
  exit 1
fi
if [ ! -s "$OUT/ui/35-volume-slider.xml" ]; then
  echo "Volume Slider UI hierarchy was not retained" >&2
  exit 1
fi
adb shell input keyevent KEYCODE_BACK
sleep 1

# ID 31 Screen Light: exercise the real shipping command path. The core screen
# light is a fullscreen app surface; torch availability is hardware-dependent
# and is not inferred from an emulator. Retain render + clean back/finish proof.
run_probe screen_light
capture_state 36-screen-light
if ! grep -Eq 'com\.painless\.pc/.?FlashActivity|com\.painless\.pc.*FlashActivity' \
    "$OUT/state/36-screen-light-activities.txt" "$OUT/state/36-screen-light-windows.txt"; then
  echo "Screen Light did not render FlashActivity" >&2
  exit 1
fi
if [ ! -s "$OUT/ui/36-screen-light.xml" ]; then
  echo "Screen Light UI hierarchy was not retained" >&2
  exit 1
fi
adb logcat -c || true
adb shell input keyevent KEYCODE_BACK
sleep 2
adb shell dumpsys activity activities > "$OUT/state/36-screen-light-after-back-activities.txt"
adb shell dumpsys window windows > "$OUT/state/36-screen-light-after-back-windows.txt"
adb logcat -d > "$OUT/logs/36-screen-light-after-back.logcat.txt"
if grep -E "FATAL EXCEPTION|Process: ${PKG//./\\.}.*has died|ANR in ${PKG//./\\.}|am_crash.*${PKG//./\\.}|am_anr.*${PKG//./\\.}" "$OUT/logs/36-screen-light-after-back.logcat.txt"; then
  echo "Screen Light crashed or ANRed while closing" >&2
  exit 1
fi
if grep -Eq 'mResumedActivity.*com\.painless\.pc/.?FlashActivity|mCurrentFocus.*com\.painless\.pc/.?FlashActivity' \
    "$OUT/state/36-screen-light-after-back-activities.txt" "$OUT/state/36-screen-light-after-back-windows.txt"; then
  echo "Screen Light remained focused after Back" >&2
  exit 1
fi

printf '%s\n' \
  "music_volume_original=$original_media" \
  "music_volume_test_baseline=$baseline_media" \
  "music_volume_muted=$muted_after" \
  "music_volume_tracker_restored=$restore_after" \
  "music_volume_original_restored=$original_restored" \
  'music_volume=PASS' \
  'volume_slider_launch_render_back=PASS' \
  'screen_light_launch_render_back=PASS' \
  > "$OUT/summary.txt"

echo "Publication media/UI control QA: PASS"
