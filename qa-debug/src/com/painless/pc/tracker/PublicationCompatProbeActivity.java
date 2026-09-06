package com.painless.pc.tracker;

import android.app.Activity;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Bundle;

import com.painless.pc.singleton.Globals;

/**
 * Debug-only publication compatibility probe. Excluded from release builds.
 * Invokes exact shipping tracker paths while preserving/restoring QA-only setup.
 */
public final class PublicationCompatProbeActivity extends Activity {

  private static final String PROBE_PREFS = "publication_compat_probe";
  private static final String HAD_WAKE_NOTIFY_PREF = "had_wake_notify_pref";
  private static final String ORIGINAL_WAKE_NOTIFY_PREF = "original_wake_notify_pref";

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
    final SharedPreferences qaPrefs = getSharedPreferences(PROBE_PREFS, MODE_PRIVATE);

    if ("screen_on_prepare_notification".equals(probe)) {
      qaPrefs.edit()
          .putBoolean(HAD_WAKE_NOTIFY_PREF, appPrefs.contains("wake_lock_notify_hidden"))
          .putBoolean(ORIGINAL_WAKE_NOTIFY_PREF,
              appPrefs.getBoolean("wake_lock_notify_hidden", true))
          .commit();
      // Shipping PriorityService shows its foreground notification when this
      // legacy "hidden" preference is false. Exercise that exact branch.
      appPrefs.edit().putBoolean("wake_lock_notify_hidden", false).commit();
      finish();
      return;
    }

    if ("screen_on_restore_notification_pref".equals(probe)) {
      final boolean hadOriginal = qaPrefs.getBoolean(HAD_WAKE_NOTIFY_PREF, false);
      final boolean original = qaPrefs.getBoolean(ORIGINAL_WAKE_NOTIFY_PREF, true);
      final SharedPreferences.Editor editor = appPrefs.edit();
      if (hadOriginal) {
        editor.putBoolean("wake_lock_notify_hidden", original);
      } else {
        editor.remove("wake_lock_notify_hidden");
      }
      editor.commit();
      finish();
      return;
    }

    if ("screen_on_enable".equals(probe)) {
      new ScreenOnTracker(13, appPrefs).requestStateChange(this, true);
      finish();
      return;
    }

    if ("screen_on_disable".equals(probe)) {
      new ScreenOnTracker(13, appPrefs).requestStateChange(this, false);
      finish();
      return;
    }

    if ("bluetooth_discovery_state".equals(probe)) {
      final int stateValue = new BluetoothDiscoveryTracker(22, appPrefs).getActualState(this);
      qaPrefs.edit().putInt("bluetooth_discovery_state", stateValue).commit();
      finish();
      return;
    }

    if ("bluetooth_discovery_toggle".equals(probe)) {
      new BluetoothDiscoveryTracker(22, appPrefs).toggleState(this);
      return;
    }

    finish();
  }
}
