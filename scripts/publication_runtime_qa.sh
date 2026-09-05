#!/usr/bin/env bash
set -euo pipefail

# Publication-only transport hardening around the already-certified Gate 2A
# runtime probe. Retry ONLY adb's transport-style rc=255. Any ordinary
# shell/app/assertion failure is returned immediately and remains red.
REAL_ADB="$(command -v adb)"
if [ -z "$REAL_ADB" ]; then
  echo "adb not found" >&2
  exit 127
fi
export REAL_ADB

adb() {
  local rc=0
  local attempt
  for attempt in 1 2 3 4 5; do
    set +e
    "$REAL_ADB" "$@"
    rc=$?
    set -e
    if [ "$rc" -eq 0 ]; then
      return 0
    fi
    if [ "$rc" -ne 255 ]; then
      return "$rc"
    fi
    echo "Transient adb rc=255 for: adb $* (attempt $attempt/5)" >&2
    "$REAL_ADB" wait-for-device >/dev/null 2>&1 || true
    sleep 1
  done
  echo "adb remained unavailable after bounded rc=255 retries: adb $*" >&2
  return 255
}
export -f adb

# Derive the publication probe from the certified Gate 2A runtime probe rather
# than maintaining a divergent full copy. Only publication navigation changes
# are applied: the retired Quick Settings/Market surfaces are asserted absent,
# Stats is asserted free of legacy Help/Root status, and shifted row coordinates
# are used. All later notification/widget/fidelity assertions remain unchanged.
TMP_PROBE="$(mktemp)"
python3 - "$TMP_PROBE" <<'PY'
from pathlib import Path
import sys

src = Path("scripts/gate2a_runtime_qa.sh").read_text()
old_nav = '''open_row "01-homescreen" 422
open_row "02-notification" 548
open_row "03-folders" 674
open_row "04-quick-settings" 800
open_row "05-settings" 1010
open_row "06-stats-info" 1136'''
new_nav = '''open_row "01-homescreen" 422
open_row "02-notification" 548
open_row "03-folders" 674
launch_root > "$OUT/state/publication-nav-root.txt"
capture "04-publication-nav"
if grep -Eqi 'text="Quick settings"|text="Market review"' "$OUT/ui/04-publication-nav.xml"; then
  echo "Retired publication navigation surface is still visible"
  exit 1
fi
open_row "05-settings" 884
open_row "06-stats-info" 1010
if grep -Eqi 'text="Help"|text="Root Access"' "$OUT/ui/06-stats-info.xml"; then
  echo "Retired legacy Stats surface is still visible"
  exit 1
fi
grep -Eqi 'Device admin' "$OUT/ui/06-stats-info.xml"
grep -Eqi 'Battery polling' "$OUT/ui/06-stats-info.xml"'''
if old_nav not in src:
    raise SystemExit("Publication nav patch anchor missing from certified probe")
src = src.replace(old_nav, new_nav, 1)

old_settings = 'open_row "10-settings-before-toggle" 1010'
new_settings = 'open_row "10-settings-before-toggle" 884'
if old_settings not in src:
    raise SystemExit("Settings row patch anchor missing from certified probe")
src = src.replace(old_settings, new_settings, 1)

old_persist = '''adb shell input tap 540 1010
sleep 2
capture "12-settings-haptic-persisted"'''
new_persist = '''adb shell input tap 540 884
sleep 2
capture "12-settings-haptic-persisted"'''
if old_persist not in src:
    raise SystemExit("Settings persistence patch anchor missing from certified probe")
src = src.replace(old_persist, new_persist, 1)

Path(sys.argv[1]).write_text(src)
PY
chmod +x "$TMP_PROBE"
bash "$TMP_PROBE"
rm -f "$TMP_PROBE"

# Publication copy closure for the surviving tracker labels. The main picker
# viewport produced by the certified probe must show the three corrected labels
# that belong in its first visible section, and must not regress to their stale
# literal names. This is rendered/runtime evidence, not only a resource check.
TOP_PICKER_XML="runtime-evidence/ui/18-widget-add-toggle-picker.xml"
test -s "$TOP_PICKER_XML"
grep -Fq 'text="Mobile Data Settings"' "$TOP_PICKER_XML"
grep -Fq 'text="Mobile Network"' "$TOP_PICKER_XML"
grep -Fq 'text="Wi‑Fi"' "$TOP_PICKER_XML"
if grep -Fq 'text="GPRS (Mobile Data)"' "$TOP_PICKER_XML" \
  || grep -Fq 'text="Data Network Toggle"' "$TOP_PICKER_XML" \
  || grep -Fq 'text="Wifi"' "$TOP_PICKER_XML"; then
  echo "A stale publication tracker label remains in the rendered top picker"
  exit 1
fi

# Flashlight is farther down the categorized picker. Re-open the real widget
# picker and bounded-scroll until the corrected label is rendered, then retain
# a screenshot/UI hierarchy as exact-head evidence. Do not infer it from the
# resource file alone.
publication_dump_ui_retry() {
  local name="$1"
  local remote="/sdcard/${name}.xml"
  local local_xml="runtime-evidence/ui/${name}.xml"
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
  return 1
}

adb shell am force-stop com.painless.pc
adb shell am start -W -a android.appwidget.action.APPWIDGET_CONFIGURE \
  -n com.painless.pc/.cfg.WidgetConfigActivity --ei appWidgetId 1004 \
  > runtime-evidence/state/publication-label-audit-start.txt 2>&1
sleep 2
adb shell input tap 850 312
sleep 2

FLASHLIGHT_VISIBLE=false
for attempt in 1 2 3 4 5 6 7 8; do
  if publication_dump_ui_retry "21-publication-labels-lower-picker" \
    && grep -Fq 'text="Flashlight"' runtime-evidence/ui/21-publication-labels-lower-picker.xml; then
    FLASHLIGHT_VISIBLE=true
    break
  fi
  adb shell input swipe 540 1650 540 650 350
  sleep 1
done
if [ "$FLASHLIGHT_VISIBLE" != "true" ]; then
  echo "Corrected Flashlight label was not rendered after bounded picker scrolling"
  exit 1
fi
if grep -Fq 'text="Flash Light"' runtime-evidence/ui/21-publication-labels-lower-picker.xml; then
  echo "Stale Flash Light label remains in the rendered lower picker"
  exit 1
fi
adb exec-out screencap -p > runtime-evidence/screens/21-publication-labels-lower-picker.png
adb shell dumpsys activity activities > runtime-evidence/state/21-publication-labels-lower-picker.activities.txt
adb shell dumpsys window windows > runtime-evidence/state/21-publication-labels-lower-picker.windows.txt
adb logcat -d > runtime-evidence/logs/21-publication-labels-lower-picker.logcat.txt
if grep -E "FATAL EXCEPTION|Process: com\.painless\.pc.*has died|ANR in com\.painless\.pc|am_crash.*com\.painless\.pc|am_anr.*com\.painless\.pc" runtime-evidence/logs/21-publication-labels-lower-picker.logcat.txt; then
  echo "Fatal runtime signal during publication label audit"
  exit 1
fi

# Exhaustively inventory the real new-toggle picker. This is deliberately QA-only:
# stable historical tracker IDs remain untouched, while the customer-facing picker
# must expose every intended surviving control and none of the retired/root-era set.
adb shell am force-stop com.painless.pc
adb shell am start -W -a android.appwidget.action.APPWIDGET_CONFIGURE \
  -n com.painless.pc/.cfg.WidgetConfigActivity --ei appWidgetId 1005 \
  > runtime-evidence/state/publication-picker-inventory-start.txt 2>&1
sleep 2
adb shell input tap 850 312
sleep 2
mkdir -p runtime-evidence/picker-inventory
rm -f runtime-evidence/picker-inventory/*.xml runtime-evidence/picker-inventory/*.png

for page in $(seq -w 0 18); do
  name="22-publication-picker-${page}"
  if ! publication_dump_ui_retry "$name"; then
    echo "Unable to dump picker UI on inventory page $page"
    exit 1
  fi
  cp "runtime-evidence/ui/${name}.xml" "runtime-evidence/picker-inventory/${page}.xml"
  adb exec-out screencap -p > "runtime-evidence/picker-inventory/${page}.png"
  adb shell input swipe 540 1650 540 520 350
  sleep 1
 done

python3 - <<'PY'
from pathlib import Path
import html
import re
import sys
import xml.etree.ElementTree as ET

root = Path("runtime-evidence/picker-inventory")
seen = set()
page_text = []
for path in sorted(root.glob("*.xml")):
    values = []
    try:
        doc = ET.parse(path)
    except Exception as exc:
        raise SystemExit(f"Cannot parse {path}: {exc}")
    for node in doc.iter():
        text = html.unescape(node.attrib.get("text", "")).strip()
        if text:
            seen.add(text)
            values.append(text)
    page_text.append(f"{path.name}: " + " | ".join(values))

expected = [
    "Hotspot (Wifi)", "Mobile Data Settings", "Data Sync", "Wi‑Fi", "Flashlight",
    "GPS", "Bluetooth", "Brightness", "Airplane Mode", "Screen Auto Rotate",
    "Volume Toggle", "Mobile Network", "USB Tether", "Screen Always On (WakeLock)",
    "Battery Info", "Screen Timeout", "Auto Brightness", "Play/Pause Music",
    "Next Track", "Previous Track", "Music volume", "Bluetooth Discovery",
    "Brightness Slider", "NFC", "Screen Lock", "Bluetooth Tether", "Volume Slider",
    "Sync Now", "Screen Light", "Notification Widget", "Widget Settings",
    "Second Notification Row", "Rotation Lock", "Pulse notification light", "Home Shortcut",
]
retired = [
    "WiMax (4G)", "Shutdown", "Restart", "Shutdown Menu", "Increase System Font",
    "Decrease System Font", "adbWireless", "Receive internet calls (SIP)",
    "Internet calling (SIP)", "Recent Apps", "No Lock Screen", "Wifi Optimize",
    "Immersive mode",
]
missing = [x for x in expected if x not in seen]
forbidden = [x for x in retired if x in seen]
(root / "seen-text.txt").write_text("\n".join(sorted(seen)) + "\n", encoding="utf-8")
(root / "page-text.txt").write_text("\n".join(page_text) + "\n", encoding="utf-8")
summary = [
    f"expected_surviving={len(expected)}",
    f"seen_surviving={len(expected) - len(missing)}",
    f"retired_expected_absent={len(retired)}",
    f"retired_seen={len(forbidden)}",
    "missing=" + " | ".join(missing),
    "forbidden=" + " | ".join(forbidden),
]
(root / "summary.txt").write_text("\n".join(summary) + "\n", encoding="utf-8")
if missing or forbidden:
    print("Publication picker inventory failed", file=sys.stderr)
    print("\n".join(summary), file=sys.stderr)
    sys.exit(1)
print("Publication picker inventory: PASS")
print("\n".join(summary))
PY

adb shell dumpsys activity activities > runtime-evidence/state/22-publication-picker-inventory.activities.txt
adb shell dumpsys window windows > runtime-evidence/state/22-publication-picker-inventory.windows.txt
adb logcat -d > runtime-evidence/logs/22-publication-picker-inventory.logcat.txt
if grep -E "FATAL EXCEPTION|Process: com\.painless\.pc.*has died|ANR in com\.painless\.pc|am_crash.*com\.painless\.pc|am_anr.*com\.painless\.pc" runtime-evidence/logs/22-publication-picker-inventory.logcat.txt; then
  echo "Fatal runtime signal during publication picker inventory"
  exit 1
fi

find runtime-evidence/screens -maxdepth 1 -type f -name '*.png' -printf '%f\n' | sort > runtime-evidence/screenshot-index.txt
echo "Publication rendered label audit: PASS" > runtime-evidence/state/publication-label-audit-summary.txt
echo "Publication picker exposure audit: PASS" > runtime-evidence/state/publication-picker-inventory-summary.txt
