package com.painless.pc.tracker;

import android.content.Intent;

import com.painless.pc.R;

public class SimpleShortcut extends AbstractCommand {

	private final String label;

	private final Intent launchIntent;
	private  String id;

	public SimpleShortcut(Intent intent, String label) {
		super(-1, null, R.drawable.icon_application);
		this.label = label;

		// Legacy shortcut providers could return CALL_PRIVILEGED, and older
		// Power Toggles folder databases may already contain our historical
		// ACTION_CALL normalization. Public builds must not require the dangerous
		// CALL_PHONE permission merely to preserve those shortcuts. Route both
		// forms through the system dialer so the number is retained and the user
		// explicitly confirms the call.
		String action = intent.getAction();
		if ("android.intent.action.CALL_PRIVILEGED".equals(action)
				|| Intent.ACTION_CALL.equals(action)) {
			intent.setAction(Intent.ACTION_DIAL);
		}

		this.launchIntent = intent;
		this.id = "ss_";
	}

	@Override
	public String getLabel(String[] labelArray) {
		return label;
	}

	@Override
	public Intent getIntent() {
		return launchIntent;
	}

	public final void setId(int id) {
		this.id = "ss_" + id;
	}
	
	public final void setId(String id) {
		this.id = "ss_" + id;
	}

	@Override
	public String getId() {
		return id;
	}

	public static int getId(int widgetID, int pos) {
		int id = widgetID << 3;
		return id + pos;
	}
}
