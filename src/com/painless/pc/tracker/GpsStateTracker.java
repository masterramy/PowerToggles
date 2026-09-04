package com.painless.pc.tracker;

import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.location.LocationManager;
import android.os.Build;
import android.provider.Settings;

import com.painless.pc.R;
import com.painless.pc.singleton.Globals;

public final class GpsStateTracker extends AbstractTracker {

  public static final String KEY_SOURCES = "gps_sources";
  public static final String DEFAULT_SOURCES = "2,-1";

  private static final String CHANGE_ACTION = "android.location.PROVIDERS_CHANGED";

  public GpsStateTracker(int trackerId, SharedPreferences pref) {
    super(trackerId, pref, getTriImageConfig(
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT
            ? R.drawable.icon_toggle_gps_2 : R.drawable.icon_toggle_gps));
  }

  @Override
  public String getChangeAction() {
    return CHANGE_ACTION;
  }

  @Override
  public int getActualState(Context context) {
    LocationManager manager =
        (LocationManager) context.getSystemService(Context.LOCATION_SERVICE);
    if (manager == null) {
      return STATE_UNKNOWN;
    }
    try {
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
        return manager.isLocationEnabled() ? STATE_ENABLED : STATE_DISABLED;
      }
      boolean gps = manager.isProviderEnabled(LocationManager.GPS_PROVIDER);
      boolean network = manager.isProviderEnabled(LocationManager.NETWORK_PROVIDER);
      return (gps || network) ? STATE_ENABLED : STATE_DISABLED;
    } catch (Throwable e) {
      return STATE_UNKNOWN;
    }
  }

  @Override
  protected void requestStateChange(Context context, boolean desiredState) {
    launchIntent(context);
  }

  void launchIntent(Context context) {
    Globals.startIntent(context,
        new Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
  }
}
