package com.painless.pc.tracker;

import android.content.Intent;
import android.content.SharedPreferences;
import android.provider.Settings;

import com.painless.pc.R;

/**
 * Compatibility representation for historical controls that modern ToggleBay
 * deliberately no longer exposes as toggles. Persisted/imported tracker IDs
 * remain readable, but they render as neutral actions and open the relevant
 * Android settings surface instead of pretending to change system state.
 */
public final class LegacySettingsAction extends AbstractCommand {

  private static final String TETHER_SETTINGS_ACTION = "android.settings.TETHER_SETTINGS";
  private static final String WIFI_PANEL_ACTION = "android.settings.panel.action.WIFI";

  public LegacySettingsAction(int trackerId, SharedPreferences pref) {
    super(trackerId, pref, iconFor(trackerId));
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

  private static int iconFor(int trackerId) {
    switch (trackerId) {
      case 0: return R.drawable.icon_toggle_hotspot;
      case 1: return R.drawable.icon_toggle_gprs;
      case 3: return R.drawable.icon_toggle_wifi;
      case 5: return R.drawable.icon_toggle_gps_2;
      case 6: return R.drawable.icon_toggle_bluetooth;
      case 8: return R.drawable.icon_toggle_airplane;
      case 11: return R.drawable.icon_toggle_gprs_4g;
      case 12: return R.drawable.icon_toggle_usb;
      case 22: return R.drawable.icon_toggle_bluetooth_discovery;
      case 24: return R.drawable.icon_toggle_nfc;
      case 26: return R.drawable.icon_toggle_bluetooth_tether;
      default: return R.drawable.icon_toggle_settings;
    }
  }

  @Override
  public Intent getIntent() {
    switch (trackerId) {
      case 0:
      case 12:
        return new Intent(TETHER_SETTINGS_ACTION);
      case 1:
        return new Intent(Settings.ACTION_DATA_USAGE_SETTINGS);
      case 3:
        return new Intent(WIFI_PANEL_ACTION);
      case 5:
        return new Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS);
      case 6:
      case 22:
      case 26:
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
