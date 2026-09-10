#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MANIFEST="$ROOT/AndroidManifest.xml"
WIFI="$ROOT/src/com/painless/pc/tracker/WifiStateTracker.java"
ADB_WIFI="$ROOT/src/com/painless/pc/tracker/AdbWirelessTracker.java"
BT="$ROOT/src/com/painless/pc/tracker/BluetoothTracker.java"
BT_DISCOVERY="$ROOT/src/com/painless/pc/tracker/BluetoothDiscoveryTracker.java"
BT_HOTSPOT="$ROOT/src/com/painless/pc/tracker/BluetoothHotspotTracker.java"
FLASH="$ROOT/src/com/painless/pc/tracker/FlashStateTracker.java"
LEGACY_FLASH="$ROOT/src/com/painless/pc/FlashService.java"
PROVIDER="$ROOT/src/com/painless/pc/FileProvider.java"
WIDGET_SETTING="$ROOT/src/com/painless/pc/util/WidgetSetting.java"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

# Modern installs must not advertise legacy Bluetooth, account-list, location,
# direct Wi-Fi mutation, or pre-Marshmallow flashlight-overlay permissions for
# user-mediated controls / explicitly visible account sync / optional SSID
# decoration / legacy camera workarounds.
grep -A2 'android:name="android.permission.BLUETOOTH"' "$MANIFEST" | grep -q 'android:maxSdkVersion="30"' || fail "BLUETOOTH not capped to Android 11"
grep -A2 'android:name="android.permission.BLUETOOTH_ADMIN"' "$MANIFEST" | grep -q 'android:maxSdkVersion="30"' || fail "BLUETOOTH_ADMIN not capped to Android 11"
grep -A2 'android:name="android.permission.GET_ACCOUNTS"' "$MANIFEST" | grep -q 'android:maxSdkVersion="25"' || fail "GET_ACCOUNTS not capped below Android 8"
grep -A2 'android:name="android.permission.ACCESS_FINE_LOCATION"' "$MANIFEST" | grep -q 'android:maxSdkVersion="28"' || fail "ACCESS_FINE_LOCATION not capped to Android 9"
grep -A2 'android:name="android.permission.CHANGE_WIFI_STATE"' "$MANIFEST" | grep -q 'android:maxSdkVersion="28"' || fail "CHANGE_WIFI_STATE not capped to Android 9"
grep -A2 'android:name="android.permission.SYSTEM_ALERT_WINDOW"' "$MANIFEST" | grep -q 'android:maxSdkVersion="22"' || fail "SYSTEM_ALERT_WINDOW not capped to legacy pre-Marshmallow flashlight path"
! grep -q 'android.permission.BLUETOOTH_CONNECT' "$MANIFEST" || fail "Modern Nearby Devices permission unexpectedly advertised"
! grep -q 'android.permission.BLUETOOTH_SCAN' "$MANIFEST" || fail "Modern Bluetooth scan permission unexpectedly advertised"

# The only surviving overlay implementation is the legacy flashlight service,
# and the tracker must route Android M+ to the modern torch service instead.
grep -q 'WindowManager.LayoutParams.TYPE_SYSTEM_OVERLAY' "$LEGACY_FLASH" || fail "Legacy flashlight overlay path unexpectedly removed or drifted"
grep -q 'Build.VERSION.SDK_INT >= Build.VERSION_CODES.M' "$FLASH" || fail "Modern flashlight API boundary missing"
grep -q 'FlashServiceM.SERVICE_INTENT' "$FLASH" || fail "Modern flashlight service handoff missing"

# UPDATE_DEVICE_STATS is a platform-only signature/privileged/role capability,
# explicitly not for ordinary third-party apps. Publication source must not
# advertise it as if it were an obtainable customer-app capability.
! grep -q 'android.permission.UPDATE_DEVICE_STATS' "$MANIFEST" || fail "Platform-only UPDATE_DEVICE_STATS permission reintroduced"

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

# ADB-over-Wi-Fi is a legacy/root control, but Android 10+ still must not attempt
# ordinary-app direct Wi-Fi mutation. If Wi-Fi is off, hand the user to the system
# Wi-Fi panel; direct setWifiEnabled calls are retained only inside pre-Q paths.
grep -q 'Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && desiredState' "$ADB_WIFI" || fail "ADB wireless modern Wi-Fi preflight missing"
grep -q 'Settings.Panel.ACTION_WIFI' "$ADB_WIFI" || fail "ADB wireless modern Wi-Fi panel handoff missing"
grep -q 'Build.VERSION.SDK_INT < Build.VERSION_CODES.Q' "$ADB_WIFI" || fail "ADB wireless legacy Wi-Fi restore is not pre-Q bounded"
grep -q 'wifiManager.setWifiEnabled(true)' "$ADB_WIFI" || fail "ADB wireless legacy Wi-Fi enable path unexpectedly removed"
grep -q 'wifiManager.setWifiEnabled(false)' "$ADB_WIFI" || fail "ADB wireless legacy Wi-Fi restore path unexpectedly removed"

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

# Both notification rows must select notification RemoteViews styling.
grep -q 'STATUS_BAR_WIDGET_ID_2' "$WIDGET_SETTING" || fail "Second notification row constant missing"
grep -Fq '(widgetId == STATUS_BAR_WIDGET_ID) || (widgetId == STATUS_BAR_WIDGET_ID_2)' "$WIDGET_SETTING" || fail "Second notification row is not classified as notification"

echo "PASS: modern radio/privacy/provider static contract"
