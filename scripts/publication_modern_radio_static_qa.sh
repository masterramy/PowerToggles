#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MANIFEST="$ROOT/AndroidManifest.xml"
GLOBALS="$ROOT/src/com/painless/pc/singleton/Globals.java"
WIFI="$ROOT/src/com/painless/pc/tracker/WifiStateTracker.java"
ADB_WIFI="$ROOT/src/com/painless/pc/tracker/AdbWirelessTracker.java"
WIMAX="$ROOT/src/com/painless/pc/tracker/WiMaxTracker.java"
SETTING_STORAGE="$ROOT/src/com/painless/pc/singleton/SettingStorage.java"
BT="$ROOT/src/com/painless/pc/tracker/BluetoothTracker.java"
BT_DISCOVERY="$ROOT/src/com/painless/pc/tracker/BluetoothDiscoveryTracker.java"
BT_HOTSPOT="$ROOT/src/com/painless/pc/tracker/BluetoothHotspotTracker.java"
FLASH="$ROOT/src/com/painless/pc/tracker/FlashStateTracker.java"
FLASH_MODERN="$ROOT/src/com/painless/pc/FlashServiceM.java"
LEGACY_FLASH="$ROOT/src/com/painless/pc/FlashService.java"
PROVIDER="$ROOT/src/com/painless/pc/FileProvider.java"
WIDGET_SETTING="$ROOT/src/com/painless/pc/util/WidgetSetting.java"
PCWIDGET="$ROOT/src/com/painless/pc/PCWidgetActivity.java"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

# Modern installs must not advertise legacy Bluetooth, account-list, location,
# direct Wi-Fi mutation, legacy connectivity-state, retired WiMAX connectivity,
# phone-state identity, or pre-Marshmallow flashlight-overlay permissions for
# user-mediated controls / explicitly visible account sync / optional SSID
# decoration / legacy refresh paths.
grep -A2 'android:name="android.permission.BLUETOOTH"' "$MANIFEST" | grep -q 'android:maxSdkVersion="30"' || fail "BLUETOOTH not capped to Android 11"
grep -A2 'android:name="android.permission.BLUETOOTH_ADMIN"' "$MANIFEST" | grep -q 'android:maxSdkVersion="30"' || fail "BLUETOOTH_ADMIN not capped to Android 11"
grep -A2 'android:name="android.permission.GET_ACCOUNTS"' "$MANIFEST" | grep -q 'android:maxSdkVersion="25"' || fail "GET_ACCOUNTS not capped below Android 8"
grep -A2 'android:name="android.permission.ACCESS_FINE_LOCATION"' "$MANIFEST" | grep -q 'android:maxSdkVersion="28"' || fail "ACCESS_FINE_LOCATION not capped to Android 9"
grep -A2 'android:name="android.permission.CHANGE_WIFI_STATE"' "$MANIFEST" | grep -q 'android:maxSdkVersion="28"' || fail "CHANGE_WIFI_STATE not capped to Android 9"
grep -A2 'android:name="android.permission.ACCESS_NETWORK_STATE"' "$MANIFEST" | grep -q 'android:maxSdkVersion="23"' || fail "ACCESS_NETWORK_STATE not capped to legacy pre-N connectivity refresh"
grep -A2 'android:name="android.permission.SYSTEM_ALERT_WINDOW"' "$MANIFEST" | grep -q 'android:maxSdkVersion="22"' || fail "SYSTEM_ALERT_WINDOW not capped to legacy pre-Marshmallow flashlight path"
! grep -q 'android.permission.CHANGE_NETWORK_STATE' "$MANIFEST" || fail "Retired WiMAX CHANGE_NETWORK_STATE permission reintroduced"
! grep -q 'android.net.wimax.WIMAX_STATE_CHANGE' "$MANIFEST" || fail "Retired WiMAX broadcast subscription reintroduced"
! grep -q 'android.permission.READ_PHONE_STATE' "$MANIFEST" || fail "Sensitive READ_PHONE_STATE permission unexpectedly advertised"
! grep -q 'android.permission.READ_BASIC_PHONE_STATE' "$MANIFEST" || fail "Sensitive READ_BASIC_PHONE_STATE permission unexpectedly advertised"
! grep -q 'android.permission.BLUETOOTH_CONNECT' "$MANIFEST" || fail "Modern Nearby Devices permission unexpectedly advertised"
! grep -q 'android.permission.BLUETOOTH_SCAN' "$MANIFEST" || fail "Modern Bluetooth scan permission unexpectedly advertised"

# Historical system/root builds advertised platform-only privileges that an
# ordinary Play application cannot obtain. Keep the publication manifest free of
# the entire family instead of preserving declarations that imply unsupported
# capabilities.
for forbidden_permission in \
    android.permission.MANAGE_USB \
    android.permission.UPDATE_DEVICE_STATS \
    android.permission.CHANGE_CONFIGURATION \
    android.permission.WRITE_SECURE_SETTINGS \
    android.permission.ACCESS_SUPERUSER \
    android.permission.MODIFY_PHONE_STATE \
    android.permission.REBOOT \
    android.permission.EXPAND_STATUS_BAR; do
  ! grep -q "$forbidden_permission" "$MANIFEST" || fail "platform/root-only permission reintroduced: $forbidden_permission"
done

# Network-type icon/label rendering is informational only. Current Android gates
# the real data-radio technology behind phone-state capability, so publication
# source must fail closed to the historical UNKNOWN bucket rather than touching
# TelephonyManager from widget/notification rendering or growing permission scope.
python3 - "$GLOBALS" <<'PY'
import re
import sys

path = sys.argv[1]
text = open(path, encoding="utf-8").read()
if "android.telephony.TelephonyManager" in text or "TelephonyManager." in text:
    raise SystemExit("FAIL: restricted TelephonyManager network-type read reintroduced")
match = re.search(r"public static final int getNetworkType\(Context context\)\s*\{(.*?)\n\s*\}", text, re.S)
if not match:
    raise SystemExit("FAIL: network type compatibility helper missing")
body = match.group(1)
if "sNetworkName = context.getString(R.string.lbl_unknown_allcap);" not in body:
    raise SystemExit("FAIL: network type helper no longer labels restricted state UNKNOWN")
if not re.search(r"\breturn\s+1\s*;", body):
    raise SystemExit("FAIL: network type helper no longer returns historical UNKNOWN icon level")
print("PASS: mobile network rendering is phone-state-free and fail-closed")
PY

# The pre-M implementation remains an explicitly capped compatibility service.
# Android M+ must use CameraManager.setTorchMode directly from the tracker rather
# than attempting a background or camera foreground service and growing CAMERA/
# FGS permission scope. FlashServiceM is now a process-scoped utility, not a
# manifest component.
grep -q 'WindowManager.LayoutParams.TYPE_SYSTEM_OVERLAY' "$LEGACY_FLASH" || fail "Legacy flashlight overlay path unexpectedly removed or drifted"
grep -q 'Build.VERSION.SDK_INT >= Build.VERSION_CODES.M' "$FLASH" || fail "Modern flashlight API boundary missing"
grep -Fq 'FlashServiceM.isEnabled(context)' "$FLASH" || fail "Modern flashlight state no longer uses direct torch controller"
grep -Fq 'FlashServiceM.setEnabled(context, desiredState)' "$FLASH" || fail "Modern flashlight toggle no longer uses direct torch controller"
! grep -q 'FlashServiceM.class' "$FLASH" || fail "Modern flashlight service launch reintroduced"
grep -q 'CameraManager' "$FLASH_MODERN" || fail "Modern flashlight CameraManager controller missing"
grep -q 'setTorchMode' "$FLASH_MODERN" || fail "Modern flashlight public setTorchMode call missing"
! grep -qE 'extends[[:space:]]+(PriorityService|Service)' "$FLASH_MODERN" || fail "Modern flashlight controller became an Android service again"
! grep -q 'android:name="FlashServiceM"' "$MANIFEST" || fail "Modern flashlight utility reintroduced as manifest service"
grep -A2 'android:name="android.permission.CAMERA"' "$MANIFEST" | grep -q 'android:maxSdkVersion="22"' || fail "CAMERA permission escaped pre-M legacy boundary"

# The retired online theme catalog was the remaining outbound network feature.
# Publication WIP is local/SAF-only, so do not regain INTERNET or direct Java
# network APIs without an explicit product/privacy review.
! grep -q 'android.permission.INTERNET' "$MANIFEST" || fail "Retired INTERNET permission reintroduced"
! grep -R -E -q 'java\.net\.|HttpResponseCache|\.openConnection\(|\.openStream\(' "$ROOT/src" || fail "Outbound Java network path reintroduced"

# Wi-Fi control on Android 10+ must be truthful/user-mediated and SSID identity
# must degrade without location/nearby permission instead of prompting.
grep -q 'Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q' "$WIFI" || fail "Wi-Fi modern API boundary missing"
grep -q 'Settings.Panel.ACTION_WIFI' "$WIFI" || fail "Wi-Fi modern system panel missing"
grep -q 'Build.VERSION.SDK_INT < Build.VERSION_CODES.Q' "$WIFI" || fail "SSID access is not bounded to pre-Android-10"
grep -q 'wifiManager.setWifiEnabled(desiredState)' "$WIFI" || fail "Legacy pre-Q Wi-Fi mutation path unexpectedly removed or drifted"
grep -q 'wifiManager.getConnectionInfo().getSSID()' "$WIFI" || fail "Legacy SSID path unexpectedly removed"
grep -q 'catch (SecurityException e)' "$WIFI" || fail "Wi-Fi protected access lacks SecurityException degradation"

# ADB Wireless is RETIRED_F3. Historical tracker ID 39 must remain loadable,
# but publication source must not regain hidden SystemProperties, root/adbd
# mutation, or direct Wi-Fi state mutation merely for retired behavior.
grep -q 'RETIRED_F3' "$ADB_WIFI" || fail "ADB wireless retirement marker missing"
grep -q 'return STATE_DISABLED' "$ADB_WIFI" || fail "ADB wireless compatibility shell is not fail-closed disabled"
! grep -Eq 'import[[:space:]]+android\.os\.SystemProperties|SystemProperties[[:space:]]*\.|"android\.os\.SystemProperties"' "$ADB_WIFI" || fail "ADB wireless hidden SystemProperties path reintroduced"
! grep -q 'RootTools' "$ADB_WIFI" || fail "ADB wireless root mutation path reintroduced"
! grep -q 'setWifiEnabled' "$ADB_WIFI" || fail "ADB wireless direct Wi-Fi mutation reintroduced"

# WiMAX is RETIRED_F3. Keep tracker ID 14 loadable for legacy saved definitions,
# but never probe/mutate obsolete WiMAX services or request connectivity mutation
# privileges/broadcasts solely for that retired control.
grep -q 'RETIRED_F3' "$WIMAX" || fail "WiMAX retirement marker missing"
grep -q 'return STATE_DISABLED' "$WIMAX" || fail "WiMAX compatibility shell is not fail-closed disabled"
! grep -q 'ReflectionUtil' "$WIMAX" || fail "WiMAX reflection bridge reintroduced"
! grep -q 'setWimaxEnabled' "$WIMAX" || fail "WiMAX mutation bridge reintroduced"
! grep -q 'getWimax' "$WIMAX" || fail "WiMAX hidden state probe reintroduced"

# Data Network's historical connectivity refresh is a manifest CONNECTIVITY_CHANGE
# receiver. Android N+ does not deliver that implicit broadcast to manifest
# receivers for modern-target apps, so the dynamic component must remain disabled
# there and ACCESS_NETWORK_STATE is retained only for the pre-N compatibility path.
grep -q 'Build.VERSION.SDK_INT < Build.VERSION_CODES.N && trackerList\[11\] != null' "$SETTING_STORAGE" || fail "Legacy connectivity receiver is not pre-N bounded"
grep -q 'new ComponentName(context, ConnectivityReceiver.class)' "$SETTING_STORAGE" || fail "Legacy connectivity receiver component path unexpectedly removed"

# Bluetooth state/control on Android 12+ must not touch protected adapter APIs.
grep -q 'Build.VERSION.SDK_INT >= Build.VERSION_CODES.S' "$BT" || fail "Bluetooth modern API boundary missing"
grep -q 'return STATE_UNKNOWN' "$BT" || fail "Bluetooth modern state does not degrade to UNKNOWN"
grep -q 'Settings.ACTION_BLUETOOTH_SETTINGS' "$BT" || fail "Bluetooth modern system settings handoff missing"
grep -q 'Build.VERSION.SDK_INT >= Build.VERSION_CODES.S' "$BT_DISCOVERY" || fail "Bluetooth discovery modern API boundary missing"
grep -q 'return STATE_UNKNOWN' "$BT_DISCOVERY" || fail "Bluetooth discovery modern state does not degrade to UNKNOWN"
grep -q 'Settings.ACTION_BLUETOOTH_SETTINGS' "$BT_DISCOVERY" || fail "Bluetooth discovery modern system settings handoff missing"
grep -q 'Build.VERSION.SDK_INT >= Build.VERSION_CODES.S' "$BT_HOTSPOT" || fail "Bluetooth hotspot modern API boundary missing"
grep -q 'return STATE_UNKNOWN' "$BT_HOTSPOT" || fail "Bluetooth hotspot modern state does not degrade to UNKNOWN"

# Share metadata must be protected by the same exact read capability as data.
# Guard the query-specific markers so an openFile-only check cannot satisfy this.
grep -q 'enforceReadGrant(uri, "folder share metadata")' "$PROVIDER" || fail "Folder share metadata is not grant-gated"
grep -q 'enforceReadGrant(uri, "widget share metadata")' "$PROVIDER" || fail "Widget share metadata is not grant-gated"
grep -q 'enforceReadGrant(uri, "folder share")' "$PROVIDER" || fail "Folder share data is not grant-gated"
grep -q 'enforceReadGrant(uri, "widget share")' "$PROVIDER" || fail "Widget share data is not grant-gated"
grep -q 'public Cursor query' "$PROVIDER" || fail "FileProvider query override missing"
grep -Fq 'public int update(Uri uri, ContentValues values, String selection, String[] selectionArgs)' "$PROVIDER" || fail "ContentProvider update override signature drifted"

# Widget backgrounds must remain launcher/SystemUI-compatible without exposing a
# predictable /back/?<id> read surface to arbitrary applications. New RemoteViews
# publish an opaque capability URI; legacy URI access is restricted to same UID,
# Android system UID, or the currently resolved HOME launcher during upgrade.
grep -q 'appendPath(getOrCreateWidgetBackToken(context, widgetId))' "$PROVIDER" || fail "Widget background capability URI missing"
grep -q 'getExistingWidgetBackToken(context, widgetId)' "$PROVIDER" || fail "External widget background capability validation missing"
grep -q 'Widget background capability required' "$PROVIDER" || fail "Widget background capability denial missing"
grep -q 'isCurrentHomeUid(context, callerUid)' "$PROVIDER" || fail "Legacy widget background migration is not launcher-bounded"
grep -q 'backimage = FileProvider.widgetBackUri(context, widgetId)' "$WIDGET_SETTING" || fail "Widget rendering still publishes predictable background URI"

# Both notification rows must select notification RemoteViews styling, and the
# second row must retain pseudo-widget ID -23 when constructing click transports.
# Otherwise tracker 33 (Widget Settings) from row two would reopen row one's -22
# configuration despite rendering settings loaded from -23.
grep -q 'STATUS_BAR_WIDGET_ID_2' "$WIDGET_SETTING" || fail "Second notification row constant missing"
grep -Fq '(widgetId == STATUS_BAR_WIDGET_ID) || (widgetId == STATUS_BAR_WIDGET_ID_2)' "$WIDGET_SETTING" || fail "Second notification row is not classified as notification"
grep -Fq 'getRemoteView(context, settings, true, Globals.STATUS_BAR_WIDGET_ID_2)' "$PCWIDGET" || fail "Second notification row click identity is not -23"

echo "PASS: modern radio/privacy/provider/flash/static notification identity contract"
