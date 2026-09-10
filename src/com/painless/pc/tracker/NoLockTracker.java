package com.painless.pc.tracker;

import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Build;

import com.painless.pc.NoLockService;
import com.painless.pc.R;

public class NoLockTracker extends AbstractTracker {

	public static final String CHANGE_ACTION = "custom_no_lock";

	@Override
	public String getChangeAction() {
		return CHANGE_ACTION;
	}

	public NoLockTracker(int trackerId, SharedPreferences pref) {
		super(trackerId, pref, getTriImageConfig(R.drawable.icon_toggle_no_lock));
	}

	@Override
	public int getActualState(Context context) {
		if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
			return STATE_DISABLED;
		}
		return NoLockService.NO_LOCK_ON ? STATE_ENABLED : STATE_DISABLED;
	}

	@Override
	protected void requestStateChange(final Context context, boolean desiredState) {
		Intent i = new Intent(context, NoLockService.class);
		if (desiredState) {
			// The legacy KeyguardLock mechanism is deprecated and requires a
			// long-lived started service. Keep that compatibility path only on
			// pre-O releases rather than attempting an unsupported background
			// service on modern Android.
			if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
				setCurrentState(context, STATE_DISABLED);
				return;
			}
			context.startService(i);
		} else {
			context.stopService(i);
		}
	}
}
