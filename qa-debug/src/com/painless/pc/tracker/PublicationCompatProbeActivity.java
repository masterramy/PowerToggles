package com.painless.pc.tracker;

import android.app.Activity;
import android.content.ContentResolver;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Bundle;
import android.provider.Settings;

import com.painless.pc.singleton.Globals;

/**
 * Debug-only publication compatibility probe. Excluded from release builds.
 * Invokes exact shipping tracker paths while preserving/restoring QA-only setup.
 */
public final class PublicationCompatProbeActivity extends Activity {

  private static final String PROBE_PREFS = "publication_compat_probe";
  private static final String HAD_WAKE_NOTIFY_PREF = "had_wake_notify_pref";
  private static final String ORIGINAL_WAKE_NOTIFY_PREF = "original_wake_notify_pref";
  private static final String HAD_ROTATION_PROMPT_PREF = "had_rotation_prompt_pref";
  private static final String ORIGINAL_ROTATION_PROMPT_PREF = "original_rotation_prompt_pref";
  private static final String HAD_ROTATION_NOTIFY_PREF = "had_rotation_notify_pref";
  private static final String ORIGINAL_ROTATION_NOTIFY_PREF = "original_rotation_notify_pref";
  private static final String ORIGINAL_ROTATION = "original_rotation_lock_rotation";
  private static final String ORIGINAL_USER_ROTATION = "original_user_rotation";
  private static final String ORIGINAL_MASTER_SYNC = "original_master_sync";
  private static final String HAD_PULSE_SETTING = "had_pulse_setting";
  private static final String ORIGINAL_PULSE_SETTING = "original_pulse_setting";

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

    if ("sync_prepare".equals(probe)) {
      qaPrefs.edit().putBoolean(ORIGINAL_MASTER_SYNC,
          ContentResolver.getMasterSyncAutomatically()).commit();
      finish();
      return;
    }

    if ("sync_toggle".equals(probe)) {
      final boolean before = ContentResolver.getMasterSyncAutomatically();
      new SyncStateTracker(2, appPrefs).requestStateChange(this, !before);
      finish();
      return;
    }

    if ("sync_state".equals(probe)) {
      qaPrefs.edit().putBoolean("master_sync_state",
          ContentResolver.getMasterSyncAutomatically()).commit();
      finish();
      return;
    }

    if ("sync_restore".equals(probe)) {
      new SyncStateTracker(2, appPrefs).requestStateChange(this,
          qaPrefs.getBoolean(ORIGINAL_MASTER_SYNC, true));
      finish();
      return;
    }

    if ("rotation_setting_prepare".equals(probe)) {
      final int originalAuto = Settings.System.getInt(
          getContentResolver(), Settings.System.ACCELEROMETER_ROTATION, 1);
      final int originalUser = Settings.System.getInt(
          getContentResolver(), Settings.System.USER_ROTATION, 0);
      qaPrefs.edit()
          .putInt(ORIGINAL_ROTATION, originalAuto)
          .putInt(ORIGINAL_USER_ROTATION, originalUser)
          .putInt("rotation_setting_before", originalUser)
          .commit();
      finish();
      return;
    }

    if ("rotation_setting_toggle".equals(probe)) {
      final int before = Settings.System.getInt(
          getContentResolver(), Settings.System.USER_ROTATION, 0);
      final int desired = before == 0 ? 1 : 0;
      final boolean wroteUser = Settings.System.putInt(
          getContentResolver(), Settings.System.USER_ROTATION, desired);
      final boolean wroteAuto = Settings.System.putInt(
          getContentResolver(), Settings.System.ACCELEROMETER_ROTATION, 0);
      final int after = Settings.System.getInt(
          getContentResolver(), Settings.System.USER_ROTATION, -1);
      qaPrefs.edit()
          .putInt("rotation_setting_after", after)
          .putBoolean("rotation_setting_user_write", wroteUser)
          .putBoolean("rotation_setting_auto_write", wroteAuto)
          .putBoolean("rotation_setting_changed", after == desired && after != before)
          .commit();
      finish();
      return;
    }

    if ("rotation_setting_restore".equals(probe)) {
      final int originalUser = qaPrefs.getInt(ORIGINAL_USER_ROTATION, 0);
      final int originalAuto = qaPrefs.getInt(ORIGINAL_ROTATION, 1);
      Settings.System.putInt(getContentResolver(), Settings.System.USER_ROTATION, originalUser);
      Settings.System.putInt(getContentResolver(), Settings.System.ACCELEROMETER_ROTATION, originalAuto);
      qaPrefs.edit()
          .putInt("rotation_setting_restored", Settings.System.getInt(
              getContentResolver(), Settings.System.USER_ROTATION, -1))
          .putInt("rotation_auto_restored", Settings.System.getInt(
              getContentResolver(), Settings.System.ACCELEROMETER_ROTATION, -1))
          .commit();
      finish();
      return;
    }

    if ("rotation_lock_prepare".equals(probe)) {
      qaPrefs.edit()
          .putInt(ORIGINAL_ROTATION, Settings.System.getInt(
              getContentResolver(), Settings.System.ACCELEROMETER_ROTATION, 1))
          .putInt(ORIGINAL_USER_ROTATION, Settings.System.getInt(
              getContentResolver(), Settings.System.USER_ROTATION, 0))
          .putBoolean(HAD_ROTATION_PROMPT_PREF, appPrefs.contains("rotation_lock_prompt"))
          .putBoolean(ORIGINAL_ROTATION_PROMPT_PREF,
              appPrefs.getBoolean("rotation_lock_prompt", true))
          .putBoolean(HAD_ROTATION_NOTIFY_PREF,
              appPrefs.contains("rotation_lock_notify_hidden"))
          .putBoolean(ORIGINAL_ROTATION_NOTIFY_PREF,
              appPrefs.getBoolean("rotation_lock_notify_hidden", true))
          .commit();
      appPrefs.edit()
          .putBoolean("rotation_lock_prompt", false)
          .putBoolean("rotation_lock_notify_hidden", false)
          .commit();
      Settings.System.putInt(getContentResolver(),
          Settings.System.ACCELEROMETER_ROTATION, 1);
      finish();
      return;
    }

    if ("rotation_lock_enable".equals(probe)) {
      new RotationLockTracker(38, appPrefs).toggleState(this);
      finish();
      return;
    }

    if ("rotation_lock_disable".equals(probe)) {
      new RotationLockTracker(38, appPrefs).toggleState(this);
      finish();
      return;
    }

    if ("rotation_lock_restore".equals(probe)) {
      Settings.System.putInt(getContentResolver(), Settings.System.USER_ROTATION,
          qaPrefs.getInt(ORIGINAL_USER_ROTATION, 0));
      Settings.System.putInt(getContentResolver(), Settings.System.ACCELEROMETER_ROTATION,
          qaPrefs.getInt(ORIGINAL_ROTATION, 1));
      final SharedPreferences.Editor editor = appPrefs.edit();
      if (qaPrefs.getBoolean(HAD_ROTATION_PROMPT_PREF, false)) {
        editor.putBoolean("rotation_lock_prompt",
            qaPrefs.getBoolean(ORIGINAL_ROTATION_PROMPT_PREF, true));
      } else {
        editor.remove("rotation_lock_prompt");
      }
      if (qaPrefs.getBoolean(HAD_ROTATION_NOTIFY_PREF, false)) {
        editor.putBoolean("rotation_lock_notify_hidden",
            qaPrefs.getBoolean(ORIGINAL_ROTATION_NOTIFY_PREF, true));
      } else {
        editor.remove("rotation_lock_notify_hidden");
      }
      editor.commit();
      finish();
      return;
    }

    if ("rotation_picker_prepare".equals(probe)) {
      qaPrefs.edit()
          .putBoolean(HAD_ROTATION_PROMPT_PREF, appPrefs.contains("rotation_lock_prompt"))
          .putBoolean(ORIGINAL_ROTATION_PROMPT_PREF,
              appPrefs.getBoolean("rotation_lock_prompt", true))
          .commit();
      appPrefs.edit().putBoolean("rotation_lock_prompt", true).commit();
      finish();
      return;
    }

    if ("rotation_picker_open".equals(probe)) {
      new RotationLockTracker(38, appPrefs).toggleState(this);
      return;
    }

    if ("rotation_picker_restore".equals(probe)) {
      final SharedPreferences.Editor editor = appPrefs.edit();
      if (qaPrefs.getBoolean(HAD_ROTATION_PROMPT_PREF, false)) {
        editor.putBoolean("rotation_lock_prompt",
            qaPrefs.getBoolean(ORIGINAL_ROTATION_PROMPT_PREF, true));
      } else {
        editor.remove("rotation_lock_prompt");
      }
      editor.commit();
      finish();
      return;
    }

    if ("pulse_prepare".equals(probe)) {
      final String original = Settings.System.getString(
          getContentResolver(), "notification_light_pulse");
      final SharedPreferences.Editor editor = qaPrefs.edit()
          .putBoolean(HAD_PULSE_SETTING, original != null);
      if (original != null) {
        editor.putString(ORIGINAL_PULSE_SETTING, original);
      } else {
        editor.remove(ORIGINAL_PULSE_SETTING);
      }
      editor.commit();
      finish();
      return;
    }

    if ("pulse_toggle".equals(probe)) {
      final int before = Settings.System.getInt(
          getContentResolver(), "notification_light_pulse", 0);
      new PulseLightTracker(40, appPrefs).requestStateChange(this, before == 0);
      qaPrefs.edit().putInt("pulse_after", Settings.System.getInt(
          getContentResolver(), "notification_light_pulse", 0)).commit();
      finish();
      return;
    }

    if ("pulse_restore".equals(probe)) {
      Settings.System.putString(getContentResolver(), "notification_light_pulse",
          qaPrefs.getBoolean(HAD_PULSE_SETTING, false)
              ? qaPrefs.getString(ORIGINAL_PULSE_SETTING, null) : null);
      finish();
      return;
    }

    if ("home".equals(probe)) {
      new HomeCommand(43, appPrefs).toggleState(this);
      return;
    }

    finish();
  }
}
