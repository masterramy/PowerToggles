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
