package com.painless.pc.tracker;

import android.content.Intent;
import android.content.SharedPreferences;
import android.provider.Settings;

import com.painless.pc.R;

/**
 * Compatibility representation for historical controls that ToggleBay no
 * longer exposes as direct toggles. Persisted/imported IDs stay readable, but
 * render as neutral actions and open the relevant Android Settings surface.
 */
public final class LegacySettingsAction extends AbstractCommand {

  public LegacySettingsAction(int trackerId, SharedPreferences pref) {
    super(trackerId, pref, R.drawable.icon_prefs);
  }

  public static boolean isLegacySettingsOnlyId(int trackerId) {
    switch (trackerId) {
      case 0:  // Hotspot
      case 1:  // Mobile data
      case 3:  // Wi-Fi
      case 5:  // Location
      case 6:  // Bluetooth
      case 8:  // Airplane mode
      case 11: // Mobile/network mode
      case 12: // USB tether
      case 22: // Bluetooth discovery
      case 24: // NFC
      case 26: // Bluetooth tether
        return true;
      default:
        return false;
    }
  }

  @Override
  public String getLabel(String[] labelArray) {
    // Some historical translations still name the old destination rather than
    // saying "Settings". The gear marker is deliberately locale-independent:
    // a legacy Wi-Fi/Bluetooth/etc. button is now visibly an action/route, never
    // an ON/OFF control, even before every historical translation is refreshed.
    return super.getLabel(labelArray) + " ⚙";
  }

  @Override
  public Intent getIntent() {
    switch (trackerId) {
      case 0:
      case 12:
      case 26:
        return new Intent(Settings.ACTION_WIRELESS_SETTINGS);
      case 1:
        return new Intent(Settings.ACTION_DATA_USAGE_SETTINGS);
      case 3:
        return new Intent(Settings.ACTION_WIFI_SETTINGS);
      case 5:
        return new Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS);
      case 6:
      case 22:
        return new Intent(Settings.ACTION_BLUETOOTH_SETTINGS);
      case 8:
        return new Intent(Settings.ACTION_AIRPLANE_MODE_SETTINGS);
      case 11:
        return new Intent(Settings.ACTION_DATA_ROAMING_SETTINGS);
      case 24:
        return new Intent(Settings.ACTION_NFC_SETTINGS);
      default:
        return new Intent(Settings.ACTION_SETTINGS);
    }
  }
}
