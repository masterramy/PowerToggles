#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RECEIVER="$ROOT/src/com/painless/pc/PluginUpdateReceiver.java"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

# PluginUpdateReceiver remains exported for deliberate Tasker/Locale/plugin
# interoperability. Its externally supplied broadcasts may update only the
# cached state/count of an already-active saved plugin and request a widget
# redraw; they must never become a direct execution surface.
grep -q 'TASK_COMPLETE_INTENT' "$RECEIVER" || fail "Tasker completion action missing"
grep -q 'FIRE_SETTING_INTENT' "$RECEIVER" || fail "Locale fire-setting action missing"
grep -q 'PLUGIN_STATE_CHANGED_INTENT' "$RECEIVER" || fail "Plugin state-change action missing"
grep -q '!PluginDB.get(context).isActive(varId)' "$RECEIVER" || fail "Receiver no longer requires an already-active saved plugin"
grep -q 'plugin.setChangedState(context, newState, count)' "$RECEIVER" || fail "Receiver state-cache update path missing"
grep -q 'PluginDB.get(context).setState(varId, newState, count)' "$RECEIVER" || fail "Receiver persistent state-cache update path missing"
grep -q 'PCWidgetActivity.partialUpdateAllWidgets(context)' "$RECEIVER" || fail "Receiver redraw path missing"

! grep -q '\.startActivity(' "$RECEIVER" || fail "Exported plugin receiver launches an Activity"
! grep -q '\.startService(' "$RECEIVER" || fail "Exported plugin receiver starts a Service"
! grep -q '\.startForegroundService(' "$RECEIVER" || fail "Exported plugin receiver starts a foreground Service"
! grep -q '\.sendBroadcast(' "$RECEIVER" || fail "Exported plugin receiver sends a downstream broadcast"
! grep -q 'requestStateChange' "$RECEIVER" || fail "Exported plugin receiver reaches tracker execution API"
! grep -q '\.getIntent()' "$RECEIVER" || fail "Exported plugin receiver reads executable plugin intent"

echo "PASS: exported plugin receiver remains state-cache/redraw only"
