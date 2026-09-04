package com.painless.pc.tracker;

import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.provider.Settings;

import com.painless.pc.R;
import com.painless.pc.singleton.Globals;

public class GprsStateTracker extends AbstractDoubleClickTracker {

  public GprsStateTracker(int trackerId, SharedPreferences pref) {
    super(trackerId, pref, getTriImageConfig(R.drawable.icon_toggle_gprs));
  }

  @Override
  public void onActualStateChange(Context context, Intent intent) {
    setCurrentState(context, STATE_UNKNOWN);
  }

  @Override
  public int getActualState(Context context) {
    return getStaticState(context);
  }

  @Override
  protected void requestStateChange(Context context, boolean desiredState) {
    showSettings(context);
  }

  public static int getStaticState(Context context) {
    // There is no supported public API for an ordinary Play app to determine
    // whether the user's mobile-data switch is enabled across current devices.
    return STATE_UNKNOWN;
  }

  @Override
  Intent getDCIntent(Context context) {
    return new Intent(Settings.ACTION_DATA_USAGE_SETTINGS);
  }

  @Override
  public boolean shouldProxy(Context context) {
    return true;
  }

  static void showSettings(Context context) {
    Globals.startIntent(context,
        new Intent(Settings.ACTION_DATA_USAGE_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
  }
}
