package com.painless.pc.tracker;

import android.content.Context;
import android.content.SharedPreferences;

import com.painless.pc.R;

/**
 * Stable tracker-ID compatibility shell for the retired WiMAX control.
 *
 * WiMAX is RETIRED_F3 and absent from the new-user picker. Keep historical ID
 * 14 loadable for saved definitions, but do not probe or mutate obsolete WiMAX
 * services through reflection or retain connectivity privileges for that path.
 */
public class WiMaxTracker extends AbstractTracker {

	public WiMaxTracker(int trackerId, SharedPreferences pref) {
		super(trackerId, pref, getTriImageConfig(R.drawable.icon_toggle_gprs_4g));
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
