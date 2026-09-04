package com.painless.pc.tracker;

import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.provider.Settings;

import com.painless.pc.R;
import com.painless.pc.singleton.Globals;

public final class UsbTetherTracker extends AbstractTracker {

  private static final String CHANGE_ACTION = "android.net.conn.TETHER_STATE_CHANGED";

  @Override
  public String getChangeAction() {
    return CHANGE_ACTION;
  }

  public UsbTetherTracker(int trackerId, SharedPreferences pref) {
    super(trackerId, pref, getTriImageConfig(R.drawable.icon_toggle_usb));
  }

  @Override
  public void onActualStateChange(Context context, Intent intent) {
    setCurrentState(context, STATE_UNKNOWN);
  }

  @Override
  public int getActualState(Context context) {
    // Current ordinary apps do not have a stable public API for the system USB
    // tethering switch across OEMs. Keep the state unknown rather than infer it
    // via hidden ConnectivityManager methods.
    return STATE_UNKNOWN;
  }

  @Override
  protected void requestStateChange(Context context, boolean desiredState) {
    Globals.startIntent(context,
        new Intent(Settings.ACTION_TETHER_SETTINGS)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
  }
}
