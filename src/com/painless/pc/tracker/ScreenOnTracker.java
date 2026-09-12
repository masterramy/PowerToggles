package com.painless.pc.tracker;

import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Build;

import com.painless.pc.R;
import com.painless.pc.ScreenOnService;
import com.painless.pc.singleton.Debug;

public final class ScreenOnTracker extends AbstractTracker {
	
	public static final String CHANGE_ACTION = "custom_screenOn";

	@Override
	public String getChangeAction() {
		return CHANGE_ACTION;
	}

	public ScreenOnTracker(int trackerId, SharedPreferences pref) {
		super(trackerId, pref, getTriImageConfig(R.drawable.icon_toggle_screen_on));
	}

	@Override
	public int getActualState(Context context) {
		return ScreenOnService.SCREEN_ON ? STATE_ENABLED : STATE_DISABLED;
	}

	@Override
	protected void requestStateChange(Context context, boolean desiredState) {
		Intent i = new Intent(context, ScreenOnService.class);
		if (desiredState) {
			try {
				if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
					context.startForegroundService(i);
				} else {
					context.startService(i);
				}
			} catch (IllegalStateException e) {
				// Android can reject a foreground-service launch from a background
				// context when no current platform exemption applies. Keep the toggle
				// truthfully disabled instead of crashing or leaving it in transition.
				Debug.log(e);
				setCurrentState(context, STATE_DISABLED);
			} catch (SecurityException e) {
				Debug.log(e);
				setCurrentState(context, STATE_DISABLED);
			}
		} else {
			context.stopService(i);
		}
	}
}
