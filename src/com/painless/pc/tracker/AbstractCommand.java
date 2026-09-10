package com.painless.pc.tracker;

import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;

import com.painless.pc.singleton.Globals;

public abstract class AbstractCommand extends AbstractTracker {

  public Context mContext;

	AbstractCommand(int trackerId, SharedPreferences pref, int imgId) {
		super(trackerId, pref, new int[] { COLOR_DEFAULT, imgId });
	}

	@Override
	public void onActualStateChange(Context context, Intent intent) { }

	@Override
	public int getActualState(Context context) {
		return STATE_DISABLED;
	}

	@Override
	protected void requestStateChange(Context context, boolean desiredState) { }

	@Override
	public void toggleState(Context context) {
		mContext = context;
		Intent intent = getIntent();
		if (intent != null) {
			// SimpleShortcut normalizes legacy direct-call intents when it is built.
			// Keep the shared command execution boundary fail-safe as well: if any
			// command unexpectedly reaches it with ACTION_CALL, open the dialer rather
			// than attempting a direct call. Use a copy so command-owned state is not
			// mutated by the safety fallback.
			if (Intent.ACTION_CALL.equals(intent.getAction())) {
				intent = new Intent(intent).setAction(Intent.ACTION_DIAL);
			}
			Globals.startIntent(context, intent);
		}
	}

	@Override
	public boolean shouldProxy(Context context) {
		return true;
	}

	public abstract Intent getIntent();

	@Override
	public String getStateText(int state, String[] states, String[] labelArray) {
		return getLabel(labelArray);
	}
}
