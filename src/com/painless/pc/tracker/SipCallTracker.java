package com.painless.pc.tracker;

import android.content.Context;
import android.content.SharedPreferences;

import com.painless.pc.R;

/**
 * Stable tracker-ID compatibility shell for the retired SIP calling control.
 *
 * ID 42 remains loadable for historical saved definitions, but publication source
 * no longer reads or writes the obsolete sip_call_options system setting.
 */
public class SipCallTracker extends AbstractTracker {

	public SipCallTracker(int trackerId, SharedPreferences pref) {
		super(trackerId, pref, new int[] {
				COLOR_DEFAULT, R.drawable.icon_toggle_sip_ask,
				COLOR_ON, R.drawable.icon_toggle_sip_some,
				COLOR_ON, R.drawable.icon_toggle_sip_all });
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

	@Override
	public String getStateText(int state, String[] states, String[] labelArray) {
		return states[14 + mDisplayNumber];
	}
}
