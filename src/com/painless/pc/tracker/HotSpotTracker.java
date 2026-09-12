package com.painless.pc.tracker;

import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.net.wifi.WifiManager;
import android.provider.Settings;

import com.painless.pc.R;
import com.painless.pc.singleton.Globals;

public final class HotSpotTracker extends AbstractDoubleClickTracker {

  private static final String CHANGE_ACTION = "android.net.wifi.WIFI_AP_STATE_CHANGED";
  private static final String TETHER_SETTINGS_ACTION = "android.settings.TETHER_SETTINGS";

  @Override
  public String getChangeAction() {
    return CHANGE_ACTION;
  }

  public HotSpotTracker(int trackerId, SharedPreferences pref) {
    super(trackerId, pref, getTriImageConfig(R.drawable.icon_toggle_hotspot));
  }

  @Override
  public int getActualState(Context context) {
    // Ordinary Play apps no longer have a supported public API for directly
    // reading/changing the user's Wi-Fi hotspot state. Do not fake a state.
    return STATE_UNKNOWN;
  }

  @Override
  protected void requestStateChange(Context context, boolean desiredState) {
    openTetherSettings(context);
  }

  @Override
  public void onActualStateChange(Context context, Intent intent) {
    setCurrentState(context, STATE_UNKNOWN);
  }

  private static void openTetherSettings(Context context) {
    Intent target = new Intent(TETHER_SETTINGS_ACTION).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
    if (target.resolveActivity(context.getPackageManager()) == null) {
      target = new Intent(Settings.ACTION_WIRELESS_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
    }
    Globals.startIntent(context, target);
  }

  /**
   * Retained only for binary/source compatibility with historical callers.
   * A modern ordinary app must not infer hotspot state through hidden APIs.
   */
  public static int getFiveState(WifiManager wifiManager) {
    return STATE_UNKNOWN;
  }

  @Override
  Intent getDCIntent(Context context) {
    Intent target = new Intent(TETHER_SETTINGS_ACTION);
    return target.resolveActivity(context.getPackageManager()) != null
        ? target : new Intent(Settings.ACTION_WIRELESS_SETTINGS);
  }
}
