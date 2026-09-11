#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MANIFEST="$ROOT/AndroidManifest.xml"
SETUP="$ROOT/src/com/painless/pc/settings/TaskerToggleSetup.java"
REFRESH="$ROOT/src/com/painless/pc/settings/TaskerRefresh.java"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

# Locale/Tasker setup surfaces are intentionally exported interoperability entry
# points. They must remain action-gated and must treat all cross-app extras as
# untrusted so malformed/unparcelable values cannot crash the app process.
grep -Fq '<activity android:name=".settings.TaskerToggleSetup" android:exported="true"' "$MANIFEST" || fail "TaskerToggleSetup export contract changed"
grep -Fq '<activity android:name=".settings.TaskerRefresh" android:exported="true"' "$MANIFEST" || fail "TaskerRefresh export contract changed"
grep -Fq 'com.twofortyfouram.locale.intent.action.EDIT_SETTING' "$MANIFEST" || fail "Locale/Tasker edit-setting action missing"

grep -Fq 'EDIT_SETTING_ACTION.equals(launchIntent.getAction())' "$SETUP" || fail "TaskerToggleSetup no longer action-gates external launch"
grep -Fq 'private static String boundedExtra(Intent intent, String key)' "$SETUP" || fail "TaskerToggleSetup bounded extra reader missing"
grep -Fq 'try {' "$SETUP" || fail "TaskerToggleSetup extra reader is not guarded"
grep -Fq 'value = intent.getStringExtra(key);' "$SETUP" || fail "TaskerToggleSetup guarded string read missing"
grep -Fq 'catch (RuntimeException e)' "$SETUP" || fail "Malformed Tasker setup extras can escape into an app-process crash"
grep -Fq 'return null;' "$SETUP" || fail "Malformed Tasker setup extras do not fail closed"
grep -Fq 'value.length() <= MAX_INPUT_CHARS' "$SETUP" || fail "Tasker setup input length bound missing"

# TaskerRefresh consumes no caller-controlled payload, but it is exported and must
# still reject launches outside the documented Locale/Tasker EDIT_SETTING action.
grep -Fq 'TaskerToggleSetup.EDIT_SETTING_ACTION.equals(launchIntent.getAction())' "$REFRESH" || fail "TaskerRefresh no longer action-gates external launch"
grep -Fq 'setResult(RESULT_CANCELED);' "$REFRESH" || fail "TaskerRefresh invalid launch does not fail closed"

echo "PASS: exported Tasker/Locale ingress static contract"
