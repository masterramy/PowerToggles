#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MANIFEST="$ROOT/AndroidManifest.xml"
PROVIDER="$ROOT/src/com/painless/pc/PCWidgetActivity.java"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

# AppWidgetManager delivers provider lifecycle broadcasts explicitly. The provider
# no longer has a supported cross-app custom IPC surface, so it must stay
# non-exported rather than allowing arbitrary apps to force redraw work.
grep -Fq '<receiver android:name=".PCWidgetActivity" android:exported="false"' "$MANIFEST" \
  || fail "AppWidget provider is externally exported"
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

echo "PASS: AppWidget provider remains framework-only and non-exported"
