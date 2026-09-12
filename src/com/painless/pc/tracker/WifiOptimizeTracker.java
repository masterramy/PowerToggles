package com.painless.pc.tracker;

import android.content.Context;
import android.content.SharedPreferences;

import com.painless.pc.R;

/**
 * Stable tracker-ID compatibility shell for retired Wi-Fi optimization control.
 *
 * Wi-Fi Optimize is RETIRED_F3. Keep historical ID 46 loadable for saved
 * definitions, but do not mutate secure/global settings or execute root shell
 * commands for an obsolete platform setting.
 */
public class WifiOptimizeTracker extends AbstractTracker {

	public WifiOptimizeTracker(int trackerId, SharedPreferences pref) {
		super(trackerId, pref, getTriImageConfig(R.drawable.icon_wifi_opt));
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
