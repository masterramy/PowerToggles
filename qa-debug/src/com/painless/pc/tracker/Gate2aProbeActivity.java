package com.painless.pc.tracker;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.media.AudioManager;
import android.os.Bundle;
import android.provider.Settings;

import com.painless.pc.R;
import com.painless.pc.TrackerManager;
import com.painless.pc.singleton.Globals;
import com.painless.pc.util.SettingsDecoder;

/**
 * Debug-only Gate 2A runtime probe. This activity is excluded from release builds.
 * It invokes the real tracker implementations so CI can prove fidelity classes
 * without adding customer-facing QA hooks to the restored candidate.
 */
public final class Gate2aProbeActivity extends Activity {

  private static final String PROBE_PREFS = "gate2a_probe";
  private static final String ORIGINAL_ROTATION = "original_rotation";
  private static final String ORIGINAL_MEDIA_VOLUME = "original_media_volume";

  @Override
  protected void onCreate(Bundle state) {
    super.onCreate(state);
    runProbe(getIntent());
  }

  @Override
  protected void onNewIntent(Intent intent) {
    super.onNewIntent(intent);
    setIntent(intent);
    runProbe(intent);
  }

  private void runProbe(Intent intent) {
    final String probe = intent.getStringExtra("probe");
    final SharedPreferences appPrefs = Globals.getAppPrefs(this);

    if ("legacy_truthful_actions".equals(probe)) {
      final int[] retiredIds = new int[] {0, 1, 3, 5, 6, 8, 11, 12, 22, 24, 26};
      final String[] expectedActions = new String[] {
          Settings.ACTION_WIRELESS_SETTINGS,
          Settings.ACTION_DATA_USAGE_SETTINGS,
          Settings.ACTION_WIFI_SETTINGS,
          Settings.ACTION_LOCATION_SOURCE_SETTINGS,
          Settings.ACTION_BLUETOOTH_SETTINGS,
          Settings.ACTION_AIRPLANE_MODE_SETTINGS,
          Settings.ACTION_DATA_ROAMING_SETTINGS,
          Settings.ACTION_WIRELESS_SETTINGS,
          Settings.ACTION_BLUETOOTH_SETTINGS,
          Settings.ACTION_NFC_SETTINGS,
          Settings.ACTION_WIRELESS_SETTINGS
      };
      final String[] labels = getResources().getStringArray(R.array.tracker_names);
      boolean allLegacyActions = true;
      boolean allNeutral = true;
      boolean allExpectedIntents = true;
      boolean allSettingsLabels = true;
      boolean keyTargetsResolve = true;

      for (int i = 0; i < retiredIds.length; i++) {
        final AbstractTracker tracker = TrackerManager.getTracker(retiredIds[i], appPrefs);
        if (!(tracker instanceof LegacySettingsAction)) {
          allLegacyActions = false;
          continue;
        }
        allNeutral &= tracker.buttonConfig.length == 2;
        final Intent target = ((LegacySettingsAction) tracker).getIntent();
        allExpectedIntents &= expectedActions[i].equals(target.getAction());
        allSettingsLabels &= tracker.getLabel(labels).contains("Settings");

        // The physical complaint was specifically Wi-Fi, Location, Bluetooth,
        // and mobile data. Prove those four system destinations resolve on API 36.
        final int id = retiredIds[i];
        if (id == 1 || id == 3 || id == 5 || id == 6) {
          keyTargetsResolve &= target.resolveActivity(getPackageManager()) != null;
        }
      }

      final String defaultTrackers = new SettingsDecoder("{}").getTrackerDef();
      final boolean defaultListOk = "2,4,7,9,10,13,15".equals(defaultTrackers);
      final boolean pass = allLegacyActions && allNeutral && allExpectedIntents
          && allSettingsLabels && keyTargetsResolve && defaultListOk;

      getSharedPreferences(PROBE_PREFS, MODE_PRIVATE).edit()
          .putBoolean("legacy_truthful_actions_pass", pass)
          .putBoolean("legacy_all_actions", allLegacyActions)
          .putBoolean("legacy_all_neutral", allNeutral)
          .putBoolean("legacy_expected_intents", allExpectedIntents)
          .putBoolean("legacy_settings_labels", allSettingsLabels)
          .putBoolean("legacy_key_targets_resolve", keyTargetsResolve)
          .putBoolean("legacy_default_list_ok", defaultListOk)
          .putString("legacy_default_list", defaultTrackers)
          .commit();
      finish();
      return;
    }

    if ("battery".equals(probe)) {
      final int battery = Globals.getBattery(this);
      getSharedPreferences(PROBE_PREFS, MODE_PRIVATE).edit()
          .putInt("battery_percent", battery)
          .putBoolean("battery_valid", battery >= 0 && battery <= 100)
          .commit();
      finish();
      return;
    }

    if ("wifi".equals(probe)) {
      new WifiStateTracker(3, appPrefs).requestStateChange(this, true);
      // The API-36 Wi-Fi panel can be translucent enough for this no-history
      // debug activity to survive underneath it. Finish the probe explicitly so
      // the next fidelity launch cannot be delivered into a stale activity.
      finish();
      return;
    }

    if ("bluetooth_enable".equals(probe)) {
      new BluetoothTracker(6, appPrefs).requestStateChange(this, true);
      return;
    }

    if ("bluetooth_disable".equals(probe)) {
      new BluetoothTracker(6, appPrefs).requestStateChange(this, false);
      return;
    }

    if ("hotspot_settings".equals(probe)) {
      new HotSpotTracker(0, appPrefs).requestStateChange(this, true);
      return;
    }

    if ("mobile_data_settings".equals(probe)) {
      new GprsStateTracker(1, appPrefs).requestStateChange(this, true);
      return;
    }

    if ("location_settings".equals(probe)) {
      new GpsStateTracker(5, appPrefs).requestStateChange(this, true);
      return;
    }

    if ("airplane_settings".equals(probe)) {
      new AirplaneTracker(8, appPrefs).requestStateChange(this, true);
      return;
    }

    if ("mobile_network_settings".equals(probe)) {
      new DataNetworkTracker(11, appPrefs).toggleState(this);
      return;
    }

    if ("usb_tether_settings".equals(probe)) {
      new UsbTetherTracker(12, appPrefs).requestStateChange(this, true);
      return;
    }

    if ("nfc_settings".equals(probe)) {
      new NfcStateTracker(24, appPrefs).requestStateChange(this, true);
      return;
    }

    if ("bluetooth_tether_settings".equals(probe)) {
      new BluetoothHotspotTracker(26, appPrefs).requestStateChange(this, true);
      return;
    }

    if ("brightness_toggle".equals(probe)) {
      final int beforeLevel = Settings.System.getInt(
          getContentResolver(), Settings.System.SCREEN_BRIGHTNESS, -1);
      final int beforeMode = Settings.System.getInt(
          getContentResolver(), Settings.System.SCREEN_BRIGHTNESS_MODE, -1);
      final BacklightTracker tracker = new BacklightTracker(7, appPrefs);
      tracker.getActualState(this);
      tracker.toggleState(this);
      final int afterLevel = Settings.System.getInt(
          getContentResolver(), Settings.System.SCREEN_BRIGHTNESS, -1);
      final int afterMode = Settings.System.getInt(
          getContentResolver(), Settings.System.SCREEN_BRIGHTNESS_MODE, -1);
      getSharedPreferences(PROBE_PREFS, MODE_PRIVATE).edit()
          .putInt("brightness_before", beforeLevel)
          .putInt("brightness_after", afterLevel)
          .putInt("brightness_mode_before", beforeMode)
          .putInt("brightness_mode_after", afterMode)
          .commit();
      finish();
      return;
    }

    if ("timeout_toggle".equals(probe)) {
      final int before = Settings.System.getInt(
          getContentResolver(), Settings.System.SCREEN_OFF_TIMEOUT, -1);
      final TimeoutTracker tracker = new TimeoutTracker(16, appPrefs);
      tracker.getActualState(this);
      tracker.toggleState(this);
      final int after = Settings.System.getInt(
          getContentResolver(), Settings.System.SCREEN_OFF_TIMEOUT, -1);
      getSharedPreferences(PROBE_PREFS, MODE_PRIVATE).edit()
          .putInt("timeout_before", before)
          .putInt("timeout_after", after)
          .commit();
      finish();
      return;
    }

    if ("auto_brightness_toggle".equals(probe)) {
      final int before = Settings.System.getInt(
          getContentResolver(), Settings.System.SCREEN_BRIGHTNESS_MODE, -1);
      final AutoBacklightTracker tracker = new AutoBacklightTracker(17, appPrefs);
      tracker.toggleState(this);
      final int after = Settings.System.getInt(
          getContentResolver(), Settings.System.SCREEN_BRIGHTNESS_MODE, -1);
      getSharedPreferences(PROBE_PREFS, MODE_PRIVATE).edit()
          .putInt("auto_brightness_before", before)
          .putInt("auto_brightness_after", after)
          .commit();
      finish();
      return;
    }

    if ("brightness_slider".equals(probe)) {
      new BrightnessSliderToggle(23, appPrefs).toggleState(this);
      return;
    }

    if ("autorotate_toggle".equals(probe)) {
      final int before = Settings.System.getInt(
          getContentResolver(), Settings.System.ACCELEROMETER_ROTATION, 0);
      getSharedPreferences(PROBE_PREFS, MODE_PRIVATE).edit()
          .putInt(ORIGINAL_ROTATION, before).commit();
      new AutoRotateTracker(9, appPrefs).requestStateChange(this, before == 0);
      final int after = Settings.System.getInt(
          getContentResolver(), Settings.System.ACCELEROMETER_ROTATION, 0);
      getSharedPreferences(PROBE_PREFS, MODE_PRIVATE).edit()
          .putInt("rotation_before", before)
          .putInt("rotation_after", after)
          .putBoolean("rotation_changed", before != after)
          .commit();
      finish();
      return;
    }

    if ("autorotate_restore".equals(probe)) {
      final SharedPreferences probePrefs = getSharedPreferences(PROBE_PREFS, MODE_PRIVATE);
      final int original = probePrefs.getInt(ORIGINAL_ROTATION, -1);
      if (original >= 0) {
        new AutoRotateTracker(9, appPrefs).requestStateChange(this, original != 0);
      }
      final int restored = Settings.System.getInt(
          getContentResolver(), Settings.System.ACCELEROMETER_ROTATION, 0);
      probePrefs.edit().putInt("rotation_restored", restored)
          .putBoolean("rotation_restore_ok", restored == original).commit();
      finish();
      return;
    }

    if ("media_volume_prepare".equals(probe)) {
      final AudioManager am = (AudioManager) getSystemService(Context.AUDIO_SERVICE);
      if (am != null) {
        final int original = am.getStreamVolume(AudioManager.STREAM_MUSIC);
        final int max = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC);
        final int baseline = Math.max(1, Math.min(max, Math.max(2, max / 2)));
        getSharedPreferences(PROBE_PREFS, MODE_PRIVATE).edit()
            .putInt(ORIGINAL_MEDIA_VOLUME, original)
            .putInt("media_volume_baseline", baseline).commit();
        am.setStreamVolume(AudioManager.STREAM_MUSIC, baseline, 0);
      }
      finish();
      return;
    }

    if ("media_volume_toggle".equals(probe)) {
      final AudioManager am = (AudioManager) getSystemService(Context.AUDIO_SERVICE);
      final int before = am == null ? -1 : am.getStreamVolume(AudioManager.STREAM_MUSIC);
      new MediaVolume(21, appPrefs).toggleState(this);
      final int after = am == null ? -1 : am.getStreamVolume(AudioManager.STREAM_MUSIC);
      getSharedPreferences(PROBE_PREFS, MODE_PRIVATE).edit()
          .putInt("media_volume_before", before)
          .putInt("media_volume_after", after).commit();
      finish();
      return;
    }

    if ("media_volume_restore_original".equals(probe)) {
      final AudioManager am = (AudioManager) getSystemService(Context.AUDIO_SERVICE);
      final SharedPreferences probePrefs = getSharedPreferences(PROBE_PREFS, MODE_PRIVATE);
      final int original = probePrefs.getInt(ORIGINAL_MEDIA_VOLUME, -1);
      if (am != null && original >= 0) {
        am.setStreamVolume(AudioManager.STREAM_MUSIC, original, 0);
      }
      final int restored = am == null ? -1 : am.getStreamVolume(AudioManager.STREAM_MUSIC);
      probePrefs.edit().putInt("media_volume_original_restored", restored)
          .putBoolean("media_volume_original_restore_ok", restored == original).commit();
      finish();
      return;
    }

    if ("volume_slider".equals(probe)) {
      new VolumeSliderToggle(27, appPrefs).toggleState(this);
      return;
    }

    if ("screen_light".equals(probe)) {
      new ScreenLightCommand(31, appPrefs).toggleState(this);
      return;
    }

    finish();
  }
}
