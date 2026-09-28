package com.painless.pc.tracker;

import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;

import com.painless.pc.R;
import com.painless.pc.TrackerManager;

/**
 * Compatibility wrapper for historical tracker IDs whose modern Android
 * behavior is settings navigation rather than a direct toggle.
 *
 * The historical numeric ID, layout position, and icon remain stable so saved
 * widgets/imports continue to load. The runtime semantics are intentionally
 * command-like: neutral appearance, explicit Settings label, and a user-mediated
 * system surface instead of fake ON/OFF state.
 */
public final class SettingsActionTracker extends AbstractCommand {

  private final String mLabel;
  private final Intent mPrimaryIntent;
  private final Intent mFallbackIntent;

  private SettingsActionTracker(int trackerId, SharedPreferences pref, int iconId,
      String label, Intent primaryIntent, Intent fallbackIntent) {
    super(trackerId, pref, iconId);
    mLabel = label + " Settings";
    mPrimaryIntent = primaryIntent;
    mFallbackIntent = fallbackIntent;
  }

  public static boolean isSettingsOnlyLegacyId(int trackerId) {
    switch (trackerId) {
      case 0:  // Hotspot
      case 1:  // Mobile data
      case 3:  // Wi-Fi
      case 5:  // Location
      case 6:  // Bluetooth
      case 8:  // Airplane mode
      case 11: // Mobile network / network mode
      case 12: // USB tether
      case 22: // Bluetooth discovery
      case 24: // NFC
      case 26: // Bluetooth tether
        return true;
      default:
        return false;
    }
  }

  public static SettingsActionTracker create(
      int trackerId, Context context, SharedPreferences pref) {
    if (!isSettingsOnlyLegacyId(trackerId)) {
      throw new IllegalArgumentException("Not a settings-only legacy tracker: " + trackerId);
    }

    // Reuse the historical tracker's first icon so existing visual layouts do
    // not silently change identity. Only the interaction/state semantics change.
    AbstractTracker historical = TrackerManager.getTracker(trackerId, pref);
    int iconId = historical.buttonConfig[1];
    String label = context.getResources().getStringArray(R.array.tracker_names)[trackerId];

    final Intent primary;
    Intent fallback = null;
    switch (trackerId) {
      case 0:
      case 12:
      case 26:
        primary = new Intent("android.settings.TETHER_SETTINGS");
        fallback = new Intent(android.provider.Settings.ACTION_WIRELESS_SETTINGS);
        break;
      case 1:
        primary = new Intent(android.provider.Settings.ACTION_DATA_USAGE_SETTINGS);
        break;
      case 3:
        primary = new Intent(android.provider.Settings.ACTION_WIFI_SETTINGS);
        break;
      case 5:
        primary = new Intent(android.provider.Settings.ACTION_LOCATION_SOURCE_SETTINGS);
        break;
      case 6:
      case 22:
        primary = new Intent(android.provider.Settings.ACTION_BLUETOOTH_SETTINGS);
        break;
      case 8:
        primary = new Intent(android.provider.Settings.ACTION_AIRPLANE_MODE_SETTINGS);
        break;
      case 11:
        primary = new Intent(android.provider.Settings.ACTION_DATA_ROAMING_SETTINGS);
        break;
      case 24:
        primary = new Intent(android.provider.Settings.ACTION_NFC_SETTINGS);
        break;
      default:
        throw new IllegalStateException("Unhandled settings-only tracker: " + trackerId);
    }

    primary.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
    if (fallback != null) {
      fallback.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
    }
    return new SettingsActionTracker(trackerId, pref, iconId, label, primary, fallback);
  }

  @Override
  public String getLabel(String[] labelArray) {
    return mLabel;
  }

  @Override
  public Intent getIntent() {
    if (mContext != null && mPrimaryIntent.resolveActivity(mContext.getPackageManager()) == null) {
      return mFallbackIntent;
    }
    return mPrimaryIntent;
  }
}
