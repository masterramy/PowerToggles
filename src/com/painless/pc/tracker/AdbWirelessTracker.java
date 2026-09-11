package com.painless.pc.tracker;

import android.content.Context;
import android.content.SharedPreferences;

import com.painless.pc.R;

/**
 * Stable tracker-ID compatibility shell for the retired ADB Wireless control.
 *
 * The historical implementation depended on hidden SystemProperties plus root
 * setprop/adbd process control. Keep ID 39 loadable for saved definitions, but
 * do not execute hidden or privileged system mutation from publication source.
 */
public class AdbWirelessTracker extends AbstractTracker {

	public AdbWirelessTracker(int trackerId, SharedPreferences pref) {
		super(trackerId, pref, getTriImageConfig(R.drawable.icon_recovery));
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
