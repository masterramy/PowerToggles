#!/usr/bin/env bash
set -euo pipefail

OUT="runtime-evidence/folder-backup-share"
mkdir -p "$OUT/screens" "$OUT/ui" "$OUT/state" "$OUT/logs"
SRC="src/com/painless/pc/nav/FolderFrag.java"
PROVIDER="src/com/painless/pc/FileProvider.java"
QA_NAME="QA Folder 314159"
SHARE_URI="content://com.painless.pc.file/folder-share"
BACKUP_NAME="power-toggles-folders.pcf"
CONSUMER_PKG="com.painless.pc.qaconsumer"
rc=0

static_check_absent() {
  local pattern="$1" label="$2"
  if grep -Eq "$pattern" "$SRC"; then
    printf 'RED %s\n' "$label" | tee -a "$OUT/state/source-contract.txt" >&2
    rc=1
  else
    printf 'PASS %s\n' "$label" | tee -a "$OUT/state/source-contract.txt"
  fi
}

static_check_present() {
  local file="$1" pattern="$2" label="$3"
  if grep -Eq "$pattern" "$file"; then
    printf 'PASS %s\n' "$label" | tee -a "$OUT/state/source-contract.txt"
  else
    printf 'RED %s\n' "$label" | tee -a "$OUT/state/source-contract.txt" >&2
    rc=1
  fi
}

: > "$OUT/state/source-contract.txt"
static_check_absent 'MODE_WORLD_READABLE' 'folder share never uses world-readable private files'
static_check_absent 'Uri\.fromFile\(' 'folder share never exposes file:// URIs'
static_check_present "$SRC" 'ACTION_CREATE_DOCUMENT' 'folder backup uses framework document creation'
static_check_present "$SRC" 'ACTION_OPEN_DOCUMENT' 'folder restore uses framework document opening'
static_check_present "$SRC" 'FLAG_GRANT_READ_URI_PERMISSION' 'folder share grants read access explicitly'
static_check_present "$SRC" 'content://com\.painless\.pc\.file/folder-share|FOLDER_SHARE_URI' 'folder share uses the scoped content URI'
static_check_present "$PROVIDER" 'folder-share' 'provider exposes a dedicated folder-share path'
static_check_present "$PROVIDER" 'checkUriPermission' 'provider enforces URI grants for external folder-share readers'
if [ "$rc" -ne 0 ]; then
  echo 'Folder backup/share publication source contract is RED.' >&2
  exit "$rc"
fi

fatal_scan() {
  local name="$1"
  adb logcat -d > "$OUT/logs/${name}.logcat.txt"
  if grep -E "FATAL EXCEPTION|Process: com\.painless\.pc.*has died|ANR in com\.painless\.pc|am_crash.*com\.painless\.pc|am_anr.*com\.painless\.pc" "$OUT/logs/${name}.logcat.txt"; then
    echo "Fatal Power Toggles runtime signal during ${name}" >&2
    return 1
  fi
}

dump_ui() {
  local name="$1" remote="/sdcard/${name}.xml"
  adb shell rm -f "$remote" >/dev/null 2>&1 || true
  rm -f "$OUT/ui/${name}.xml"
  for attempt in 1 2 3 4 5; do
    adb shell uiautomator dump "$remote" >/dev/null 2>&1 || true
    if adb shell test -s "$remote" >/dev/null 2>&1; then
      adb pull "$remote" "$OUT/ui/${name}.xml" >/dev/null 2>&1 || true
      test -s "$OUT/ui/${name}.xml" && return 0
    fi
    sleep 1
  done
  echo "Unable to capture UI hierarchy for ${name}" >&2
  return 1
}

capture() {
  local name="$1"
  dump_ui "$name"
  adb exec-out screencap -p > "$OUT/screens/${name}.png"
  adb shell dumpsys activity activities > "$OUT/state/${name}.activities.txt"
  adb shell dumpsys window windows > "$OUT/state/${name}.windows.txt"
  fatal_scan "$name"
}

node_coords() {
  local name="$1" needle="$2"
  dump_ui "$name"
  python3 - "$OUT/ui/${name}.xml" "$needle" <<'PY'
import re, sys, xml.etree.ElementTree as ET
path, needle = sys.argv[1:]
for node in ET.parse(path).iter():
    vals=(node.attrib.get('text',''), node.attrib.get('content-desc',''), node.attrib.get('resource-id',''))
    if not any(needle in v for v in vals):
        continue
    m=re.fullmatch(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]', node.attrib.get('bounds',''))
    if m:
        x1,y1,x2,y2=map(int,m.groups())
        print((x1+x2)//2, (y1+y2)//2)
        raise SystemExit(0)
raise SystemExit('Rendered node not found: '+needle)
PY
}

tap_node() {
  local name="$1" needle="$2" coords
  coords="$(node_coords "$name" "$needle")"
  read -r x y <<< "$coords"
  adb shell input tap "$x" "$y"
}

long_press_node() {
  local name="$1" needle="$2" coords
  coords="$(node_coords "$name" "$needle")"
  read -r x y <<< "$coords"
  adb shell input swipe "$x" "$y" "$x" "$y" 900
}

wait_for_node() {
  local name="$1" needle="$2" attempts="${3:-10}"
  for attempt in $(seq 1 "$attempts"); do
    if dump_ui "$name" && python3 - "$OUT/ui/${name}.xml" "$needle" <<'PY'
import sys, xml.etree.ElementTree as ET
path, needle=sys.argv[1:]
for node in ET.parse(path).iter():
    if any(needle in node.attrib.get(k,'') for k in ('text','content-desc','resource-id')):
        raise SystemExit(0)
raise SystemExit(1)
PY
    then return 0; fi
    sleep 1
  done
  return 1
}

assert_documents_ui() {
  local name="$1"
  grep -Eq 'com\.google\.android\.documentsui|com\.android\.documentsui' "$OUT/state/${name}.activities.txt"
}

probe() {
  local action="$1"
  adb shell am force-stop com.painless.pc >/dev/null 2>&1 || true
  adb shell am start -W -n com.painless.pc/.tracker.PublicationFolderProbeActivity --es probe "$action" >/dev/null
  sleep 1
}

pull_probe() {
  adb shell run-as com.painless.pc cat shared_prefs/publication_folder_probe.xml > "$OUT/state/probe-prefs.xml"
}

read_probe() {
  local key="$1"
  python3 - "$OUT/state/probe-prefs.xml" "$key" <<'PY'
import sys, xml.etree.ElementTree as ET
root=ET.parse(sys.argv[1]).getroot(); key=sys.argv[2]
for node in root:
    if node.attrib.get('name')==key:
        print(node.text or '' if node.tag=='string' else node.attrib.get('value',''))
        raise SystemExit(0)
raise SystemExit('missing probe key: '+key)
PY
}

launch_folder() {
  adb shell am force-stop com.painless.pc >/dev/null 2>&1 || true
  adb logcat -c
  adb shell am start -W -n com.painless.pc/.settings.LaunchActivity \
    --es ':android:show_fragment' com.painless.pc.nav.FolderFrag \
    > "$OUT/state/folder-launch.txt"
  sleep 2
}

build_consumer() {
  local root="$RUNNER_TEMP/folder-share-consumer"
  rm -rf "$root"
  mkdir -p "$root/src/main/java/com/painless/pc/qaconsumer"
  cat > "$root/settings.gradle" <<'EOF'
pluginManagement { repositories { google(); mavenCentral(); gradlePluginPortal() } }
dependencyResolutionManagement { repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS); repositories { google(); mavenCentral() } }
rootProject.name='FolderShareConsumer'
EOF
  cat > "$root/build.gradle" <<'EOF'
plugins {
    id 'com.android.application' version '8.13.2'
}

android {
    namespace 'com.painless.pc.qaconsumer'
    compileSdk 36
    defaultConfig {
        applicationId 'com.painless.pc.qaconsumer'
        minSdk 23
        targetSdk 36
        versionCode 1
        versionName '1.0'
    }
}
EOF
  cat > "$root/src/main/AndroidManifest.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
  <application android:theme="@android:style/Theme.Material.Light.NoActionBar" android:label="QA Folder Share Consumer">
    <activity android:name=".ShareReceiverActivity" android:exported="true" android:label="QA Folder Share Consumer">
      <intent-filter>
        <action android:name="android.intent.action.SEND" />
        <category android:name="android.intent.category.DEFAULT" />
        <data android:mimeType="application/zip" />
      </intent-filter>
    </activity>
  </application>
</manifest>
EOF
  cat > "$root/src/main/java/com/painless/pc/qaconsumer/ShareReceiverActivity.java" <<'EOF'
package com.painless.pc.qaconsumer;

import android.app.Activity;
import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;

public final class ShareReceiverActivity extends Activity {
  @Override protected void onCreate(Bundle state) {
    super.onCreate(state);
    String result;
    try {
      Uri uri = getIntent().getParcelableExtra(Intent.EXTRA_STREAM);
      if (uri == null) throw new IllegalStateException("missing stream");
      InputStream in = getContentResolver().openInputStream(uri);
      if (in == null) throw new IllegalStateException("null stream");
      long bytes=0; byte[] buffer=new byte[8192]; int read;
      while ((read=in.read(buffer)) != -1) bytes += read;
      in.close();
      result="PASS bytes="+bytes+" uri="+uri.toString()+"\n";
    } catch (Throwable t) {
      result="FAIL "+t.getClass().getName()+":"+String.valueOf(t.getMessage())+"\n";
    }
    try {
      FileOutputStream out=new FileOutputStream(new File(getFilesDir(), "result.txt"));
      out.write(result.getBytes(StandardCharsets.UTF_8)); out.close();
    } catch (Throwable ignored) { }
    finish();
  }
}
EOF
  gradle -p "$root" --no-daemon assembleDebug > "$OUT/logs/share-consumer-build.txt" 2>&1
  local apk
  apk="$(find "$root/build/outputs/apk/debug" -name '*.apk' | head -n1)"
  test -s "$apk"
  adb install -r "$apk" > "$OUT/state/share-consumer-install.txt"
}

cleanup() {
  adb shell am force-stop com.painless.pc >/dev/null 2>&1 || true
  adb shell am force-stop "$CONSUMER_PKG" >/dev/null 2>&1 || true
  adb shell pm uninstall "$CONSUMER_PKG" >/dev/null 2>&1 || true
  adb shell rm -f "/sdcard/Download/$BACKUP_NAME" >/dev/null 2>&1 || true
  adb shell am start -W -n com.painless.pc/.tracker.PublicationFolderProbeActivity --es probe cleanup >/dev/null 2>&1 || true
}
trap cleanup EXIT

build_consumer
probe cleanup || true
probe seed
pull_probe
SEED_DB="$(read_probe seed_db)"
test -n "$SEED_DB"
printf 'seed_db=%s\n' "$SEED_DB" > "$OUT/state/seed.txt"

# No external caller may open the exported provider path without a URI grant.
adb shell run-as "$CONSUMER_PKG" rm -f files/result.txt >/dev/null 2>&1 || true
adb shell am start -W -a android.intent.action.SEND -t application/zip \
  -n "$CONSUMER_PKG/.ShareReceiverActivity" \
  --eu android.intent.extra.STREAM "$SHARE_URI" > "$OUT/state/share-negative-start.txt" 2>&1 || true
sleep 1
adb shell run-as "$CONSUMER_PKG" cat files/result.txt > "$OUT/state/share-negative-result.txt"
# Android 16 may hide an ungranted provider from the external caller entirely,
# producing FileNotFoundException:No content provider instead of SecurityException.
# Either result proves denial here; the positive share below must then prove that
# the explicit customer-path URI grant makes the same exact URI readable cross-UID.
grep -Eq '^FAIL (java\.lang\.SecurityException|java\.io\.FileNotFoundException:No content provider: content://com\.painless\.pc\.file/folder-share)' "$OUT/state/share-negative-result.txt"

# Exact rendered Folder list and action mode, then real cross-UID Share selection.
launch_folder
capture "00-folder-list"
grep -Fq "text=\"$QA_NAME\"" "$OUT/ui/00-folder-list.xml"
long_press_node "01-folder-longpress-source" "$QA_NAME"
sleep 1
capture "01-folder-action-mode"
grep -Eq 'text="Share"|content-desc="Share"' "$OUT/ui/01-folder-action-mode.xml"

adb shell run-as "$CONSUMER_PKG" rm -f files/result.txt >/dev/null 2>&1 || true
adb logcat -c
tap_node "02-share-source" "Share"
sleep 2
if ! adb shell run-as "$CONSUMER_PKG" test -s files/result.txt >/dev/null 2>&1; then
  if wait_for_node "02-share-target-wait" "QA Folder Share Consumer" 8; then
    capture "02-share-target-list"
    tap_node "02-share-target-source" "QA Folder Share Consumer"
    sleep 2
  fi
fi
adb shell run-as "$CONSUMER_PKG" cat files/result.txt > "$OUT/state/share-positive-result.txt"
grep -Eq '^PASS bytes=[1-9][0-9]* uri=content://com\.painless\.pc\.file/folder-share$' "$OUT/state/share-positive-result.txt"
adb exec-out run-as com.painless.pc cat files/folder.pcf > "$OUT/state/shared-folder.pcf"
test -s "$OUT/state/shared-folder.pcf"
unzip -t "$OUT/state/shared-folder.pcf" | tee "$OUT/state/shared-unzip-test.txt"
unzip -p "$OUT/state/shared-folder.pcf" folders.txt > "$OUT/state/shared-folders.txt"
grep -Fxq "$QA_NAME" "$OUT/state/shared-folders.txt"
fatal_scan "02-share-positive"

# Create a real customer backup through ACTION_CREATE_DOCUMENT.
adb shell rm -f "/sdcard/Download/$BACKUP_NAME" >/dev/null 2>&1 || true
launch_folder
long_press_node "03-backup-longpress-source" "$QA_NAME"
sleep 1
tap_node "03-backup-overflow-source" "More options"
sleep 1
capture "03-backup-action-overflow"
grep -Fq 'text="Create Backup"' "$OUT/ui/03-backup-action-overflow.xml"
tap_node "04-backup-source" "Create Backup"
sleep 2
capture "04-backup-document"
assert_documents_ui "04-backup-document"
grep -Fq "text=\"$BACKUP_NAME\"" "$OUT/ui/04-backup-document.xml"
grep -Fq 'text="SAVE"' "$OUT/ui/04-backup-document.xml"
tap_node "05-backup-save-source" "SAVE"
sleep 4
capture "05-backup-return"
for attempt in $(seq 1 10); do
  adb shell test -s "/sdcard/Download/$BACKUP_NAME" >/dev/null 2>&1 && break
  sleep 1
done
adb shell test -s "/sdcard/Download/$BACKUP_NAME"
adb pull "/sdcard/Download/$BACKUP_NAME" "$OUT/state/$BACKUP_NAME" >/dev/null
unzip -t "$OUT/state/$BACKUP_NAME" | tee "$OUT/state/backup-unzip-test.txt"
unzip -p "$OUT/state/$BACKUP_NAME" folders.txt > "$OUT/state/backup-folders.txt"
grep -Fxq "$QA_NAME" "$OUT/state/backup-folders.txt"
sha256sum "$OUT/state/$BACKUP_NAME" > "$OUT/state/backup-sha256.txt"

# Delete the source through the customer destructive path and prove absence.
launch_folder
long_press_node "06-delete-longpress-source" "$QA_NAME"
sleep 1
tap_node "06-delete-source" "Delete"
sleep 1
capture "06-delete-confirm"
grep -Fq 'text="Yes"' "$OUT/ui/06-delete-confirm.xml"
tap_node "07-delete-yes-source" "Yes"
sleep 2
capture "07-delete-return"
if grep -Fq "text=\"$QA_NAME\"" "$OUT/ui/07-delete-return.xml"; then
  echo 'Folder remained rendered after customer deletion' >&2
  exit 1
fi
probe verify_deleted
pull_probe
test "$(read_probe deleted_original_absent)" = "true"
test "$(read_probe deleted_named_count)" = "0"

# Restore the actual backup through ACTION_OPEN_DOCUMENT.
launch_folder
tap_node "08-restore-overflow-source" "More options"
sleep 1
capture "08-restore-overflow"
grep -Fq 'text="Restore Backup"' "$OUT/ui/08-restore-overflow.xml"
tap_node "09-restore-source" "Restore Backup"
sleep 2
capture "09-restore-document"
assert_documents_ui "09-restore-document"
if ! wait_for_node "10-backup-file-wait" "$BACKUP_NAME" 5; then
  tap_node "10-roots-source" "Show roots"
  sleep 1
  wait_for_node "10-downloads-wait" "Downloads" 5
  tap_node "10-downloads-source" "Downloads"
  sleep 2
  wait_for_node "10-backup-file-downloads-wait" "$BACKUP_NAME" 8
fi
capture "10-backup-visible"
tap_node "11-backup-select-source" "$BACKUP_NAME"
sleep 4
launch_folder
capture "11-restored-folder-list"
grep -Fq "text=\"$QA_NAME\"" "$OUT/ui/11-restored-folder-list.xml"
probe verify_restored
pull_probe
test "$(read_probe restored_named_count)" = "1"
test "$(read_probe restored_semantic_row)" = "true"
RESTORED_DB="$(read_probe restored_db)"
printf 'restored_db=%s\n' "$RESTORED_DB" > "$OUT/state/restored.txt"

# Process-death persistence must retain the restored folder and semantic row.
adb shell am force-stop com.painless.pc
launch_folder
capture "12-restored-after-process-death"
grep -Fq "text=\"$QA_NAME\"" "$OUT/ui/12-restored-after-process-death.xml"
probe verify_restored
pull_probe
test "$(read_probe restored_named_count)" = "1"
test "$(read_probe restored_semantic_row)" = "true"

echo 'Folder backup/delete/restore/share publication QA PASS'
