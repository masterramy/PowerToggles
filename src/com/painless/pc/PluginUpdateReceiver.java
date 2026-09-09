package com.painless.pc;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.net.Uri;
import android.text.TextUtils;

import com.painless.pc.singleton.Globals;
import com.painless.pc.singleton.PluginDB;
import com.painless.pc.singleton.SettingStorage;
import com.painless.pc.tracker.AbstractTracker;
import com.painless.pc.tracker.PluginTracker;

public class PluginUpdateReceiver extends BroadcastReceiver {

  private static final String TASK_COMPLETE_INTENT = "net.dinglisch.android.tasker.ACTION_TASK_COMPLETE";
  private static final String FIRE_SETTING_INTENT = "com.twofortyfouram.locale.intent.action.FIRE_SETTING";
  private static final String PLUGIN_STATE_CHANGED_INTENT = "com.painless.pc.ACTION_STATE_CHANGED";
  private static final int MAX_VAR_ID_LENGTH = 256;
  private static final int MAX_COUNT = 1000000;

  @Override
  public void onReceive(Context context, Intent intent) {
    if (intent == null) {
      return;
    }

    String action = intent.getAction();
    if (!TASK_COMPLETE_INTENT.equals(action)
        && !FIRE_SETTING_INTENT.equals(action)
        && !PLUGIN_STATE_CHANGED_INTENT.equals(action)) {
      // This receiver is exported for deliberate Tasker/Locale/plugin interoperability.
      // Explicit broadcasts with unrelated actions must not fall through into state mutation.
      return;
    }

    if (intent.getBooleanExtra("refresh", false)) {
      PCWidgetActivity.partialUpdateAllWidgets(context);
      return;
    }

    String varId;
    boolean newState;
    if (TASK_COMPLETE_INTENT.equals(action)) {
      Uri data = intent.getData();
      if (data == null || !"task".equals(data.getScheme())
          || TextUtils.isEmpty(data.getSchemeSpecificPart())) {
        return;
      }
      varId = Globals.TASKER_KEY_PREFIX + data.getSchemeSpecificPart();
      newState = PluginDB.get(context).getState(varId);
    } else if (FIRE_SETTING_INTENT.equals(action)) {
      String taskerVar = intent.getStringExtra("varID");
      if (TextUtils.isEmpty(taskerVar)) {
        return;
      }
      varId = Globals.TASKER_KEY_PREFIX + taskerVar;
      newState = Boolean.parseBoolean(intent.getStringExtra("state"));
    } else {
      varId = intent.getStringExtra("varID");
      newState = intent.getBooleanExtra("state", false);
      String pluginID = intent.getStringExtra(Intent.EXTRA_UID);
      if (!TextUtils.isEmpty(varId) && !TextUtils.isEmpty(pluginID)) {
        varId = varId + '-' + pluginID;
      }
    }

    if (TextUtils.isEmpty(varId) || varId.length() > MAX_VAR_ID_LENGTH
        || !PluginDB.get(context).isActive(varId)) {
      return;
    }

    AbstractTracker tracker = SettingStorage.getTracker("pl_" + varId, context, Globals.getAppPrefs(context));
    if (tracker instanceof PluginTracker) {
      int count = PluginDB.get(context).getCount(varId);
      try {
        count = Integer.parseInt(intent.getStringExtra("count"));
      } catch (Exception e) {
        // Keep the current stored count.
      }
      if (count < 0) {
        count = 0;
      } else if (count > MAX_COUNT) {
        count = MAX_COUNT;
      }

      PluginTracker plugin = (PluginTracker) tracker;
      plugin.setChangedState(context, newState, count);
      PluginDB.get(context).setState(varId, newState, count);
      PCWidgetActivity.partialUpdateAllWidgets(context);
    }
  }
}
