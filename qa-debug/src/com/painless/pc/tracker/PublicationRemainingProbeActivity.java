package com.painless.pc.tracker;

import android.app.Activity;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Bundle;
import android.os.Handler;

import com.painless.pc.notify.NotifyStatus;
import com.painless.pc.singleton.Globals;

/**
 * Debug-only publication probe for remaining G10 controls. Excluded from release builds.
 * Invokes the exact shipping tracker classes and preserves/restores QA-touched preferences.
 */
public final class PublicationRemainingProbeActivity extends Activity {

  private static final String PROBE_PREFS = "publication_remaining_probe";
  private static final String STATUS_KEY = "status_bar_widget";
  private static final String TWO_ROW_KEY = "nofity_two_row";

  @Override
  protected void onCreate(Bundle state) {
    super.onCreate(state);
    runProbe(getIntent().getStringExtra("probe"));
  }

  @Override
  protected void onNewIntent(Intent intent) {
    super.onNewIntent(intent);
    setIntent(intent);
    runProbe(intent.getStringExtra("probe"));
  }

  private void runProbe(String probe) {
    final SharedPreferences appPrefs = Globals.getAppPrefs(this);
    final SharedPreferences qaPrefs = getSharedPreferences(PROBE_PREFS, MODE_PRIVATE);

    if ("screen_lock".equals(probe)) {
      new LockScreenToggle(25, appPrefs).toggleState(this);
      return;
    }

    if ("sync_now".equals(probe)) {
      final SyncNowTracker tracker = new SyncNowTracker(28, appPrefs);
      tracker.requestStateChange(this, true);
      qaPrefs.edit().putInt("sync_now_immediate_state", tracker.getActualState(this)).commit();
      new Handler().postDelayed(new Runnable() {
        @Override
        public void run() {
          qaPrefs.edit().putInt("sync_now_final_state", tracker.getActualState(
              PublicationRemainingProbeActivity.this)).commit();
          finish();
        }
      }, 4500);
      return;
    }

    if ("notify_prepare".equals(probe)) {
      qaPrefs.edit()
          .putBoolean("had_status", appPrefs.contains(STATUS_KEY))
          .putBoolean("original_status", NotifyStatus.isEnabled(this))
          .putBoolean("had_two_row", appPrefs.contains(TWO_ROW_KEY))
          .putBoolean("original_two_row", NotifyStatus.isTwoRowEnabled(this))
          .commit();
      finish();
      return;
    }

    if ("notify_widget_toggle".equals(probe)) {
      final NotifyWidgetTracker tracker = new NotifyWidgetTracker(32, appPrefs);
      final boolean before = NotifyStatus.isEnabled(this);
      tracker.requestStateChange(this, !before);
      qaPrefs.edit()
          .putBoolean("notify_widget_before", before)
          .putBoolean("notify_widget_after", NotifyStatus.isEnabled(this))
          .commit();
      finish();
      return;
    }

    if ("two_row_toggle".equals(probe)) {
      final TwoRowTracker tracker = new TwoRowTracker(34, appPrefs);
      final boolean before = NotifyStatus.isTwoRowEnabled(this);
      tracker.requestStateChange(this, !before);
      qaPrefs.edit()
          .putBoolean("two_row_before", before)
          .putBoolean("two_row_after", NotifyStatus.isTwoRowEnabled(this))
          .commit();
      finish();
      return;
    }

    if ("notify_restore".equals(probe)) {
      final boolean originalStatus = qaPrefs.getBoolean("original_status", false);
      final boolean originalTwoRow = qaPrefs.getBoolean("original_two_row", false);
      NotifyStatus.setEnabled(this, originalStatus);
      NotifyStatus.setTwoRowEnabled(this, originalTwoRow);

      final SharedPreferences.Editor editor = appPrefs.edit();
      if (!qaPrefs.getBoolean("had_status", false)) {
        editor.remove(STATUS_KEY);
      }
      if (!qaPrefs.getBoolean("had_two_row", false)) {
        editor.remove(TWO_ROW_KEY);
      }
      editor.commit();

      qaPrefs.edit()
          .putBoolean("restored_status", NotifyStatus.isEnabled(this))
          .putBoolean("restored_two_row", NotifyStatus.isTwoRowEnabled(this))
          .commit();
      finish();
      return;
    }

    finish();
  }
}
