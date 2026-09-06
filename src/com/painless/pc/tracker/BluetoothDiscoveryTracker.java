package com.painless.pc.tracker;

import android.Manifest;
import android.bluetooth.BluetoothAdapter;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.os.Build;
import android.provider.Settings;

import com.painless.pc.R;
import com.painless.pc.singleton.Globals;

public class BluetoothDiscoveryTracker extends AbstractTracker {

	public BluetoothDiscoveryTracker(int trackerId, SharedPreferences pref) {
		super(trackerId, pref, getTriImageConfig(R.drawable.icon_toggle_bluetooth_discovery));
	}

	private boolean hasModernBluetoothPermission(Context context) {
		return Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
				context.checkSelfPermission(Manifest.permission.BLUETOOTH_SCAN) == PackageManager.PERMISSION_GRANTED;
	}

	@Override
	public int getActualState(Context context) {
		final BluetoothAdapter adapter = BluetoothAdapter.getDefaultAdapter();
		if (adapter == null || !hasModernBluetoothPermission(context)) {
			return STATE_UNKNOWN;
		}
		try {
			return (adapter.getScanMode() == BluetoothAdapter.SCAN_MODE_CONNECTABLE_DISCOVERABLE) ?
					STATE_ENABLED : STATE_DISABLED;
		} catch (SecurityException ignored) {
			return STATE_UNKNOWN;
		}
	}

	@Override
	public void toggleState(Context context) {
		if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !hasModernBluetoothPermission(context)) {
			// Modern Android requires runtime Nearby devices permission for direct
			// discoverability control. Keep the widget crash-free and hand the user
			// to the platform Bluetooth surface rather than silently failing.
			Globals.startIntent(context, new Intent(Settings.ACTION_BLUETOOTH_SETTINGS));
			return;
		}
		Intent discoverableIntent = new Intent(BluetoothAdapter.ACTION_REQUEST_DISCOVERABLE);
		discoverableIntent.putExtra(BluetoothAdapter.EXTRA_DISCOVERABLE_DURATION, 120);
		try {
			Globals.startIntent(context, discoverableIntent);
		} catch (SecurityException ignored) {
			Globals.startIntent(context, new Intent(Settings.ACTION_BLUETOOTH_SETTINGS));
		}
	}

	@Override
	protected void requestStateChange(Context context, boolean desiredState) { }

	@Override
	public boolean shouldProxy(Context context) {
		return true;
	}
}
