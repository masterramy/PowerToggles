package com.painless.pc.tracker;

import android.app.Activity;
import android.content.ComponentName;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Bundle;
import android.os.Handler;

import com.painless.pc.singleton.Globals;

/** Debug-only publication probe for the remaining MediaButton edge paths. */
public final class PublicationMediaEdgeProbeActivity extends Activity {

  private static final String PROBE_PREFS = "publication_media_edge_probe";
  private static final String ACTION_EXPLICIT_PLAYER = "com.painless.pc.qa.MEDIA_EDGE_PLAYER";

  @Override
  protected void onCreate(Bundle state) {
    super.onCreate(state);
    String probe = getIntent() == null ? null : getIntent().getStringExtra("probe");
    if ("no_player".equals(probe)) {
      runNoPlayerProbe();
    } else if ("explicit_player".equals(probe)) {
      runExplicitPlayerProbe();
    } else {
      finish();
    }
  }

  private void runNoPlayerProbe() {
    final SharedPreferences appPrefs = Globals.getAppPrefs(this);
    final SharedPreferences qaPrefs = getSharedPreferences(PROBE_PREFS, MODE_PRIVATE);
    final boolean hadPlayer = appPrefs.contains(MediaButton.KEY_PLAYER_INTENT);
    final String originalPlayer = appPrefs.getString(MediaButton.KEY_PLAYER_INTENT, "");

    // Exercise the exact modern no-configured-player branch without creating a
    // MediaSession in this process. The isolated workflow uses a fresh emulator
    // and records media_session state before this activity starts.
    appPrefs.edit().remove(MediaButton.KEY_PLAYER_INTENT).commit();
    boolean threw = false;
    String error = "";
    try {
      new MediaPlayPause(18, appPrefs).toggleState(this);
      new MediaNext(19, appPrefs).toggleState(this);
      new MediaPrev(20, appPrefs).toggleState(this);
    } catch (Throwable t) {
      threw = true;
      error = t.getClass().getName() + ":" + String.valueOf(t.getMessage());
    } finally {
      restorePlayerPreference(appPrefs, hadPlayer, originalPlayer);
    }

    qaPrefs.edit()
        .putBoolean("no_player_completed", true)
        .putBoolean("no_player_threw", threw)
        .putString("no_player_error", error)
        .putBoolean("no_player_pref_restored",
            playerPreferenceMatches(appPrefs, hadPlayer, originalPlayer))
        .commit();
    finish();
  }

  private void runExplicitPlayerProbe() {
    final SharedPreferences appPrefs = Globals.getAppPrefs(this);
    final SharedPreferences qaPrefs = getSharedPreferences(PROBE_PREFS, MODE_PRIVATE);
    final boolean hadPlayer = appPrefs.contains(MediaButton.KEY_PLAYER_INTENT);
    final String originalPlayer = appPrefs.getString(MediaButton.KEY_PLAYER_INTENT, "");

    // Reset only the explicit-player counters. The debug-only manifest receiver
    // persists each exact ordered-broadcast event, so receiver delivery survives
    // Activity lifecycle timing and proves MediaButton's configured Intent path.
    qaPrefs.edit()
        .putBoolean("explicit_completed", false)
        .putBoolean("explicit_threw", false)
        .putString("explicit_error", "")
        .putInt("explicit_play_pause_down", 0)
        .putInt("explicit_play_pause_up", 0)
        .putInt("explicit_play_pause_matched", 0)
        .putInt("explicit_next_down", 0)
        .putInt("explicit_next_up", 0)
        .putInt("explicit_next_matched", 0)
        .putInt("explicit_prev_down", 0)
        .putInt("explicit_prev_up", 0)
        .putInt("explicit_prev_matched", 0)
        .putLong("explicit_play_pause_down_time", -1L)
        .putLong("explicit_next_down_time", -1L)
        .putLong("explicit_prev_down_time", -1L)
        .commit();

    boolean threw = false;
    String error = "";
    try {
      Intent playerIntent = new Intent(ACTION_EXPLICIT_PLAYER)
          .setComponent(new ComponentName(this, PublicationMediaEdgeReceiver.class));
      String playerUri = playerIntent.toUri(0);
      appPrefs.edit().putString(MediaButton.KEY_PLAYER_INTENT, playerUri).commit();
      new MediaPlayPause(18, appPrefs).toggleState(this);
      new MediaNext(19, appPrefs).toggleState(this);
      new MediaPrev(20, appPrefs).toggleState(this);
    } catch (Throwable t) {
      threw = true;
      error = t.getClass().getName() + ":" + String.valueOf(t.getMessage());
    }

    final boolean probeThrew = threw;
    final String probeError = error;
    new Handler().postDelayed(new Runnable() {
      @Override
      public void run() {
        restorePlayerPreference(appPrefs, hadPlayer, originalPlayer);
        qaPrefs.edit()
            .putBoolean("explicit_completed", true)
            .putBoolean("explicit_threw", probeThrew)
            .putString("explicit_error", probeError)
            .putBoolean("explicit_pref_restored",
                playerPreferenceMatches(appPrefs, hadPlayer, originalPlayer))
            .commit();
        finish();
      }
    }, 1000L);
  }

  private static void restorePlayerPreference(SharedPreferences prefs,
      boolean hadPlayer, String originalPlayer) {
    SharedPreferences.Editor editor = prefs.edit();
    if (hadPlayer) {
      editor.putString(MediaButton.KEY_PLAYER_INTENT, originalPlayer);
    } else {
      editor.remove(MediaButton.KEY_PLAYER_INTENT);
    }
    editor.commit();
  }

  private static boolean playerPreferenceMatches(SharedPreferences prefs,
      boolean hadPlayer, String originalPlayer) {
    if (prefs.contains(MediaButton.KEY_PLAYER_INTENT) != hadPlayer) {
      return false;
    }
    return !hadPlayer || originalPlayer.equals(
        prefs.getString(MediaButton.KEY_PLAYER_INTENT, ""));
  }
}
