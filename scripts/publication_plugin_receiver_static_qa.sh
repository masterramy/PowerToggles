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

# Reject the Android component/IPC execution families that could turn an
# externally callable state-update receiver into a confused-deputy launcher.
! grep -Eq '\.(startActivity|startActivities|startService|startForegroundService|bindService|sendBroadcast|sendOrderedBroadcast|sendBroadcastAsUser|sendOrderedBroadcastAsUser|startIntentSender)\(' "$RECEIVER" \
  || fail "Exported plugin receiver reaches an Android execution/IPC API"
! grep -q 'requestStateChange' "$RECEIVER" || fail "Exported plugin receiver reaches tracker execution API"
! grep -q '\.getIntent()' "$RECEIVER" || fail "Exported plugin receiver reads executable plugin intent"
! grep -q 'PendingIntent' "$RECEIVER" || fail "Exported plugin receiver gains a PendingIntent execution path"
! grep -q 'Runtime.getRuntime' "$RECEIVER" || fail "Exported plugin receiver gains process execution"
! grep -q 'ProcessBuilder' "$RECEIVER" || fail "Exported plugin receiver gains process execution"

echo "PASS: exported plugin receiver remains state-cache/redraw only"
