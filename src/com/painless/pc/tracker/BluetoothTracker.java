package com.painless.pc.tracker;

import android.bluetooth.BluetoothAdapter;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Build;
import android.provider.Settings;

import com.painless.pc.R;
import com.painless.pc.singleton.Globals;

public final class BluetoothTracker extends AbstractDoubleClickTracker  {

	private static final String CHANGE_ACTION = BluetoothAdapter.ACTION_STATE_CHANGED;

	@Override
	public String getChangeAction() {
		return CHANGE_ACTION;
	}

	public BluetoothTracker(int trackerId, SharedPreferences pref) {
		super(trackerId, pref, getTriImageConfig(R.drawable.icon_toggle_bluetooth));
	}

	@Override
	public int getActualState(Context context) {
		// Android 12+ protects adapter state with BLUETOOTH_CONNECT. Power Toggles
		// deliberately avoids adding a Nearby Devices runtime-permission burden for
		// a control that modern Android no longer allows third-party apps to switch
		// directly anyway. Report UNKNOWN rather than prompting or faking state.
		if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
			return STATE_UNKNOWN;
		}

		final BluetoothAdapter adapter = BluetoothAdapter.getDefaultAdapter();
		if (adapter == null) {
			return STATE_UNKNOWN;
		}
		try {
			switch (adapter.getState()) {
				case BluetoothAdapter.STATE_ON :
					return STATE_ENABLED;
				case BluetoothAdapter.STATE_OFF :
					return STATE_DISABLED;
				case BluetoothAdapter.STATE_TURNING_ON :
					return STATE_TURNING_ON;
				case BluetoothAdapter.STATE_TURNING_OFF :
					return STATE_TURNING_OFF;
				default :
					return STATE_UNKNOWN;
			}
		} catch (SecurityException e) {
			return STATE_UNKNOWN;
		}
	}

	@Override
	protected void requestStateChange(Context context, boolean desiredState) {
		// Android 12+ requires BLUETOOTH_CONNECT even for the legacy request-enable
		// activity, and Android 13+ also blocks direct enable/disable for ordinary
		// apps. Use the system Bluetooth settings UI for a truthful, permission-free
		// user-mediated control on modern Android.
		if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
			Globals.startIntent(context, new Intent(Settings.ACTION_BLUETOOTH_SETTINGS));
			return;
		}

		final BluetoothAdapter adapter = BluetoothAdapter.getDefaultAdapter();
		if (adapter == null) {
			return;
		}
		try {
			if (desiredState) {
				adapter.enable();
			} else {
				adapter.disable();
			}
		} catch (SecurityException e) {
			Globals.startIntent(context, new Intent(Settings.ACTION_BLUETOOTH_SETTINGS));
		}
	}

	@Override
	Intent getDCIntent(Context context) {
		return new Intent(Settings.ACTION_BLUETOOTH_SETTINGS);
	}
}
