#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MANIFEST="$ROOT/AndroidManifest.xml"

python3 - "$MANIFEST" <<'PY'
import sys
import xml.etree.ElementTree as ET

manifest = sys.argv[1]
android = "{http://schemas.android.com/apk/res/android}"
expected = {
    ".picker.ThemePicker",
    ".cfg.IconThemeEditor",
    ".cfg.BatteryIconEditor",
    ".cfg.NinePatchEditor",
    ".cfg.ConfigGuide",
    ".acts.BrightnessActivity",
    "FlashActivity",
    "BootDialog",
    "RLPicker",
    ".acts.BrightnessSlider",
    ".acts.VolumeSlider",
    "ProxyActivity",
    "PermissionDialog",
}

root = ET.parse(manifest).getroot()
application = root.find("application")
if application is None:
    raise SystemExit("FAIL: application element missing")

seen = set()
for activity in application.findall("activity"):
    name = activity.get(android + "name")
    if name not in expected:
        continue
    seen.add(name)
    if activity.get(android + "exported") != "false":
        raise SystemExit(f"FAIL: internal activity is not explicitly non-exported: {name}")
    if activity.findall("intent-filter"):
        raise SystemExit(f"FAIL: internal activity unexpectedly gained an intent-filter: {name}")

missing = sorted(expected - seen)
if missing:
    raise SystemExit("FAIL: internal activity declaration missing: " + ", ".join(missing))

print("PASS: internal activities are explicitly non-exported and have no intent filters")
PY
