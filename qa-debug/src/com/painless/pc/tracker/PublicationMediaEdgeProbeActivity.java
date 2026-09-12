package com.painless.pc.tracker;

import android.app.Activity;
import android.content.BroadcastReceiver;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Bundle;
import android.os.Handler;
import android.os.SystemClock;
import android.view.KeyEvent;

import com.painless.pc.singleton.Globals;

/** Debug-only publication probe for the remaining MediaButton edge paths. */
public final class PublicationMediaEdgeProbeActivity extends Activity {

  private static final String PROBE_PREFS = "publication_media_edge_probe";
  private static final String ACTION_EXPLICIT_PLAYER = "com.painless.pc.qa.MEDIA_EDGE_PLAYER";
  private static final int EXPLICIT_DELIVERY_POLL_MS = 100;
  private static final int EXPLICIT_DELIVERY_MAX_POLLS = 50;

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

    resetExplicitEventCounters(qaPrefs);
    qaPrefs.edit()
        .putBoolean("explicit_completed", false)
        .putBoolean("explicit_threw", false)
        .putString("explicit_error", "")
        .putBoolean("explicit_uri_round_trip", false)
        .putBoolean("explicit_control_delivered", false)
        .putString("explicit_player_uri", "")
        .putString("explicit_parsed_component", "")
        .commit();

    try {
      final Intent playerIntent = new Intent(ACTION_EXPLICIT_PLAYER)
          .setComponent(new ComponentName(this, PublicationMediaEdgeReceiver.class));
      final String playerUri = playerIntent.toUri(0);
      final Intent parsedIntent = Intent.parseUri(playerUri, 0);
      final boolean uriRoundTrip = ACTION_EXPLICIT_PLAYER.equals(parsedIntent.getAction())
          && playerIntent.getComponent().equals(parsedIntent.getComponent());

      qaPrefs.edit()
          .putBoolean("explicit_uri_round_trip", uriRoundTrip)
          .putString("explicit_player_uri", playerUri)
          .putString("explicit_parsed_component",
              String.valueOf(parsedIntent.getComponent()))
          .commit();

      if (!uriRoundTrip) {
        throw new IllegalStateException("Configured-player Intent URI did not preserve action/component");
      }

      // Harness control: prove the exact parsed explicit Intent can reach the
      // debug-only manifest receiver before attributing any later zero delivery
      // to shipping MediaButton. The ordered-broadcast result receiver runs only
      // after the target chain has completed.
      long controlTime = SystemClock.uptimeMillis();
      Intent control = new Intent(parsedIntent).putExtra(
          Intent.EXTRA_KEY_EVENT,
          new KeyEvent(controlTime, controlTime, KeyEvent.ACTION_DOWN,
              KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE, 0));
      sendOrderedBroadcast(control, null, new BroadcastReceiver() {
        @Override
        public void onReceive(Context context, Intent intent) {
          boolean controlDelivered =
              qaPrefs.getInt("explicit_play_pause_down", 0) == 1;
          qaPrefs.edit()
              .putBoolean("explicit_control_delivered", controlDelivered)
              .commit();

          if (!controlDelivered) {
            completeExplicitProbe(appPrefs, qaPrefs, hadPlayer, originalPlayer,
                true, "QA_CONTROL_RECEIVER_NOT_DELIVERED");
            return;
          }

          // Remove the one control event. From this point onward every retained
          // count is attributable only to the unchanged shipping MediaButton path.
          resetExplicitEventCounters(qaPrefs);
          appPrefs.edit().putString(MediaButton.KEY_PLAYER_INTENT, playerUri).commit();

          // Do not nest the shipping ordered broadcasts inside this control
          // broadcast's result callback. Android may serialize ordered broadcasts
          // until this callback returns, which can make a timer observe zero
          // deliveries even though the target is healthy. Queue the shipping path
          // on the main loop so this result callback returns first.
          new Handler().post(new Runnable() {
            @Override
            public void run() {
              boolean threw = false;
              String error = "";
              try {
                new MediaPlayPause(18, appPrefs).toggleState(PublicationMediaEdgeProbeActivity.this);
                new MediaNext(19, appPrefs).toggleState(PublicationMediaEdgeProbeActivity.this);
                new MediaPrev(20, appPrefs).toggleState(PublicationMediaEdgeProbeActivity.this);
              } catch (Throwable t) {
                threw = true;
                error = t.getClass().getName() + ":" + String.valueOf(t.getMessage());
              }

              if (threw) {
                completeExplicitProbe(appPrefs, qaPrefs, hadPlayer, originalPlayer,
                    true, error);
                return;
              }

              waitForExplicitDelivery(appPrefs, qaPrefs, hadPlayer, originalPlayer,
                  0);
            }
          });
        }
      }, null, RESULT_OK, null, null);
    } catch (Throwable t) {
      completeExplicitProbe(appPrefs, qaPrefs, hadPlayer, originalPlayer,
          true, t.getClass().getName() + ":" + String.valueOf(t.getMessage()));
    }
  }

  private void waitForExplicitDelivery(final SharedPreferences appPrefs,
      final SharedPreferences qaPrefs, final boolean hadPlayer,
      final String originalPlayer, final int poll) {
    if (explicitDeliveryComplete(qaPrefs)) {
      completeExplicitProbe(appPrefs, qaPrefs, hadPlayer, originalPlayer,
          false, "");
      return;
    }

    if (poll >= EXPLICIT_DELIVERY_MAX_POLLS) {
      completeExplicitProbe(appPrefs, qaPrefs, hadPlayer, originalPlayer,
          false, "DELIVERY_TIMEOUT");
      return;
    }

    new Handler().postDelayed(new Runnable() {
      @Override
      public void run() {
        waitForExplicitDelivery(appPrefs, qaPrefs, hadPlayer, originalPlayer,
            poll + 1);
      }
    }, EXPLICIT_DELIVERY_POLL_MS);
  }

  private static boolean explicitDeliveryComplete(SharedPreferences prefs) {
    return exactDeliveryFor(prefs, "explicit_play_pause")
        && exactDeliveryFor(prefs, "explicit_next")
        && exactDeliveryFor(prefs, "explicit_prev");
  }

  private static boolean exactDeliveryFor(SharedPreferences prefs, String prefix) {
    return prefs.getInt(prefix + "_down", 0) == 1
        && prefs.getInt(prefix + "_up", 0) == 1
        && prefs.getInt(prefix + "_matched", 0) == 1;
  }

  private void completeExplicitProbe(SharedPreferences appPrefs,
      SharedPreferences qaPrefs, boolean hadPlayer, String originalPlayer,
      boolean threw, String error) {
    restorePlayerPreference(appPrefs, hadPlayer, originalPlayer);
    qaPrefs.edit()
        .putBoolean("explicit_completed", true)
        .putBoolean("explicit_threw", threw)
        .putString("explicit_error", error)
        .putBoolean("explicit_pref_restored",
            playerPreferenceMatches(appPrefs, hadPlayer, originalPlayer))
        .commit();
    finish();
  }

  private static void resetExplicitEventCounters(SharedPreferences prefs) {
    prefs.edit()
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
