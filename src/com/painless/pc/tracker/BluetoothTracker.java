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
			// Android 12+ protects adapter state with Nearby Devices permission.
			// A power-control widget must not fake a known state when access is denied.
			return STATE_UNKNOWN;
		}
	}

	@Override
	protected void requestStateChange(Context context, boolean desiredState) {
		// Apps targeting Android 13+ can no longer directly enable/disable Bluetooth.
		// Preserve truthful behavior with user-mediated system UI instead.
		if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
			Globals.startIntent(context, desiredState
					? new Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE)
					: new Intent(Settings.ACTION_BLUETOOTH_SETTINGS));
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
