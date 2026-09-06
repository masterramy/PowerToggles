package com.painless.pc.tracker;

import android.app.Activity;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Bundle;
import android.provider.Settings;

import com.painless.pc.singleton.Globals;

/**
 * Debug-only Gate 2A runtime probe. This activity is excluded from release builds.
 * It invokes the real tracker implementations so CI can prove fidelity classes
 * without adding customer-facing QA hooks to the restored candidate.
 */
public final class Gate2aProbeActivity extends Activity {

  private static final String PROBE_PREFS = "gate2a_probe";
  private static final String ORIGINAL_ROTATION = "original_rotation";

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

    finish();
  }
}
