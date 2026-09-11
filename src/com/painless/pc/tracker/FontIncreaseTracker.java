package com.painless.pc.tracker;

import android.content.Context;
import android.content.SharedPreferences;

import com.painless.pc.R;

/**
 * Stable tracker-ID compatibility shell for retired font-size controls.
 *
 * Font Increase/Decrease are RETIRED_F3. Keep the historical classes loadable
 * for saved definitions, but do not mutate FONT_SCALE or execute root commands.
 */
public class FontIncreaseTracker extends AbstractTracker {

	protected float delta;

	public FontIncreaseTracker(int trackerId, SharedPreferences pref) {
		this(trackerId, pref, R.drawable.icon_toggle_font_inc);
	}

	FontIncreaseTracker(int trackerId, SharedPreferences pref, int imgId) {
		super(trackerId, pref, getTriImageConfig(imgId));
	}

	@Override
	public void init(SharedPreferences pref) {
		delta = 0f;
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
		return getLabel(labelArray);
	}
}
