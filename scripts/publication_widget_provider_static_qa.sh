#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MANIFEST="$ROOT/AndroidManifest.xml"
PROVIDER="$ROOT/src/com/painless/pc/PCWidgetActivity.java"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

# Android's AppWidget host/service discovers the provider through this receiver.
# A non-exported receiver is still visible to package-manager queries but is not
# registered by AppWidgetService as a bindable provider on current Android, which
# leaves real widget hosts unable to bind it. Keep only the framework widget
# action here and export the provider as required by the AppWidget contract.
grep -Fq '<receiver android:name=".PCWidgetActivity" android:exported="true"' "$MANIFEST" \
  || fail "AppWidget provider is not exported for framework host binding"
grep -Fq '<action android:name="android.appwidget.action.APPWIDGET_UPDATE" />' "$MANIFEST" \
  || fail "AppWidget update filter missing"
grep -Fq 'android:name="android.appwidget.provider" android:resource="@xml/widgetprovider"' "$MANIFEST" \
  || fail "AppWidget provider metadata missing"

# Retired Buzzpia integration accepted caller-controlled filesystem paths. Its
# manifest actions must remain absent; the source-level denial remains as defense
# in depth for any in-process or future exposure regression.
! grep -Fq 'com.buzzpia.aqua.appwidget.' "$MANIFEST" \
  || fail "Retired Buzzpia widget IPC reintroduced in manifest"
grep -Fq 'private static final String BUZZPIA_ACTION = "com.buzzpia.aqua.appwidget.";' "$PROVIDER" \
  || fail "Retired Buzzpia denial prefix missing"
grep -Fq 'action.startsWith(BUZZPIA_ACTION)' "$PROVIDER" \
  || fail "Retired Buzzpia actions are not denied"

echo "PASS: AppWidget provider is framework-bindable with retired custom IPC denied"
