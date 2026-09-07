package com.painless.pc.tracker;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.view.KeyEvent;

/**
 * Debug-only configured-media-player endpoint.
 * Persists exact DOWN/UP delivery from shipping MediaButton ordered broadcasts.
 */
public final class PublicationMediaEdgeReceiver extends BroadcastReceiver {

  private static final String PROBE_PREFS = "publication_media_edge_probe";

  @Override
  public void onReceive(Context context, Intent intent) {
    KeyEvent event = intent == null ? null :
        (KeyEvent) intent.getParcelableExtra(Intent.EXTRA_KEY_EVENT);
    if (event == null) {
      return;
    }

    String prefix = prefixForKeyCode(event.getKeyCode());
    if (prefix == null) {
      return;
    }

    SharedPreferences prefs = context.getSharedPreferences(PROBE_PREFS, Context.MODE_PRIVATE);
    SharedPreferences.Editor edit = prefs.edit();
    if (event.getAction() == KeyEvent.ACTION_DOWN) {
      edit.putInt(prefix + "_down", prefs.getInt(prefix + "_down", 0) + 1)
          .putLong(prefix + "_down_time", event.getDownTime());
    } else if (event.getAction() == KeyEvent.ACTION_UP) {
      edit.putInt(prefix + "_up", prefs.getInt(prefix + "_up", 0) + 1);
      if (prefs.getLong(prefix + "_down_time", -1L) == event.getDownTime()) {
        edit.putInt(prefix + "_matched", prefs.getInt(prefix + "_matched", 0) + 1);
      }
    }
    edit.commit();
  }

  private static String prefixForKeyCode(int keyCode) {
    if (keyCode == KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE) return "explicit_play_pause";
    if (keyCode == KeyEvent.KEYCODE_MEDIA_NEXT) return "explicit_next";
    if (keyCode == KeyEvent.KEYCODE_MEDIA_PREVIOUS) return "explicit_prev";
    return null;
  }
}
