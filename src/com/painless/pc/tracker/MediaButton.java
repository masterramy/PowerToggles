package com.painless.pc.tracker;

import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.media.AudioManager;
import android.os.Build;
import android.os.SystemClock;
import android.text.TextUtils;
import android.view.KeyEvent;

import com.painless.pc.singleton.Debug;
import com.painless.pc.singleton.Globals;

public abstract class MediaButton extends AbstractCommand {

  public static final String KEY_PLAYER_INTENT = "media_player_intent";

	private final int keyCode;

	MediaButton(int trackerId, SharedPreferences pref, int imgId, int keyCode) {
		super(trackerId, pref, imgId);
		this.keyCode = keyCode;
	}

	@Override
	public void toggleState(Context context) {
	  String player = Globals.getAppPrefs(context).getString(KEY_PLAYER_INTENT, "");
	  try {
      long eventtime = SystemClock.uptimeMillis();
      KeyEvent down = new KeyEvent(eventtime, eventtime, KeyEvent.ACTION_DOWN, keyCode, 0);
      KeyEvent up = new KeyEvent(eventtime, eventtime + 2, KeyEvent.ACTION_UP, keyCode, 0);

      if (TextUtils.isEmpty(player) && Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
        AudioManager audio = (AudioManager) context.getSystemService(Context.AUDIO_SERVICE);
        if (audio != null) {
          // Modern Android routes media keys through the active media-session consumer.
          audio.dispatchMediaKeyEvent(down);
          audio.dispatchMediaKeyEvent(up);
          return;
        }
      }

      // Preserve the configured explicit-player path and the pre-KitKat fallback.
      Intent mediaIntent = TextUtils.isEmpty(player) ? new Intent(Intent.ACTION_MEDIA_BUTTON) : Intent.parseUri(player, 0);
      context.sendOrderedBroadcast(new Intent(mediaIntent).putExtra(Intent.EXTRA_KEY_EVENT, down), null);
      context.sendOrderedBroadcast(new Intent(mediaIntent).putExtra(Intent.EXTRA_KEY_EVENT, up), null);
    } catch (Exception e) {
      Debug.log(e);
    }
	}

	@Override
	public Intent getIntent() {
		return null;
	}

	@Override
	public boolean shouldProxy(Context context) {
		return false;
	}
}