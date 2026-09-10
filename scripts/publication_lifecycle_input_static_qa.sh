#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROGRESS="$ROOT/src/com/painless/pc/util/ProgressTask.java"
IMPORT_EXPORT="$ROOT/src/com/painless/pc/util/ImportExportActivity.java"
HOME="$ROOT/src/com/painless/pc/nav/HomeFrag.java"
BATTERY="$ROOT/src/com/painless/pc/cfg/BatteryIconEditor.java"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

# Background work must not retain completed tasks or publish into dead Activities.
grep -q 'protected void onFinished()' "$PROGRESS" || fail "ProgressTask completion-release hook missing"
grep -q 'onFinished();' "$PROGRESS" || fail "ProgressTask does not release after completion/cancellation"
grep -q 'runningTasks.remove(this)' "$IMPORT_EXPORT" || fail "Completed import/export tasks remain retained"
grep -q 'task.cancel(true)' "$IMPORT_EXPORT" || fail "Import/export teardown cancellation missing"

# Home restore may refresh its list, but must not manually re-enter Fragment lifecycle.
grep -q 'private void refreshWidgetList()' "$HOME" || fail "Home widget refresh helper missing"
grep -q 'refreshWidgetList();' "$HOME" || fail "Home restore does not refresh widget list"
RESTORE_BLOCK="$(sed -n '/requestCode == REQUEST_RESTORE/,/^[[:space:]]*}/p' "$HOME")"
! printf '%s\n' "$RESTORE_BLOCK" | grep -q 'onResume();' || fail "Home restore manually re-enters onResume"

# A battery image is cropped to a height-sized square after import. Reject portrait
# inputs before publication so createBitmap cannot request width beyond the bitmap.
grep -Fq 'image.getWidth() >= image.getHeight()' "$BATTERY" || fail "Portrait battery-image crash guard missing"
grep -q 'image.getHeight() > 0' "$BATTERY" || fail "Battery-image zero-height guard missing"

echo "PASS: lifecycle/import static contract"
