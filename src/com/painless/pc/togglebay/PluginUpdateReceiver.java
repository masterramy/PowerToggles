package com.painless.pc.togglebay;

import android.content.Context;
import android.content.Intent;

import com.painless.pc.BuildConfig;

/**
 * ToggleBay public action boundary for the certified plugin receiver.
 */
public class PluginUpdateReceiver extends com.painless.pc.PluginUpdateReceiver {

  private static final String TOGGLEBAY_STATE_CHANGED =
      BuildConfig.APPLICATION_ID + ".ACTION_STATE_CHANGED";
  private static final String LEGACY_STATE_CHANGED = "com.painless.pc.ACTION_STATE_CHANGED";

  @Override
  public void onReceive(Context context, Intent intent) {
    if (intent != null && TOGGLEBAY_STATE_CHANGED.equals(intent.getAction())) {
      Intent normalized = new Intent(intent);
      normalized.setAction(LEGACY_STATE_CHANGED);
      super.onReceive(context, normalized);
      return;
    }
    super.onReceive(context, intent);
  }
}
