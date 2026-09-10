#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROGRESS="$ROOT/src/com/painless/pc/util/ProgressTask.java"
IMPORT_EXPORT="$ROOT/src/com/painless/pc/util/ImportExportActivity.java"
HOME="$ROOT/src/com/painless/pc/nav/HomeFrag.java"
BATTERY="$ROOT/src/com/painless/pc/cfg/BatteryIconEditor.java"
BACKUP="$ROOT/src/com/painless/pc/singleton/BackupUtil.java"
FOLDER_READER="$ROOT/src/com/painless/pc/folder/FolderZipReader.java"
WIDGET_CONFIG="$ROOT/src/com/painless/pc/cfg/WidgetConfigActivity.java"
LAUNCH="$ROOT/src/com/painless/pc/settings/LaunchActivity.java"

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

# Widget editor imports are previews until Done. Embedded folder databases must be
# staged privately while the ZIP is open, committed only from Done, and rolled back
# on replacement import or Activity destruction. The legacy eager API remains for
# non-editor restore callers.
grep -q 'readSettingsStaged' "$BACKUP" || fail "Staged widget-import API missing"
grep -q 'folderReader.stageAll();' "$BACKUP" || fail "Embedded folder data is not staged before ZIP close"
grep -q 'public FolderZipReader folderImport' "$BACKUP" || fail "BackupData does not carry the staged folder transaction"
grep -q 'File.createTempFile("pt_folder_restore_"' "$FOLDER_READER" || fail "Folder import does not stage into private cache"
grep -q 'Folder destination changed while import was pending' "$FOLDER_READER" || fail "Folder commit collision guard missing"
grep -q 'publishedFiles.add(targetFile)' "$FOLDER_READER" || fail "Partial destination is not registered for rollback before copy"
grep -q 'mPendingFolderImport.commitAll();' "$WIDGET_CONFIG" || fail "Widget Done does not commit staged folder data"
grep -q 'rollbackPendingFolderImport();' "$WIDGET_CONFIG" || fail "Widget editor does not roll back staged folder data"
grep -q 'BackupUtil.readSettingsStaged' "$WIDGET_CONFIG" || fail "Widget editor still uses eager folder publication"

# LaunchActivity is exported, so PreferenceActivity.EXTRA_SHOW_FRAGMENT is an
# external ingress. It must accept only the complete, source-proven settings
# navigation set and must never regress to blanket Fragment acceptance.
! grep -A3 'isValidFragment(String fragmentName)' "$LAUNCH" | grep -Fq 'return true;' || fail "Exported settings Activity blanket-accepts fragment injection"
for fragment in HomeFrag NotifyFrag FolderFrag SettingsFrag InfoFrag TogglePrefFrag TCacheFrag CFolderFrag; do
  grep -Fq "${fragment}.class.getName().equals(fragmentName)" "$LAUNCH" || fail "LaunchActivity allowlist missing ${fragment}"
done
! grep -Fq 'AbsListFrag.class.getName().equals(fragmentName)' "$LAUNCH" || fail "Non-navigation base Fragment unexpectedly exposed"

echo "PASS: lifecycle/import static contract"
