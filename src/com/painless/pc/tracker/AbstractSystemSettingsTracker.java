package com.painless.pc.tracker;

import android.Manifest;
import android.annotation.TargetApi;
import android.app.AppOpsManager;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.os.Build;
import android.os.Process;
import android.provider.Settings;

import com.painless.pc.PermissionDialog;
import com.painless.pc.singleton.Globals;

public abstract class AbstractSystemSettingsTracker extends AbstractTracker {

	private final String mSettings;
	private final String mAction;

	public AbstractSystemSettingsTracker(int trackerId, SharedPreferences pref, String settings,
	    int icon, String action) {
		super(trackerId, pref, getBiImageConfig(icon));
		mSettings = settings;
		mAction = action;
	}

	@Override
	public int getDisplayNo(Context context) {
		return (getTriState(context) == STATE_DISABLED) ? 0 : 1;
	}

	@Override
	public int getActualState(Context context) {
		return Settings.System.getInt(context.getContentResolver(), mSettings, 0) == 0 ? STATE_DISABLED : STATE_ENABLED;
	}

	@Override
	protected void requestStateChange(Context c, boolean desiredState) {
	  boolean success = putInt(c, mSettings, desiredState ? 1 : 0);

    if (!success) {
      showPermissionDialog(c, mAction);
    }
    setCurrentState(c, getActualState(c));
	}

	public static void showPermissionDialog(Context c, String action) {
	  showPermissionDialog(c, new Intent(action));
	}

	public static void showPermissionDialog(Context c, Intent target) {
	  target.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
	  c.startActivity(Globals.getAppPrefs(c).getBoolean("prompt_permission", false) ? target :
	    new Intent(c, PermissionDialog.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK).putExtra("target", target));
	}

	/**
	 * Writes one public Settings.System integer only while WRITE_SETTINGS is
	 * currently available. The special-access AppOp can be revoked between a
	 * caller's preflight and the write, so every write still fails closed here.
	 */
	public static boolean putInt(Context c, String setting, int value) {
	  if (!hasPermission(c)) {
	    return false;
	  }
	  try {
	    return Settings.System.putInt(c.getContentResolver(), setting, value);
	  } catch (SecurityException e) {
	    return false;
	  }
	}

	@TargetApi(Build.VERSION_CODES.M)
  public static boolean hasPermission(Context c) {
	  return ((Build.VERSION.SDK_INT < Build.VERSION_CODES.M)
        || (c.checkSelfPermission(Manifest.permission.WRITE_SETTINGS) == PackageManager.PERMISSION_GRANTED))
        || (c.getSystemService(AppOpsManager.class).checkOpNoThrow(AppOpsManager.OPSTR_WRITE_SETTINGS, Process.myUid(), c.getPackageName()) == AppOpsManager.MODE_ALLOWED);
	}
}
