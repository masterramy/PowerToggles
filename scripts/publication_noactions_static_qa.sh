#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MANIFEST="$ROOT/AndroidManifest.xml"
WIDGET="$ROOT/src/com/painless/pc/PCWidgetActivity.java"
PLUGIN_RECEIVER="$ROOT/src/com/painless/pc/PluginUpdateReceiver.java"
PROVIDER="$ROOT/src/com/painless/pc/FileProvider.java"
ICON="$ROOT/src/com/painless/pc/picker/IconPicker.java"
HOME="$ROOT/src/com/painless/pc/nav/HomeFrag.java"
FOLDER="$ROOT/src/com/painless/pc/nav/FolderFrag.java"
FOLDER_READER="$ROOT/src/com/painless/pc/folder/FolderZipReader.java"
CONFIG="$ROOT/src/com/painless/pc/cfg/WidgetConfigActivity.java"
EDIT_CONFIG="$ROOT/src/com/painless/pc/cfg/EditWidgetConfigActivity.java"
FILE_PICKER="$ROOT/src/com/painless/pc/picker/FilePicker.java"
IMPORT_EXPORT="$ROOT/src/com/painless/pc/util/ImportExportActivity.java"
PROGRESS_TASK="$ROOT/src/com/painless/pc/util/ProgressTask.java"
BITMAP_IMPORT="$ROOT/src/com/painless/pc/util/BitmapImportUtils.java"
BACKUP="$ROOT/src/com/painless/pc/singleton/BackupUtil.java"
GLOBALS="$ROOT/src/com/painless/pc/singleton/Globals.java"
TASKER_SETUP="$ROOT/src/com/painless/pc/settings/TaskerToggleSetup.java"
TASKER_REFRESH="$ROOT/src/com/painless/pc/settings/TaskerRefresh.java"
THEME="$ROOT/src/com/painless/pc/picker/ThemePicker.java"
THEME_ENTRY="$ROOT/src/com/painless/pc/picker/theme/ThemeEntry.java"
THEME_ADAPTER="$ROOT/src/com/painless/pc/picker/theme/ThemeAdapter.java"
THEME_LOADER="$ROOT/src/com/painless/pc/picker/theme/ThemeLoader.java"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

# Legacy Buzz path-based IPC must be retired both from implicit discovery and
# from explicit-broadcast execution on the still-exported AppWidget receiver.
! grep -q 'com\.buzzpia\.aqua\.appwidget\.GET_VERSION' "$MANIFEST" || fail "Buzz GET_VERSION still exported"
! grep -q 'com\.buzzpia\.aqua\.appwidget\.GET_CONFIG_DATA' "$MANIFEST" || fail "Buzz GET_CONFIG_DATA still exported"
! grep -q 'com\.buzzpia\.aqua\.appwidget\.SET_CONFIG_DATA' "$MANIFEST" || fail "Buzz SET_CONFIG_DATA still exported"
grep -q 'startsWith(BUZZPIA_ACTION)' "$WIDGET" || fail "Explicit Buzz broadcasts are not denied"
grep -q 'Ignoring retired Buzzpia widget IPC action' "$WIDGET" || fail "Buzz deny-only retirement marker missing"
! grep -q 'FileOutputStream' "$WIDGET" || fail "Widget receiver still performs direct path output"
! grep -q 'BackupUtil\.importBackup' "$WIDGET" || fail "Widget receiver still performs path-based restore"

# The exported plugin receiver remains intentionally interoperable with the
# three supported Tasker/Locale/plugin actions, but unrelated explicit actions
# and malformed/unbounded mutation payloads must be rejected.
grep -q 'PLUGIN_STATE_CHANGED_INTENT' "$PLUGIN_RECEIVER" || fail "Plugin action allowlist missing"
grep -q '!TASK_COMPLETE_INTENT.equals(action)' "$PLUGIN_RECEIVER" || fail "Plugin receiver does not reject unrelated explicit actions"
grep -q '!"task".equals(data.getScheme())' "$PLUGIN_RECEIVER" || fail "Task completion data is not scheme-validated"
grep -q 'MAX_VAR_ID_LENGTH' "$PLUGIN_RECEIVER" || fail "Plugin var ID bound missing"
grep -q 'MAX_COUNT' "$PLUGIN_RECEIVER" || fail "Plugin count bound missing"

# Exported Locale/Tasker edit activities must only honor the documented edit
# action, and task-provider/extras enumeration must be bounded.
grep -q 'EDIT_SETTING_ACTION.equals(launchIntent.getAction())' "$TASKER_SETUP" || fail "Tasker setup accepts arbitrary launch action"
grep -q 'MAX_INPUT_CHARS' "$TASKER_SETUP" || fail "Tasker setup input bound missing"
grep -q 'EDIT_SETTING_ACTION.equals(launchIntent.getAction())' "$TASKER_REFRESH" || fail "Tasker refresh accepts arbitrary launch action"
grep -q 'MAX_TASKER_TASKS' "$GLOBALS" || fail "Tasker provider row bound missing"
grep -q 'MAX_TASKER_TASK_NAME_CHARS' "$GLOBALS" || fail "Tasker provider name bound missing"

# Folder/widget share remain grant-gated/read-only; config becomes same-UID/read-only;
# crop is exact-grant capability-gated and external write-only. Launcher /back is
# deliberately preserved as a separate read-only compatibility path.
grep -q 'FOLDER_SHARE_URI' "$PROVIDER" || fail "Folder share route missing"
grep -q 'WIDGET_SHARE_URI' "$PROVIDER" || fail "Widget share route missing"
grep -q 'Widget share is read-only' "$PROVIDER" || fail "Widget share write modes not denied"
grep -q 'enforceReadGrant(uri, "widget share")' "$PROVIDER" || fail "Widget share lacks exact temporary-grant gate"
grep -q 'enforceSameUid("configuration preview")' "$PROVIDER" || fail "Config route not same-UID gated"
grep -q 'Configuration preview is read-only' "$PROVIDER" || fail "Config write modes not denied"
grep -q 'External crop output is write-only' "$PROVIDER" || fail "Crop read/read-write modes not denied"
grep -q 'enforceReadGrant(uri, "crop output")' "$PROVIDER" || fail "Crop output lacks exact temporary-grant gate"
grep -q 'Widget background is read-only' "$PROVIDER" || fail "Launcher background route permits writes"

grep -q 'PICK_CROP_RESULT' "$ICON" || fail "Dedicated crop-result request path missing"
grep -q 'FileProvider.CROP_URI' "$ICON" || fail "Known app-owned crop output is not used"
grep -q 'setCropOutputExtra' "$ICON" || fail "Crop output grant helper missing"
! grep -q 'FLAG_GRANT_WRITE_URI_PERMISSION' "$ICON" || fail "Broad WRITE grant would propagate to source image"

# Home widget card must use SAF on modern Android and a grant-gated content URI
# for Share; legacy raw paths are allowed only in the explicit pre-KitKat fallback.
grep -q 'Intent.ACTION_CREATE_DOCUMENT' "$HOME" || fail "Home widget backup SAF create missing"
grep -q 'Intent.ACTION_OPEN_DOCUMENT' "$HOME" || fail "Home widget restore SAF open missing"
grep -q 'FileProvider.WIDGET_SHARE_URI' "$HOME" || fail "Home widget share content URI missing"
grep -q 'FLAG_GRANT_READ_URI_PERMISSION' "$HOME" || fail "Home widget share grant missing"
grep -q 'ClipData.newRawUri' "$HOME" || fail "Home widget share ClipData grant propagation missing"
! grep -q 'MODE_WORLD_READABLE' "$HOME" || fail "Home widget share still world-readable"
! grep -q 'Uri.fromFile' "$HOME" || fail "Home widget share still uses file URI"
grep -q 'Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT' "$HOME" || fail "Home modern/legacy storage boundary missing"
grep -q 'MAX_WIDGET_BACKUP_BYTES' "$HOME" || fail "Home restore compressed archive bound missing"
grep -q 'BackupUtil.copy(in, out, MAX_WIDGET_BACKUP_BYTES)' "$HOME" || fail "Home SAF restore copy is unbounded"

# Folder backup/restore/share must also use modern document/content-URI paths
# and bound both the compressed archive and expanded embedded databases.
grep -q 'Intent.ACTION_CREATE_DOCUMENT' "$FOLDER" || fail "Folder backup SAF create missing"
grep -q 'Intent.ACTION_OPEN_DOCUMENT' "$FOLDER" || fail "Folder restore SAF open missing"
grep -q 'FileProvider.FOLDER_SHARE_URI' "$FOLDER" || fail "Folder share content URI missing"
grep -q 'MAX_FOLDER_ARCHIVE_BYTES' "$FOLDER" || fail "Folder compressed archive bound missing"
grep -q 'MAX_FOLDER_NAMES_BYTES' "$FOLDER" || fail "Folder metadata bound missing"
grep -q 'MAX_FOLDER_COUNT' "$FOLDER" || fail "Folder count bound missing"
grep -q 'MAX_FOLDER_DB_BYTES' "$FOLDER_READER" || fail "Folder DB entry bound missing"
grep -q 'MAX_TOTAL_FOLDER_DB_BYTES' "$FOLDER_READER" || fail "Folder aggregate DB bound missing"
grep -q 'BackupUtil.copy(in, out, Math.min(MAX_FOLDER_DB_BYTES, remainingTotal))' "$FOLDER_READER" || fail "Expanded folder DB copy is unbounded"

# Shared document import staging and image decode must reject oversized data
# before allocating attacker-controlled bitmap dimensions. The shared copy
# primitive must also stop promptly when lifecycle cancellation interrupts it.
grep -q 'MAX_DOCUMENT_IMPORT_BYTES' "$IMPORT_EXPORT" || fail "Generic document import size bound missing"
grep -q 'BackupUtil.copy(in, out, MAX_DOCUMENT_IMPORT_BYTES)' "$IMPORT_EXPORT" || fail "Generic SAF document import copy is unbounded"
grep -q 'Thread.currentThread().isInterrupted()' "$BACKUP" || fail "Shared backup/import work ignores interruption"
grep -q 'InterruptedIOException' "$BACKUP" || fail "Shared bounded copy lacks cancellation exception"
grep -q 'MAX_DIMENSION' "$BITMAP_IMPORT" || fail "Bitmap dimension bound missing"
grep -q 'MAX_PIXELS' "$BITMAP_IMPORT" || fail "Bitmap pixel bound missing"
grep -q 'inJustDecodeBounds = true' "$BITMAP_IMPORT" || fail "Bitmap decode does not inspect bounds first"
grep -q 'decode(byte\[\] data)' "$BITMAP_IMPORT" || fail "Archive bitmap bounded decoder missing"
grep -q 'MAX_CONFIG_BYTES' "$BACKUP" || fail "Widget config ZIP entry bound missing"
grep -q 'MAX_IMAGE_BYTES' "$BACKUP" || fail "Widget image ZIP entry bound missing"
grep -q 'readZipEntry' "$BACKUP" || fail "Widget ZIP bounded entry reader missing"
grep -q 'copy(InputStream in, OutputStream out, long maxBytes)' "$BACKUP" || fail "Shared bounded copy primitive missing"

# Background task completion must be lifecycle-safe. Import/export tasks are
# retained by the Activity, cancelled on teardown, and cancelled tasks may not
# dismiss/publish into a destroyed owner Activity.
grep -q 'runningTasks' "$IMPORT_EXPORT" || fail "Import/export tasks are not lifecycle-owned"
grep -q 'task.cancel(true)' "$IMPORT_EXPORT" || fail "Import/export tasks are not cancelled on teardown"
grep -q 'protected void onDestroy()' "$IMPORT_EXPORT" || fail "Import/export lifecycle teardown hook missing"
grep -q 'canPublishResult' "$PROGRESS_TASK" || fail "ProgressTask has no owner lifecycle publication gate"
grep -q 'ownerActivity.isFinishing()' "$PROGRESS_TASK" || fail "ProgressTask does not reject finishing Activity"
grep -q 'ownerActivity.isDestroyed()' "$PROGRESS_TASK" || fail "ProgressTask does not reject destroyed Activity"
grep -q 'onCancelled(R result)' "$PROGRESS_TASK" || fail "ProgressTask cancellation cleanup missing"

# Existing-widget editing is internal-only. The exported framework config entry
# must verify that a supplied widget ID really belongs to this provider.
grep -q 'EditWidgetConfigActivity' "$EDIT_CONFIG" || fail "Internal widget edit activity missing"
grep -q 'android:name=".cfg.EditWidgetConfigActivity"' "$MANIFEST" || fail "Internal widget edit activity not declared"
grep 'android:name=".cfg.EditWidgetConfigActivity"' "$MANIFEST" | grep -q 'android:exported="false"' || fail "Internal widget edit activity is exported"
grep -q 'this instanceof EditWidgetConfigActivity' "$CONFIG" || fail "Exported config still accepts edit_widget directly"
grep -q 'isOwnedAppWidgetId' "$CONFIG" || fail "Exported widget configuration ownership check missing"
grep -q 'getAppWidgetInfo(widgetId)' "$CONFIG" || fail "Widget provider ownership is not framework-verified"
grep -q 'new Intent(context, EditWidgetConfigActivity.class)' "$GLOBALS" || fail "Existing-widget edits still target exported config activity"

# Widget theme export must use SAF on modern Android; the raw file picker is a
# pre-KitKat-only compatibility implementation and broad storage permission may
# therefore exist only through API 18.
grep -q 'Intent.ACTION_CREATE_DOCUMENT' "$CONFIG" || fail "Widget theme export SAF create missing"
grep -q 'DEFAULT_THEME_NAME' "$CONFIG" || fail "Widget theme export default document name missing"
grep -q 'SDK_INT >= Build.VERSION_CODES.KITKAT' "$FILE_PICKER" || fail "Legacy file picker is not modern-Android gated"
! grep -q 'requestPermissions' "$FILE_PICKER" || fail "Legacy file picker still requests runtime storage permission"
! grep -q 'Manifest.permission.WRITE_EXTERNAL_STORAGE' "$FILE_PICKER" || fail "Legacy file picker still contains modern storage permission flow"
grep -A2 'android:name="android.permission.WRITE_EXTERNAL_STORAGE"' "$MANIFEST" | grep -q 'android:maxSdkVersion="18"' || fail "WRITE_EXTERNAL_STORAGE is not capped to pre-SAF Android"

# Theme browsing is now local/system plus explicit SAF import. The retired
# remote Google Drive gallery must not reappear or make screen launch network-bound.
grep -q 'Intent.ACTION_OPEN_DOCUMENT' "$THEME" || fail "Theme SAF import missing"
grep -q 'Build.VERSION.SDK_INT < Build.VERSION_CODES.KITKAT' "$THEME" || fail "Legacy shared-root discovery is not pre-SAF bounded"
grep -q 'imported-themes' "$THEME" || fail "Imported themes are not persisted app-private"
grep -q 'validateThemeFile' "$THEME" || fail "Theme archive validation missing"
grep -q 'MAX_THEME_BYTES' "$THEME" || fail "Theme archive size bound missing"
grep -q 'MAX_LOCAL_THEMES' "$THEME" || fail "Theme inventory count bound missing"
grep -q 'mImportTask.cancel(true)' "$THEME" || fail "Theme import task is not cancelled on teardown"
grep -q 'Thread.currentThread().isInterrupted()' "$THEME" || fail "Theme import does not observe cancellation around promotion"
grep -q 'Unable to remove cancelled promoted theme' "$THEME" || fail "Cancelled theme promotion rollback missing"
! grep -q 'googledrive.com' "$THEME" || fail "Dead remote theme endpoint restored"
! grep -q 'BASE_URL' "$THEME" || fail "Remote theme catalog constant restored"
! grep -q 'URLConnection' "$THEME" || fail "Theme screen performs network catalog I/O"
! grep -q 'HttpResponseCache' "$THEME" || fail "Obsolete theme network cache restored"
! grep -q 'remoteUrl' "$THEME_ENTRY" || fail "Remote theme entry capability restored"
! grep -q 'RemoteThemeLoader' "$THEME_LOADER" || fail "Remote theme loader restored"
! grep -q 'URLConnection' "$THEME_LOADER" || fail "Theme loader performs network I/O"
grep -q 'MAX_THEME_IMAGE_BYTES' "$THEME_LOADER" || fail "Local theme image archive bound missing"
grep -q 'BitmapImportUtils.decode' "$THEME_LOADER" || fail "Local theme image decode is not bounds-first"
grep -q 'TYPE_FAILED' "$THEME_ADAPTER" || fail "Corrupt local theme terminal row missing"
grep -q 'shutdownNow' "$THEME_LOADER" || fail "Theme loader teardown is not interruptible"
grep -q 'mDestroyed' "$THEME_LOADER" || fail "Post-destroy delivery guard missing"

echo "PASS: no-Actions publication static hardening contract"
