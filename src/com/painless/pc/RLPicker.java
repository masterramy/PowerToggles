package com.painless.pc;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Context;
import android.content.DialogInterface;
import android.content.DialogInterface.OnClickListener;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;
import android.view.Surface;

import com.painless.pc.tracker.AbstractSystemSettingsTracker;
import com.painless.pc.tracker.RotationLockTracker;
import com.painless.pc.util.SectionAdapter;

import java.util.concurrent.atomic.AtomicInteger;

public class RLPicker extends Activity implements OnClickListener {

  private static final AtomicInteger ROTATION_WRITE_GENERATION = new AtomicInteger();
  private static final long ROTATION_SETTLE_REASSERT_MS = 750L;

  @Override
  protected void onCreate(Bundle savedInstanceState) {
    super.onCreate(savedInstanceState);

    SectionAdapter adapter = new SectionAdapter(this);
    adapter.addItem(getString(R.string.rt_auto), R.drawable.icon_toggle_autorotate);

    if (RotationLockTracker.isLandScapeDefault(this)) {
      adapter.addItem(getString(R.string.rt_land, getText(R.string.rt_default)), R.drawable.icon_rotation_land);
      adapter.addItem(getString(R.string.rt_port, getText(R.string.rt_forced)), R.drawable.icon_rotation_port);
    } else {
      adapter.addItem(getString(R.string.rt_port, getText(R.string.rt_default)), R.drawable.icon_rotation_port);
      adapter.addItem(getString(R.string.rt_land, getText(R.string.rt_forced)), R.drawable.icon_rotation_land);
    }

    AlertDialog dialog = new AlertDialog.Builder(this)
        .setTitle(R.string.rt_title)
        .setAdapter(adapter, this)
        .setNegativeButton(R.string.act_cancel, null)
        .create();
    dialog.setOnDismissListener(d -> finish());
    dialog.show();
  }

  @Override
  public void onClick(DialogInterface dialog, int type) {
    // The public Settings.System rotation controls replace the legacy overlay
    // service, which Android 16 no longer permits from an ordinary app service.
    // Picker order remains Auto / device-default orientation / forced opposite.
    if (type == 0) {
      setRotationMode(this, 0);
    } else if (type == 1) {
      setRotationMode(this, RotationLockTracker.isLandScapeDefault(this) ? 2 : 1);
    } else if (type == 2) {
      setRotationMode(this, RotationLockTracker.isLandScapeDefault(this) ? 1 : 2);
    }
    PCWidgetActivity.partialUpdateAllWidgets(this);
  }

  /** mode: 0 auto, 1 portrait, 2 landscape. */
  public static void setRotationMode(Context c, int mode) {
    if (!AbstractSystemSettingsTracker.hasPermission(c)) {
      AbstractSystemSettingsTracker.showPermissionDialog(c, Settings.ACTION_DISPLAY_SETTINGS);
      return;
    }

    final int generation = ROTATION_WRITE_GENERATION.incrementAndGet();

    if (mode == 0) {
      if (!AbstractSystemSettingsTracker.putInt(c, Settings.System.ACCELEROMETER_ROTATION, 1)) {
        AbstractSystemSettingsTracker.showPermissionDialog(c, Settings.ACTION_DISPLAY_SETTINGS);
      }
      return;
    }

    boolean landscapeDefault = RotationLockTracker.isLandScapeDefault(c);
    final int rotation;
    if (mode == 1) {
      rotation = landscapeDefault ? Surface.ROTATION_90 : Surface.ROTATION_0;
    } else {
      rotation = landscapeDefault ? Surface.ROTATION_0 : Surface.ROTATION_90;
    }

    // Re-enter auto before selecting a new locked angle. On Android 16, changing
    // USER_ROTATION while rotation is already locked can rotate momentarily but
    // then normalize back to the previous lock when a fixed-orientation surface
    // (for example the launcher) resumes. Relatch through Auto, freeze rotation,
    // and assert the requested angle immediately. Every write is fail-closed in
    // case WRITE_SETTINGS is revoked between the initial permission check and the
    // relatch sequence; only a complete sequence may schedule the delayed reassert.
    boolean success =
        AbstractSystemSettingsTracker.putInt(c, Settings.System.ACCELEROMETER_ROTATION, 1)
        && AbstractSystemSettingsTracker.putInt(c, Settings.System.USER_ROTATION, rotation)
        && AbstractSystemSettingsTracker.putInt(c, Settings.System.ACCELEROMETER_ROTATION, 0)
        && AbstractSystemSettingsTracker.putInt(c, Settings.System.USER_ROTATION, rotation);
    if (!success) {
      AbstractSystemSettingsTracker.showPermissionDialog(c, Settings.ACTION_DISPLAY_SETTINGS);
      return;
    }

    // A synchronous reassert can still race the launcher/activity orientation
    // settle on Android 16. Reinforce once after that settle window, but only if
    // this is still the newest rotation command and the user remains in locked
    // mode. A later Auto/Portrait/Landscape command increments the generation and
    // invalidates this runnable, so a stale choice can never be resurrected.
    new Handler(Looper.getMainLooper()).postDelayed(new Runnable() {
      @Override
      public void run() {
        if (ROTATION_WRITE_GENERATION.get() != generation) {
          return;
        }
        if (Settings.System.getInt(c.getContentResolver(), Settings.System.ACCELEROMETER_ROTATION, 1) == 0) {
          AbstractSystemSettingsTracker.putInt(c, Settings.System.USER_ROTATION, rotation);
        }
      }
    }, ROTATION_SETTLE_REASSERT_MS);
  }

  public static void setAutoRotate(Context c, int value) {
    setRotationMode(c, value == 1 ? 0 : 1);
  }
}
