package com.painless.pc.singleton;

import java.util.ArrayList;
import java.util.Calendar;

import android.app.Activity;
import android.app.AlarmManager;
import android.app.PendingIntent;
import android.content.ActivityNotFoundException;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.database.Cursor;
import android.net.Uri;
import android.os.Build;
import android.os.Process;
import android.preference.PreferenceActivity;
import android.widget.Toast;

import com.painless.pc.R;
import com.painless.pc.cfg.EditWidgetConfigActivity;
import com.painless.pc.nav.NotifyFrag;
import com.painless.pc.settings.LaunchActivity;

public class Globals {

	// Id of various buttons
	public static final int[] BUTTONS = new int[] {
		R.id.btn_1,
		R.id.btn_2,
		R.id.btn_3,
		R.id.btn_4,
		R.id.btn_5,
		R.id.btn_6,
		R.id.btn_7,
		R.id.btn_8
	};

	// Id of various button dividers
	public static final int[] BUTTON_DIVS = new int[] {
		R.id.btn_1_div,
		R.id.btn_2_div,
		R.id.btn_3_div,
		R.id.btn_4_div,
		R.id.btn_5_div,
		R.id.btn_6_div,
		R.id.btn_7_div,
		R.id.btn_8
	};

	// Id of various buttons containers
	public static final int[] BUTTONS_CONTAINERS = new int[] {
		R.id.btn_1_container,
		R.id.btn_2_container,
		R.id.btn_3_container,
		R.id.btn_4_container,
		R.id.btn_5_container,
		R.id.btn_6_container,
		R.id.btn_7_container,
		R.id.btn_8_container
	};

	// Id of various buttons containers
	public static final int[] BUTTONS_INDS = new int[] {
		R.id.btn_1_ind,
		R.id.btn_2_ind,
		R.id.btn_3_ind,
		R.id.btn_4_ind,
		R.id.btn_5_ind,
		R.id.btn_6_ind,
		R.id.btn_7_ind,
		R.id.btn_8_ind
	};

	public static boolean IS_LOLLIPOP = Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP;

	public static final String PLUGIN_INTENT = "com.painless.pc.ACTION_SET_STATE";

	public static final String SHARED_PREFS_NAME = "widget_preference";
	public static final String EXTRA_PREFS_NAME = "extra_preference";
	public static final String NOTIFICATION_PRIORITY = "notify_priority";

  public static final String SIGNAURE_PERMISSION = "com.painless.pc.permission.CONTROL_PLUGIN";

	public static final int STATUS_BAR_WIDGET_ID = -22;
	public static final int STATUS_BAR_WIDGET_ID_2 = -23;
  public static final int QS_MAX_WIDGET_ID = -50;
	public static final int NOTIFICATION_ID = 1;

	// ++++++++++++++++++ Battery +++++++++++++++++++
	private static final long batteryGap = 5000;	// 5 seconds.
	private static long lastBatteryUpdate = 0;
	public static int sLastBattery = 0;

	private static final String MOTOROLA_HACK = "motorola_hack";

	public static int getBattery(Context context) {
		final long now = System.currentTimeMillis();
		if (batteryGap < Math.abs(now - lastBatteryUpdate)) {
			lastBatteryUpdate = now;

			SharedPreferences pref = getAppPrefs(context);
			boolean updated = false;

			if (pref.getBoolean(MOTOROLA_HACK, false)) {
				try {
					java.io.FileReader fReader = new java.io.FileReader("/sys/class/power_supply/battery/charge_counter");
					java.io.BufferedReader bReader = new java.io.BufferedReader(fReader);
					String line = bReader.readLine();
					bReader.close();

					int charge_counter = Integer.valueOf(line);
					if (charge_counter >= 0 && charge_counter < 115) {
						sLastBattery = Math.min(charge_counter, 100);
						updated = true;
					}
				} catch (Throwable e) {
					Debug.log(e);
					pref.edit().remove(MOTOROLA_HACK).commit();
				}
			}

			if (!updated) {
				try {
					final Intent intent = context.getApplicationContext().
							registerReceiver(null, new IntentFilter(Intent.ACTION_BATTERY_CHANGED));

					final int level = intent.getIntExtra("level", 0);
					final int scale = intent.getIntExtra("scale", 100);
					sLastBattery = level * 100 / scale;
				} catch (Exception e) { }
			}
		}
		return sLastBattery;
	}


	/**
	 * Compatibility no-op. Modern ordinary applications have no supported public
	 * API for collapsing the system notification shade programmatically.
	 */
	public static final void collapseStatusBar(Context context) {
		// Intentionally empty. Do not restore hidden StatusBarManager reflection.
	}

	public static Intent setIncognetoIntent(Intent i) {
		return i.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TASK)
				.addFlags(Intent.FLAG_ACTIVITY_EXCLUDE_FROM_RECENTS)
				.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP);
	}

	public static final void startIntent(Context context, Intent intent) {
		try {
			Globals.collapseStatusBar(context);
			intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
			context.startActivity(intent);
		} catch (ActivityNotFoundException e) {
			Debug.log(e);
			Toast.makeText(context, R.string.err_no_activity, Toast.LENGTH_LONG).show();
		} catch (SecurityException e) {
			Debug.log(e);
			Toast.makeText(context, R.string.err_security, Toast.LENGTH_LONG).show();
		}
	}

	public static String sNetworkName = "";

	/**
	 * Returns the historical notification/icon level for an unknown mobile radio.
	 * Reading the actual data-network technology requires phone-state privileges
	 * that this ordinary Play app intentionally does not request. Preserve the
	 * existing UNKNOWN -> level 1 rendering contract without making a restricted
	 * TelephonyManager call from widget or notification rendering.
	 */
	public static final int getNetworkType(Context context) {
		sNetworkName = context.getString(R.string.lbl_unknown_allcap);
		return 1;
	}

	public static boolean isNotificationWidget(int widgetId) {
	  return (widgetId == STATUS_BAR_WIDGET_ID) || (widgetId == STATUS_BAR_WIDGET_ID_2);
	}

	public static void showWidgetConfig(int widgetId, Context context, boolean newTask) {
		final Intent intent = isNotificationWidget(widgetId) ?
		        new Intent(context, LaunchActivity.class).putExtra(PreferenceActivity.EXTRA_SHOW_FRAGMENT, NotifyFrag.class.getName()) :
		          new Intent(context, EditWidgetConfigActivity.class).putExtra("edit_widget", widgetId);
		if (newTask) {
			intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
		}

		collapseStatusBar(context);
		context.startActivity(intent);
		if (!newTask && (context instanceof Activity)) {
			((Activity) context).overridePendingTransition(R.anim.right_slide_in, R.anim.left_slide_out);
		}
	}

	// Custom action
	public static final String CUSTOM_ACTION = "com.painless.pc.CUSTOM_ACTION";
	public static void sendCustomAction(Context context, String action) {
		Intent intent = new Intent(CUSTOM_ACTION);
		intent.putExtra("action_type", action);
		context.sendBroadcast(intent);
	}

	private static SharedPreferences sPrefs;

	public static SharedPreferences getAppPrefs(Context context) {
	  if (sPrefs == null) {
	    sPrefs = context.getApplicationContext().getSharedPreferences(SHARED_PREFS_NAME, Context.MODE_PRIVATE);
	  }
	  return sPrefs;
	}


	public static String getTimeDiff(long timedate, Context context) {
		if (timedate == 0) {
			return context.getString(R.string.stat_u_never);
		}
		long diff = Calendar.getInstance().getTimeInMillis() - timedate;
		diff = diff / 60000;	// convert to minutes.
		if (diff <= 1) {
			return context.getString(R.string.stat_u_now);
		} else if (diff < 120) {
			return context.getString(R.string.stat_u_mins, diff);
		} else {
			diff = diff / 60;	// hours
			if (diff < 48) {
				return context.getString(R.string.stat_u_hours, diff);
			} else {
				diff = diff / 24;	// days
				return context.getString(R.string.stat_u_days, diff);
			}
		}
	}

	public static final String TASKER_KEY_PREFIX = "tasker_";
  private static final int MAX_TASKER_TASKS = 256;
  private static final int MAX_TASKER_TASK_NAME_CHARS = 256;

	public static ArrayList<String> getTaskerTasks(Context context) {
		ArrayList<String> tasks = new ArrayList<String>();
    Cursor c = null;
    try {
      c = context.getContentResolver().query(
          Uri.parse("content://net.dinglisch.android.tasker/tasks"), null, null, null, null);
      if (c == null) {
        return tasks;
      }
      int nameCol = c.getColumnIndex("name");
      if (nameCol < 0) {
        return tasks;
      }
      while (tasks.size() < MAX_TASKER_TASKS && c.moveToNext()) {
        String name = c.getString(nameCol);
        if (name == null || name.length() == 0) {
          continue;
        }
        tasks.add(name.length() <= MAX_TASKER_TASK_NAME_CHARS
            ? name : name.substring(0, MAX_TASKER_TASK_NAME_CHARS));
      }
    } catch (Throwable e) {
      Debug.log(e);
    } finally {
      if (c != null) {
        try { c.close(); } catch (Throwable e) { Debug.log(e); }
      }
    }
		return tasks;
	}

	public static void setAlarm(Context context, Calendar when, Intent target) {
		final PendingIntent sender = PendingIntent.getBroadcast(context, 0, target,
				PendingIntent.FLAG_CANCEL_CURRENT | PendingIntent.FLAG_IMMUTABLE);
		final AlarmManager am = (AlarmManager) context.getSystemService(Context.ALARM_SERVICE);
		am.set(AlarmManager.RTC, when.getTimeInMillis(), sender);
	}

	public static boolean hasPermission(Context c, String permission) {
	  return c.checkPermission(permission, Process.myPid(), Process.myUid()) == PackageManager.PERMISSION_GRANTED;
	}

//	public static boolean isNewVersion(Context context) {
//		SharedPreferences prefs = context.getSharedPreferences(SHARED_PREFS_NAME, 0);
//		int version = prefs.getInt("current_version", 0);
//		try {
//			int currentVersion = context.getPackageManager().getPackageInfo(context.getPackageName(), 0).versionCode;
//			if (currentVersion != version) {
//				pref.edit().putInt("current_version", currentVersion).commit();
//				return true;
//			}
//		} catch (NameNotFoundException e) {
//			Debug.log(e);
//		}
//		return false;
//	}
}
