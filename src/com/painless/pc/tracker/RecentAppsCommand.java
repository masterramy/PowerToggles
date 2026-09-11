package com.painless.pc.tracker;

import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;

import com.painless.pc.R;

/**
 * Stable tracker-ID compatibility shell for the retired Recent Apps control.
 *
 * Modern ordinary applications do not have a supported public API for opening
 * the system recents UI. Keep the historical tracker class loadable for saved
 * widget/folder definitions, but do not call hidden status-bar binder APIs.
 */
public class RecentAppsCommand extends AbstractCommand {

	public RecentAppsCommand(int trackerId, SharedPreferences pref) {
		super(trackerId, pref, R.drawable.icon_toggle_recent);
	}

	@Override
	public void toggleState(Context context) {
		// RETIRED_F3: intentionally inert. Do not restore hidden IStatusBarService
		// or ServiceManager access merely to preserve unsupported legacy behavior.
	}

	@Override
	public Intent getIntent() {
		return null;
	}
}
