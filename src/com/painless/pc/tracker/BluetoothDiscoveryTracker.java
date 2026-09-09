package com.painless.pc.tracker;

import android.bluetooth.BluetoothAdapter;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Build;
import android.provider.Settings;

import com.painless.pc.R;
import com.painless.pc.singleton.Globals;

public class BluetoothDiscoveryTracker extends AbstractTracker {

  public BluetoothDiscoveryTracker(int trackerId, SharedPreferences pref) {
    super(trackerId, pref, getTriImageConfig(R.drawable.icon_toggle_bluetooth_discovery));
  }

  @Override
  public int getActualState(Context context) {
    // Android 12+ protects scan/discoverability state with Nearby Devices
    // permissions. Avoid adding that sensitive runtime permission solely for
    // this legacy convenience toggle; use the platform Bluetooth UI instead.
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
      return STATE_UNKNOWN;
    }

    final BluetoothAdapter adapter = BluetoothAdapter.getDefaultAdapter();
    if (adapter == null) {
      return STATE_UNKNOWN;
    }
    try {
      return adapter.getScanMode() == BluetoothAdapter.SCAN_MODE_CONNECTABLE_DISCOVERABLE
          ? STATE_ENABLED : STATE_DISABLED;
    } catch (SecurityException ignored) {
      return STATE_UNKNOWN;
    }
  }

  @Override
  public void toggleState(Context context) {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
      Globals.startIntent(context, new Intent(Settings.ACTION_BLUETOOTH_SETTINGS));
      return;
    }

    Intent discoverableIntent = new Intent(BluetoothAdapter.ACTION_REQUEST_DISCOVERABLE);
    discoverableIntent.putExtra(BluetoothAdapter.EXTRA_DISCOVERABLE_DURATION, 120);
    try {
      Globals.startIntent(context, discoverableIntent);
    } catch (SecurityException ignored) {
      Globals.startIntent(context, new Intent(Settings.ACTION_BLUETOOTH_SETTINGS));
    }
  }

  @Override
  protected void requestStateChange(Context context, boolean desiredState) { }

  @Override
  public boolean shouldProxy(Context context) {
    return true;
  }
}
