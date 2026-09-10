#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MANIFEST="$ROOT/AndroidManifest.xml"
WIFI="$ROOT/src/com/painless/pc/tracker/WifiStateTracker.java"
BT="$ROOT/src/com/painless/pc/tracker/BluetoothTracker.java"
BT_DISCOVERY="$ROOT/src/com/painless/pc/tracker/BluetoothDiscoveryTracker.java"
BT_HOTSPOT="$ROOT/src/com/painless/pc/tracker/BluetoothHotspotTracker.java"
PROVIDER="$ROOT/src/com/painless/pc/FileProvider.java"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

# Modern installs must not advertise legacy Bluetooth, account-list, or location
# permissions for user-mediated controls / explicitly visible account sync /
# optional SSID decoration.
grep -A2 'android:name="android.permission.BLUETOOTH"' "$MANIFEST" | grep -q 'android:maxSdkVersion="30"' || fail "BLUETOOTH not capped to Android 11"
grep -A2 'android:name="android.permission.BLUETOOTH_ADMIN"' "$MANIFEST" | grep -q 'android:maxSdkVersion="30"' || fail "BLUETOOTH_ADMIN not capped to Android 11"
grep -A2 'android:name="android.permission.GET_ACCOUNTS"' "$MANIFEST" | grep -q 'android:maxSdkVersion="25"' || fail "GET_ACCOUNTS not capped below Android 8"
grep -A2 'android:name="android.permission.ACCESS_FINE_LOCATION"' "$MANIFEST" | grep -q 'android:maxSdkVersion="28"' || fail "ACCESS_FINE_LOCATION not capped to Android 9"
! grep -q 'android.permission.BLUETOOTH_CONNECT' "$MANIFEST" || fail "Modern Nearby Devices permission unexpectedly advertised"
! grep -q 'android.permission.BLUETOOTH_SCAN' "$MANIFEST" || fail "Modern Bluetooth scan permission unexpectedly advertised"

# Wi-Fi control on Android 10+ must be truthful/user-mediated and SSID identity
# must degrade without location/nearby permission instead of prompting.
grep -q 'Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q' "$WIFI" || fail "Wi-Fi modern API boundary missing"
grep -q 'Settings.Panel.ACTION_WIFI' "$WIFI" || fail "Wi-Fi modern system panel missing"
grep -q 'Build.VERSION.SDK_INT < Build.VERSION_CODES.Q' "$WIFI" || fail "SSID access is not bounded to pre-Android-10"
grep -q 'wifiManager.getConnectionInfo().getSSID()' "$WIFI" || fail "Legacy SSID path unexpectedly removed"
grep -q 'catch (SecurityException e)' "$WIFI" || fail "Wi-Fi protected access lacks SecurityException degradation"

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

echo "PASS: modern radio/privacy/provider static contract"
