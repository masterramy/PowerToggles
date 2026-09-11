package com.painless.pc.tracker;

import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Build;

import com.painless.pc.FlashService;
import com.painless.pc.FlashServiceM;
import com.painless.pc.R;
import com.painless.pc.singleton.Debug;

public final class FlashStateTracker extends AbstractTracker {

	public static final String CHANGE_ACTION = "custom_flash";

	@Override
	public String getChangeAction() {
		return CHANGE_ACTION;
	}

	public FlashStateTracker(int trackerId, SharedPreferences pref) {
		super(trackerId, pref, getTriImageConfig(R.drawable.icon_toggle_flash));
	}

	@Override
	public int getActualState(Context context) {
		if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
			return FlashServiceM.isEnabled(context) ? STATE_ENABLED : STATE_DISABLED;
		}
		return FlashService.FLASH_ON ? STATE_ENABLED : STATE_DISABLED;
	}

	@Override
	protected void requestStateChange(final Context context, boolean desiredState) {
		if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
			if (!FlashServiceM.setEnabled(context, desiredState)) {
				setCurrentState(context, getActualState(context));
			}
			return;
		}

		Intent i = new Intent(context, FlashService.class);
		if (desiredState) {
			try {
				context.startService(i);
			} catch (IllegalStateException e) {
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
