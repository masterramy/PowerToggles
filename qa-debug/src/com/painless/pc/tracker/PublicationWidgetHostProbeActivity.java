package com.painless.pc.tracker;

import android.app.Activity;
import android.app.PendingIntent;
import android.appwidget.AppWidgetHost;
import android.appwidget.AppWidgetManager;
import android.appwidget.AppWidgetProviderInfo;
import android.content.ComponentName;
import android.content.Intent;
import android.content.SharedPreferences;
import android.net.Uri;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;

import com.painless.pc.PCWidgetActivity;
import com.painless.pc.singleton.Globals;
import com.painless.pc.singleton.SettingStorage;
import com.painless.pc.theme.RVFactory;

/**
 * Debug-only publication probe for ID33 Widget Settings.
 *
 * Allocates a genuine framework AppWidgetHost ID, binds it to the shipping
 * Power Toggles provider, and invokes the exact shipping widget-button intent
 * path. This class is present only in debug builds; release bytes are untouched.
 */
public final class PublicationWidgetHostProbeActivity extends Activity {

  private static final int HOST_ID = 0x5054;
  private static final String PREFS = "publication_widget_host_probe";
  private AppWidgetHost mHost;

  @Override
  protected void onCreate(Bundle state) {
    super.onCreate(state);
    runProbe(getIntent().getStringExtra("probe"),
        getIntent().getIntExtra("widget_id", AppWidgetManager.INVALID_APPWIDGET_ID));
  }

  @Override
  protected void onNewIntent(Intent intent) {
    super.onNewIntent(intent);
    setIntent(intent);
    runProbe(intent.getStringExtra("probe"),
        intent.getIntExtra("widget_id", AppWidgetManager.INVALID_APPWIDGET_ID));
  }

  private SharedPreferences probePrefs() {
    return getSharedPreferences(PREFS, MODE_PRIVATE);
  }

  private AppWidgetHost host() {
    if (mHost == null) {
      mHost = new AppWidgetHost(this, HOST_ID);
    }
    return mHost;
  }

  private void runProbe(String probe, int widgetId) {
    final SharedPreferences out = probePrefs();
    final AppWidgetManager manager = AppWidgetManager.getInstance(this);
    final ComponentName provider = new ComponentName(this, PCWidgetActivity.class);

    if ("allocate_bind".equals(probe)) {
      int allocated = AppWidgetManager.INVALID_APPWIDGET_ID;
      boolean bound = false;
      String error = "";
      try {
        allocated = host().allocateAppWidgetId();
        bound = manager.bindAppWidgetIdIfAllowed(allocated, provider);
      } catch (Throwable t) {
        error = t.getClass().getName() + ":" + String.valueOf(t.getMessage());
      }
      final AppWidgetProviderInfo info = allocated == AppWidgetManager.INVALID_APPWIDGET_ID
          ? null : manager.getAppWidgetInfo(allocated);
      out.edit()
          .putInt("widget_id", allocated)
          .putBoolean("bound", bound)
          .putBoolean("provider_info_present", info != null)
          .putString("provider", info == null || info.provider == null ? "" : info.provider.flattenToString())
          .putString("allocate_error", error)
          .commit();
      finish();
      return;
    }

    if ("status".equals(probe)) {
      final AppWidgetProviderInfo info = manager.getAppWidgetInfo(widgetId);
      String settings = "";
      String error = "";
      try {
        settings = SettingStorage.getSettingString(this, widgetId);
      } catch (Throwable t) {
        error = t.getClass().getName() + ":" + String.valueOf(t.getMessage());
      }
      out.edit()
          .putInt("status_widget_id", widgetId)
          .putBoolean("status_provider_info_present", info != null)
          .putString("status_provider", info == null || info.provider == null ? "" : info.provider.flattenToString())
          .putBoolean("settings_present", settings != null && settings.length() > 2)
          .putInt("settings_length", settings == null ? -1 : settings.length())
          .putString("status_error", error)
          .commit();
      finish();
      return;
    }

    if ("reopen".equals(probe)) {
      final SharedPreferences appPrefs = Globals.getAppPrefs(this);
      final WidgetSettingCommand command = new WidgetSettingCommand(33, appPrefs);
      final Uri data = Uri.parse("tracker/?" + command.getId() + "#" + widgetId);
      final Intent click = RVFactory.makeIntent(this, data);
      out.edit()
          .putInt("reopen_widget_id", widgetId)
          .putString("reopen_uri", data.toString())
          .putString("reopen_dispatch_error", "")
          .commit();

      // RemoteViews invokes this route through a PendingIntent as a user-facing
      // widget action. A raw sendBroadcast() from onCreate can be treated as a
      // background-activity launch on Android 16 and incorrectly strand the QA
      // probe on Launcher. Dispatch the same immutable broadcast PendingIntent
      // once this debug host is visibly resumed so the certification exercises
      // the shipping receiver/data/category transport without changing release.
      final PendingIntent pending = PendingIntent.getBroadcast(this, 0, click,
          PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
      new Handler(Looper.getMainLooper()).postDelayed(() -> {
        try {
          pending.send();
          // Do not leave this no-UI debug host beneath WidgetConfigActivity.
          // Finishing here makes every later probe a fresh lifecycle invocation
          // and prevents Android 16 from reusing a stale top activity after BACK.
          finish();
        } catch (PendingIntent.CanceledException e) {
          out.edit().putString("reopen_dispatch_error",
              e.getClass().getName() + ":" + String.valueOf(e.getMessage())).commit();
          finish();
        }
      }, 500L);
      return;
    }

    if ("malformed".equals(probe)) {
      final SharedPreferences appPrefs = Globals.getAppPrefs(this);
      final WidgetSettingCommand command = new WidgetSettingCommand(33, appPrefs);
      final Uri data = Uri.parse("tracker/?" + command.getId() + "#not-a-widget-id");
      sendBroadcast(RVFactory.makeIntent(this, data));
      out.edit().putString("malformed_uri", data.toString()).commit();
      finish();
      return;
    }

    if ("delete".equals(probe)) {
      String error = "";
      try {
        host().deleteAppWidgetId(widgetId);
      } catch (Throwable t) {
        error = t.getClass().getName() + ":" + String.valueOf(t.getMessage());
      }
      out.edit()
          .putInt("deleted_widget_id", widgetId)
          .putBoolean("provider_present_after_delete", manager.getAppWidgetInfo(widgetId) != null)
          .putString("delete_error", error)
          .commit();
      finish();
      return;
    }

    finish();
  }
}
