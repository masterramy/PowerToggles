package com.painless.pc.tracker;

import android.content.Context;
import android.content.SharedPreferences;

import com.painless.pc.R;

/**
 * Stable tracker-ID compatibility shell for the retired notification-light pulse control.
 *
 * ID 40 remains loadable for historical saved definitions, but publication source
 * no longer reads or writes the obsolete notification_light_pulse system setting.
 */
public class PulseLightTracker extends AbstractTracker {

	public PulseLightTracker(int trackerId, SharedPreferences pref) {
		super(trackerId, pref, getBiImageConfig(R.drawable.icon_toggle_pulse));
	}

	@Override
	public int getActualState(Context context) {
		return STATE_DISABLED;
	}

	@Override
	protected void requestStateChange(Context context, boolean desiredState) {
		// RETIRED_F3: intentionally inert.
		setCurrentState(context, STATE_DISABLED);
	}
}
