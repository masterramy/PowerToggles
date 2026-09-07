package com.painless.pc.tracker;

import android.app.Activity;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.SharedPreferences;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.view.KeyEvent;

import com.painless.pc.singleton.Globals;

/** Debug-only publication probe for the remaining MediaButton edge paths. */
public final class PublicationMediaEdgeProbeActivity extends Activity {

  private static final String PROBE_PREFS = "publication_media_edge_probe";
  private static final String ACTION_EXPLICIT_PLAYER = "com.painless.pc.qa.MEDIA_EDGE_PLAYER";

  private final int[][] explicitCounts = new int[3][3]; // down, up, matched-downTime up
  private final long[] explicitDownTimes = new long[] {-1L, -1L, -1L};
  private BroadcastReceiver explicitReceiver;

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

    explicitReceiver = new BroadcastReceiver() {
      @Override
      public void onReceive(Context context, Intent intent) {
        KeyEvent event = intent == null ? null :
            (KeyEvent) intent.getParcelableExtra(Intent.EXTRA_KEY_EVENT);
        if (event == null) {
          return;
        }
        int index = indexForKeyCode(event.getKeyCode());
        if (index < 0) {
          return;
        }
        if (event.getAction() == KeyEvent.ACTION_DOWN) {
          explicitCounts[index][0]++;
          explicitDownTimes[index] = event.getDownTime();
        } else if (event.getAction() == KeyEvent.ACTION_UP) {
          explicitCounts[index][1]++;
          if (explicitDownTimes[index] == event.getDownTime()) {
            explicitCounts[index][2]++;
          }
        }
      }
    };

    IntentFilter filter = new IntentFilter(ACTION_EXPLICIT_PLAYER);
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
      registerReceiver(explicitReceiver, filter, Context.RECEIVER_NOT_EXPORTED);
    } else {
      registerReceiver(explicitReceiver, filter);
    }

    boolean threw = false;
    String error = "";
    try {
      String playerUri = new Intent(ACTION_EXPLICIT_PLAYER).toUri(0);
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
        try {
          unregisterReceiver(explicitReceiver);
        } catch (Throwable ignored) {
        }
        restorePlayerPreference(appPrefs, hadPlayer, originalPlayer);
        qaPrefs.edit()
            .putBoolean("explicit_completed", true)
            .putBoolean("explicit_threw", probeThrew)
            .putString("explicit_error", probeError)
            .putInt("explicit_play_pause_down", explicitCounts[0][0])
            .putInt("explicit_play_pause_up", explicitCounts[0][1])
            .putInt("explicit_play_pause_matched", explicitCounts[0][2])
            .putInt("explicit_next_down", explicitCounts[1][0])
            .putInt("explicit_next_up", explicitCounts[1][1])
            .putInt("explicit_next_matched", explicitCounts[1][2])
            .putInt("explicit_prev_down", explicitCounts[2][0])
            .putInt("explicit_prev_up", explicitCounts[2][1])
            .putInt("explicit_prev_matched", explicitCounts[2][2])
            .putBoolean("explicit_pref_restored",
                playerPreferenceMatches(appPrefs, hadPlayer, originalPlayer))
            .commit();
        finish();
      }
    }, 1000L);
  }

  private static int indexForKeyCode(int keyCode) {
    if (keyCode == KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE) return 0;
    if (keyCode == KeyEvent.KEYCODE_MEDIA_NEXT) return 1;
    if (keyCode == KeyEvent.KEYCODE_MEDIA_PREVIOUS) return 2;
    return -1;
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
