package com.painless.pc.tracker;

import android.app.Activity;
import android.app.NotificationManager;
import android.content.Intent;
import android.content.SharedPreferences;
import android.media.AudioManager;
import android.media.session.MediaSession;
import android.media.session.PlaybackState;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.view.KeyEvent;

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

    if ("battery_info".equals(probe)) {
      new BatteryTracker(15, appPrefs).toggleState(this);
      return;
    }

    if ("volume_toggle".equals(probe)) {
      final AudioManager audio = (AudioManager) getSystemService(AUDIO_SERVICE);
      final int before = audio == null ? -1 : audio.getRingerMode();
      boolean policyAccess = false;
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
        final NotificationManager notification =
            (NotificationManager) getSystemService(NOTIFICATION_SERVICE);
        policyAccess = notification != null && notification.isNotificationPolicyAccessGranted();
      }
      boolean threw = false;
      String error = "";
      int after = before;
      boolean restoreThrew = false;
      int restored = before;
      if (audio != null) {
        final VolumeTracker tracker = new VolumeTracker(10, appPrefs);
        tracker.init(appPrefs);
        try {
          tracker.toggleState(this);
        } catch (Throwable t) {
          threw = true;
          error = t.getClass().getName() + ":" + String.valueOf(t.getMessage());
        }
        after = audio.getRingerMode();
        if (after != before) {
          try {
            audio.setRingerMode(before);
          } catch (Throwable t) {
            restoreThrew = true;
          }
        }
        restored = audio.getRingerMode();
      }
      qaPrefs.edit()
          .putInt("volume_before", before)
          .putInt("volume_after", after)
          .putInt("volume_restored", restored)
          .putBoolean("volume_policy_access", policyAccess)
          .putBoolean("volume_threw", threw)
          .putBoolean("volume_restore_threw", restoreThrew)
          .putString("volume_error", error)
          .commit();
      finish();
      return;
    }

    if ("media_transport".equals(probe)) {
      qaPrefs.edit()
          .putInt("media_play_pause_count", 0)
          .putInt("media_play_count", 0)
          .putInt("media_pause_count", 0)
          .putInt("media_next_count", 0)
          .putInt("media_prev_count", 0)
          .putBoolean("media_session_supported", Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP)
          .commit();
      if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) {
        finish();
        return;
      }

      final MediaSession session = new MediaSession(this, "PublicationMediaTransportProbe");
      session.setCallback(new MediaSession.Callback() {
        @Override
        public boolean onMediaButtonEvent(Intent mediaButtonIntent) {
          final KeyEvent event = mediaButtonIntent == null ? null :
              (KeyEvent) mediaButtonIntent.getParcelableExtra(Intent.EXTRA_KEY_EVENT);
          if (event != null && event.getAction() == KeyEvent.ACTION_DOWN) {
            final SharedPreferences.Editor edit = qaPrefs.edit();
            if (event.getKeyCode() == KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE) {
              edit.putInt("media_play_pause_count",
                  qaPrefs.getInt("media_play_pause_count", 0) + 1);
            } else if (event.getKeyCode() == KeyEvent.KEYCODE_MEDIA_NEXT) {
              edit.putInt("media_next_count", qaPrefs.getInt("media_next_count", 0) + 1);
            } else if (event.getKeyCode() == KeyEvent.KEYCODE_MEDIA_PREVIOUS) {
              edit.putInt("media_prev_count", qaPrefs.getInt("media_prev_count", 0) + 1);
            }
            edit.commit();
          }
          return true;
        }

        @Override
        public void onPlay() {
          qaPrefs.edit()
              .putInt("media_play_count", qaPrefs.getInt("media_play_count", 0) + 1)
              .putInt("media_play_pause_count",
                  qaPrefs.getInt("media_play_pause_count", 0) + 1)
              .commit();
        }

        @Override
        public void onPause() {
          qaPrefs.edit()
              .putInt("media_pause_count", qaPrefs.getInt("media_pause_count", 0) + 1)
              .putInt("media_play_pause_count",
                  qaPrefs.getInt("media_play_pause_count", 0) + 1)
              .commit();
        }
      });
      final long actions = PlaybackState.ACTION_PLAY_PAUSE |
          PlaybackState.ACTION_PLAY | PlaybackState.ACTION_PAUSE |
          PlaybackState.ACTION_SKIP_TO_NEXT | PlaybackState.ACTION_SKIP_TO_PREVIOUS;
      session.setPlaybackState(new PlaybackState.Builder()
          .setActions(actions)
          .setState(PlaybackState.STATE_PLAYING, 0, 1.0f)
          .build());
      session.setActive(true);

      new MediaPlayPause(18, appPrefs).toggleState(this);
      new MediaNext(19, appPrefs).toggleState(this);
      new MediaPrev(20, appPrefs).toggleState(this);

      new Handler().postDelayed(new Runnable() {
        @Override
        public void run() {
          session.setActive(false);
          session.release();
          finish();
        }
      }, 2000);
      return;
    }

    finish();
  }
}
