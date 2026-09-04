package com.painless.pc.tracker;

import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.nfc.NfcAdapter;
import android.provider.Settings;

import com.painless.pc.R;
import com.painless.pc.singleton.Globals;

public class NfcStateTracker extends AbstractTracker {

  public NfcStateTracker(int trackerId, SharedPreferences pref) {
    super(trackerId, pref, getTriImageConfig(R.drawable.icon_toggle_nfc));
  }

  @Override
  public int getActualState(Context context) {
    NfcAdapter adapter = NfcAdapter.getDefaultAdapter(context);
    if (adapter == null) {
      return STATE_UNKNOWN;
    }
    try {
      return adapter.isEnabled() ? STATE_ENABLED : STATE_DISABLED;
    } catch (SecurityException e) {
      return STATE_UNKNOWN;
    }
  }

  @Override
  public void toggleState(Context context) {
    showSettings(context);
  }

  @Override
  protected void requestStateChange(Context context, boolean desiredState) {
    showSettings(context);
  }

  private void showSettings(Context context) {
    Globals.startIntent(context,
        new Intent(Settings.ACTION_NFC_SETTINGS)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
  }

  @Override
  public boolean shouldProxy(Context context) {
    return true;
  }
}
