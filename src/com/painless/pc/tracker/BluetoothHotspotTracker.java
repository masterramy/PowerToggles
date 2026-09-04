package com.painless.pc.tracker;

import android.bluetooth.BluetoothAdapter;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.provider.Settings;

import com.painless.pc.R;
import com.painless.pc.singleton.Globals;

public class BluetoothHotspotTracker extends AbstractTracker {

  public BluetoothHotspotTracker(int trackerId, SharedPreferences pref) {
    super(trackerId, pref, getTriImageConfig(R.drawable.icon_toggle_bluetooth_tether));
  }

  @Override
  public int getActualState(Context context) {
    BluetoothAdapter adapter = BluetoothAdapter.getDefaultAdapter();
    if (adapter == null) {
      return STATE_UNKNOWN;
    }
    try {
      if (!adapter.isEnabled()) {
        return STATE_DISABLED;
      }
    } catch (SecurityException e) {
      return STATE_UNKNOWN;
    }
    // There is no supported ordinary-app public API for the Bluetooth PAN
    // tethering switch. Do not read it through hidden profile methods.
    return STATE_UNKNOWN;
  }

  @Override
  protected void requestStateChange(Context context, boolean desiredState) {
    Globals.startIntent(context,
        new Intent(Settings.ACTION_TETHER_SETTINGS)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
  }

  @Override
  public boolean shouldProxy(Context context) {
    return true;
  }
}
