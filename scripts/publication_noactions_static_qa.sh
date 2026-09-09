#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MANIFEST="$ROOT/AndroidManifest.xml"
WIDGET="$ROOT/src/com/painless/pc/PCWidgetActivity.java"
PLUGIN_RECEIVER="$ROOT/src/com/painless/pc/PluginUpdateReceiver.java"
PROVIDER="$ROOT/src/com/painless/pc/FileProvider.java"
ICON="$ROOT/src/com/painless/pc/picker/IconPicker.java"
HOME="$ROOT/src/com/painless/pc/nav/HomeFrag.java"
THEME="$ROOT/src/com/painless/pc/picker/ThemePicker.java"
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
grep -q 'File.createTempFile("power_toggles_widget_restore_"' "$HOME" || fail "Home SAF restore private staging missing"

# Modern ThemePicker must provide scoped local import and explicit degraded
# states instead of target-36 shared-root discovery/permanent spinners.
grep -q 'Intent.ACTION_OPEN_DOCUMENT' "$THEME" || fail "Theme SAF import missing"
grep -q 'Build.VERSION.SDK_INT < Build.VERSION_CODES.KITKAT' "$THEME" || fail "Legacy shared-root discovery is not pre-SAF bounded"
grep -q 'imported-themes' "$THEME" || fail "Imported themes are not persisted app-private"
grep -q 'validateThemeFile' "$THEME" || fail "Theme archive validation missing"
grep -q 'MAX_THEME_BYTES' "$THEME" || fail "Theme archive size bound missing"
grep -q 'tm_remote_unavailable' "$THEME" || fail "Remote degraded-state UI missing"
grep -q 'setConnectTimeout' "$THEME" || fail "Remote catalog connect timeout missing"
grep -q 'setReadTimeout' "$THEME" || fail "Remote catalog read timeout missing"
grep -q 'TYPE_FAILED' "$THEME_ADAPTER" || fail "Failed preview terminal row missing"
grep -q 'shutdownNow' "$THEME_LOADER" || fail "Theme loader teardown is not interruptible"
grep -q 'MAX_REMOTE_IMAGE_BYTES' "$THEME_LOADER" || fail "Remote image bound missing"
grep -q 'mDestroyed' "$THEME_LOADER" || fail "Post-destroy delivery guard missing"

echo "PASS: no-Actions publication static hardening contract"
