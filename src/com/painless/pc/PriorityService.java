package com.painless.pc;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.os.Build;
import android.os.IBinder;

import com.painless.pc.singleton.Globals;

public abstract class PriorityService extends Service {

  private static final String STOP_INTENT_PREFIX = "com.painless.ps.";
  private static final String FOREGROUND_CHANNEL_ID = "persistent_controls";

  private final int mNotificationId;
  private final String mAction;

  private boolean mRegistered;

  private final BroadcastReceiver mStopReceiver = new BroadcastReceiver() {
    
    @Override
    public void onReceive(Context context, Intent intent) {
      stopSelf();
    }
  };

  PriorityService(int notificationId, String action) {
    mNotificationId = notificationId;
    mAction = action;
  }

  @Override
  public IBinder onBind(Intent intent) {
    return null;
  }

  protected void broadcastState() {
    Globals.sendCustomAction(this, mAction);
  }

  protected void maybeShowNotification(String key, boolean dValue, int icon, int title, int subtitle, boolean listenToDeviceLock) {
    maybeShowNotification(key, dValue, icon, title, subtitle, listenToDeviceLock, false);
  }

  protected void maybeShowNotification(String key, boolean dValue, int icon, int title, int subtitle,
          boolean listenToDeviceLock, boolean forceForeground) {
    IntentFilter stopFilter = new IntentFilter();
    if (listenToDeviceLock) {
      stopFilter.addAction(Intent.ACTION_SCREEN_OFF);
      mRegistered = true;
    }
    
    if (forceForeground || !Globals.getAppPrefs(this).getBoolean(key, dValue)) {
      String stopIntent = STOP_INTENT_PREFIX + key;

      NotificationManager notificationManager = (NotificationManager) getSystemService(NOTIFICATION_SERVICE);
      Notification.Builder builder;
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
        NotificationChannel channel = new NotificationChannel(
            FOREGROUND_CHANNEL_ID,
            getString(title),
            NotificationManager.IMPORTANCE_LOW);
        channel.setDescription(getString(subtitle));
        notificationManager.createNotificationChannel(channel);
        builder = new Notification.Builder(this, FOREGROUND_CHANNEL_ID);
      } else {
        builder = new Notification.Builder(this);
      }

      Notification n = builder
          .setSmallIcon(icon)
          .setContentTitle(getString(title))
          .setContentText(getString(subtitle))
          .setContentIntent(PendingIntent.getBroadcast(this, 0, new Intent(stopIntent), PendingIntent.FLAG_IMMUTABLE))
          .setOngoing(true)
          .build();
      startForeground(mNotificationId, n);

      stopFilter.addAction(stopIntent);
      mRegistered = true;
    }
    if (mRegistered) {
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
        registerReceiver(mStopReceiver, stopFilter, Context.RECEIVER_NOT_EXPORTED);
      } else {
        registerReceiver(mStopReceiver, stopFilter);
      }
    }
  }

  protected void clearNotification() {
    if (mRegistered) {
      unregisterReceiver(mStopReceiver);
    }
    ((NotificationManager) getSystemService(NOTIFICATION_SERVICE)).cancel(mNotificationId);
  }
}
