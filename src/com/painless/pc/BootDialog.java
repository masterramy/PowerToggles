package com.painless.pc;

import android.app.Activity;
import android.os.Bundle;
import android.widget.Toast;

/**
 * Stable activity-name compatibility shell for retired power controls.
 *
 * Shutdown, Restart, and Shutdown Menu are RETIRED_F3. Historical saved
 * definitions may still resolve this activity, but publication source must not
 * depend on hidden IPowerManager/ServiceManager APIs, internal AlertActivity,
 * or privileged/root reboot execution.
 */
public class BootDialog extends Activity {

	@Override
	protected void onCreate(Bundle savedInstanceState) {
		super.onCreate(savedInstanceState);
		Toast.makeText(this, R.string.bt_error_summary, Toast.LENGTH_LONG).show();
		finish();
	}
}
