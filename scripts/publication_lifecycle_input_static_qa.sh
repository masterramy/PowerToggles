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
IMMERSIVE_TRACKER="$ROOT/src/com/painless/pc/tracker/ImmersiveTracker.java"
NOLOCK_TRACKER="$ROOT/src/com/painless/pc/tracker/NoLockTracker.java"
NOLOCK_SERVICE="$ROOT/src/com/painless/pc/NoLockService.java"
FLASH_TRACKER="$ROOT/src/com/painless/pc/tracker/FlashStateTracker.java"
FLASH_LEGACY="$ROOT/src/com/painless/pc/FlashService.java"
FLASH_MODERN="$ROOT/src/com/painless/pc/FlashServiceM.java"
SCREEN_TRACKER="$ROOT/src/com/painless/pc/tracker/ScreenOnTracker.java"
SCREEN_SERVICE="$ROOT/src/com/painless/pc/ScreenOnService.java"
PRIORITY_SERVICE="$ROOT/src/com/painless/pc/PriorityService.java"
MANIFEST="$ROOT/AndroidManifest.xml"

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
LAUNCH_VALIDATION_BLOCK="$(sed -n '/protected boolean isValidFragment(String fragmentName)/,/^[[:space:]]*}/p' "$LAUNCH")"
[ -n "$LAUNCH_VALIDATION_BLOCK" ] || fail "LaunchActivity fragment-validation method missing"
! printf '%s\n' "$LAUNCH_VALIDATION_BLOCK" | grep -Eq 'return[[:space:]]+true[[:space:]]*;' || fail "Exported settings Activity blanket-accepts fragment injection"
for fragment in HomeFrag NotifyFrag FolderFrag SettingsFrag InfoFrag TogglePrefFrag TCacheFrag CFolderFrag; do
  printf '%s\n' "$LAUNCH_VALIDATION_BLOCK" | grep -Fq "${fragment}.class.getName().equals(fragmentName)" || fail "LaunchActivity allowlist missing ${fragment}"
done
fragment_count="$(printf '%s\n' "$LAUNCH_VALIDATION_BLOCK" | grep -oE '[A-Za-z0-9_]+\.class\.getName\(\)\.equals\(fragmentName\)' | wc -l | tr -d '[:space:]')"
[ "$fragment_count" = "8" ] || fail "LaunchActivity allowlist is not the exact eight-fragment navigation set"
! printf '%s\n' "$LAUNCH_VALIDATION_BLOCK" | grep -Fq 'AbsListFrag.class.getName().equals(fragmentName)' || fail "Non-navigation base Fragment unexpectedly exposed"

# Long-lived service controls must obey modern background-execution rules. The
# historical Immersive TYPE_TOAST and KeyguardLock controls remain pre-O only;
# Screen Always On uses the declared special-use foreground service on O+ and
# cannot honor the legacy hidden-notification preference when foregrounding is
# mandatory.
for legacy_tracker in "$IMMERSIVE_TRACKER" "$NOLOCK_TRACKER"; do
  grep -q 'Build.VERSION.SDK_INT >= Build.VERSION_CODES.O' "$legacy_tracker" || fail "Legacy service tracker lacks Android O cutoff: $legacy_tracker"
  grep -q 'setCurrentState(context, STATE_DISABLED);' "$legacy_tracker" || fail "Legacy service tracker can leave modern toggle in transition: $legacy_tracker"
done
grep -q 'catch (SecurityException e)' "$NOLOCK_SERVICE" || fail "Legacy keyguard denial can crash NoLockService"
grep -q 'mLock != null' "$NOLOCK_SERVICE" || fail "NoLockService teardown assumes keyguard lock acquisition succeeded"
# KeyguardLock.disableKeyguard()/reenableKeyguard() require DISABLE_KEYGUARD.
# No Lock is source-disabled on Android O+, so the permission must exist only on
# the same pre-O compatibility range rather than leaking into modern installs.
grep -A2 'android:name="android.permission.DISABLE_KEYGUARD"' "$MANIFEST" | grep -q 'android:maxSdkVersion="25"' || fail "Legacy No Lock permission is missing or not capped to pre-O"

# The legacy flashlight implementation opens android.hardware.Camera only below
# Android M. API23+ uses CameraManager.setTorchMode instead, so the historical
# FLASHLIGHT/CAMERA permissions must not leak into modern installs.
grep -Fq 'Build.VERSION.SDK_INT >= Build.VERSION_CODES.M ? FlashServiceM.class : FlashService.class' "$FLASH_TRACKER" || fail "Flash tracker no longer preserves the pre-M/modern implementation split"
grep -q 'android.hardware.Camera' "$FLASH_LEGACY" || fail "Legacy flashlight implementation no longer matches the pre-M permission boundary"
grep -q 'CameraManager' "$FLASH_MODERN" || fail "Modern flashlight implementation no longer uses CameraManager"
grep -q 'setTorchMode' "$FLASH_MODERN" || fail "Modern flashlight implementation no longer uses torch API"
grep -A2 'android:name="android.permission.FLASHLIGHT"' "$MANIFEST" | grep -q 'android:maxSdkVersion="22"' || fail "Legacy FLASHLIGHT permission is not capped to pre-M"
grep -A2 'android:name="android.permission.CAMERA"' "$MANIFEST" | grep -q 'android:maxSdkVersion="22"' || fail "Legacy CAMERA permission is not capped to pre-M"
# Pre-M camera acquisition/configuration failures must be truthful and teardown
# must tolerate partial initialization. Never publish a false enabled torch state.
grep -q 'throw new IllegalStateException("Unable to open flashlight camera")' "$FLASH_LEGACY" || fail "Legacy flashlight null-camera failure is not explicit"
grep -q 'releaseCamera();' "$FLASH_LEGACY" || fail "Legacy flashlight failure path does not release partial camera state"
grep -q 'FLASH_ON = false;' "$FLASH_LEGACY" || fail "Legacy flashlight failure path does not publish disabled state"
grep -q 'stopSelf();' "$FLASH_LEGACY" || fail "Legacy flashlight failure path does not stop the failed service"
grep -q 'if (handler != null)' "$FLASH_LEGACY" || fail "Legacy flashlight teardown assumes handler initialization succeeded"
grep -q 'lock != null && lock.isHeld()' "$FLASH_LEGACY" || fail "Legacy flashlight teardown assumes wake lock acquisition succeeded"
grep -q 'wm != null && surface != null' "$FLASH_LEGACY" || fail "Legacy flashlight teardown assumes overlay initialization succeeded"


grep -q 'context.startForegroundService(i);' "$SCREEN_TRACKER" || fail "Screen Always On does not use foreground-service launch on Android O+"
grep -q 'catch (IllegalStateException e)' "$SCREEN_TRACKER" || fail "Rejected Screen Always On foreground launch can crash caller"
grep -q 'setCurrentState(context, STATE_DISABLED);' "$SCREEN_TRACKER" || fail "Rejected Screen Always On launch can remain stuck in transition"
grep -q 'boolean listenToDeviceLock, boolean forceForeground' "$PRIORITY_SERVICE" || fail "PriorityService cannot force a required foreground notification"
grep -q 'forceForeground || !Globals.getAppPrefs' "$PRIORITY_SERVICE" || fail "Required foreground notification still obeys legacy hide preference"
grep -q 'Build.VERSION.SDK_INT >= Build.VERSION_CODES.O' "$SCREEN_SERVICE" || fail "ScreenOnService does not force modern foreground promotion"
grep -q 'lock != null && lock.isHeld()' "$SCREEN_SERVICE" || fail "ScreenOnService teardown can release an invalid wake lock"
grep -q 'android:name="ScreenOnService" android:exported="false" android:foregroundServiceType="specialUse"' "$MANIFEST" || fail "ScreenOnService special-use foreground declaration missing"
grep -q 'android.permission.FOREGROUND_SERVICE_SPECIAL_USE' "$MANIFEST" || fail "ScreenOnService special-use foreground permission missing"

echo "PASS: lifecycle/import static contract"
