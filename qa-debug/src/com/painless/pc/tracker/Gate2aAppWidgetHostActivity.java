package com.painless.pc.tracker;

import android.app.Activity;
import android.appwidget.AppWidgetHost;
import android.appwidget.AppWidgetManager;
import android.content.ComponentName;
import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import android.util.Log;

import com.painless.pc.CommandReceiver;
import com.painless.pc.PCWidgetActivity;
import com.painless.pc.cfg.WidgetConfigActivity;

/** QA-only host used to prove tracker 33 with a genuine AppWidgetManager ID. */
public class Gate2aAppWidgetHostActivity extends Activity {
  private static final String TAG = "Gate2aId33Host";
  private static final int HOST_ID = 0x2A33;

  @Override
  protected void onCreate(Bundle savedInstanceState) {
    super.onCreate(savedInstanceState);
    handle(getIntent());
  }

  @Override
  protected void onNewIntent(Intent intent) {
    super.onNewIntent(intent);
    handle(intent);
  }

  private void handle(Intent intent) {
    String action = intent.getStringExtra("qa_action");
    if ("allocate".equals(action)) {
      AppWidgetHost host = new AppWidgetHost(this, HOST_ID);
      int widgetId = host.allocateAppWidgetId();
      ComponentName provider = new ComponentName(this, PCWidgetActivity.class);
      boolean bound = AppWidgetManager.getInstance(this)
          .bindAppWidgetIdIfAllowed(widgetId, provider);
      Log.i(TAG, "allocated widgetId=" + widgetId + " bound=" + bound);
      if (bound) {
        startActivity(new Intent(this, WidgetConfigActivity.class)
            .setAction(AppWidgetManager.ACTION_APPWIDGET_CONFIGURE)
            .putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId));
      }
    } else if ("reopen".equals(action)) {
      int widgetId = intent.getIntExtra("widget_id", AppWidgetManager.INVALID_APPWIDGET_ID);
      Intent click = new Intent(this, CommandReceiver.class)
          .addCategory(Intent.CATEGORY_ALTERNATIVE)
          .setData(Uri.parse("gate2a://widget?33#" + widgetId));
      sendBroadcast(click);
      Log.i(TAG, "reopen widgetId=" + widgetId);
    } else if ("invalid".equals(action)) {
      Intent click = new Intent(this, CommandReceiver.class)
          .addCategory(Intent.CATEGORY_ALTERNATIVE)
          .setData(Uri.parse("gate2a://widget?33#not-an-int"));
      sendBroadcast(click);
      Log.i(TAG, "invalid fragment sent");
    } else if ("delete".equals(action)) {
      int widgetId = intent.getIntExtra("widget_id", AppWidgetManager.INVALID_APPWIDGET_ID);
      new AppWidgetHost(this, HOST_ID).deleteAppWidgetId(widgetId);
      Log.i(TAG, "deleted widgetId=" + widgetId);
    }
    finish();
  }
}
