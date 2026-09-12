package com.painless.pc.tracker;

import android.content.ContentResolver;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.provider.Settings;

import com.painless.pc.R;
import com.painless.pc.singleton.Globals;

public final class AirplaneTracker extends AbstractTracker {

  @Override
  public String getChangeAction() {
    return Intent.ACTION_AIRPLANE_MODE_CHANGED;
  }

  public AirplaneTracker(int trackerId, SharedPreferences pref) {
    super(trackerId, pref, getTriImageConfig(R.drawable.icon_toggle_airplane));
  }

  @Override
  public int getActualState(Context context) {
    return isEnabled(context.getContentResolver()) ? STATE_ENABLED : STATE_DISABLED;
  }

  @Override
  protected void requestStateChange(Context context, boolean desiredState) {
    // Current ordinary Play apps cannot directly toggle airplane mode. Always
    // hand control to the user's system settings rather than attempting root or
    // Global-setting mutation and then pretending success.
    Globals.startIntent(context,
        new Intent(Settings.ACTION_AIRPLANE_MODE_SETTINGS)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
  }

  @Override
  public boolean shouldProxy(Context context) {
    return true;
  }

  private static boolean isEnabled(ContentResolver resolver) {
    return Settings.Global.getInt(resolver, Settings.Global.AIRPLANE_MODE_ON, 0) != 0;
  }
}
