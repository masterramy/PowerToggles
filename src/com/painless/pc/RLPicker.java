package com.painless.pc;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Context;
import android.content.DialogInterface;
import android.content.DialogInterface.OnClickListener;
import android.os.Bundle;
import android.provider.Settings;
import android.view.Surface;

import com.painless.pc.tracker.AbstractSystemSettingsTracker;
import com.painless.pc.tracker.RotationLockTracker;
import com.painless.pc.util.SectionAdapter;

public class RLPicker extends Activity implements OnClickListener {

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

    if (mode == 0) {
      Settings.System.putInt(c.getContentResolver(), Settings.System.ACCELEROMETER_ROTATION, 1);
      return;
    }

    boolean landscapeDefault = RotationLockTracker.isLandScapeDefault(c);
    int rotation;
    if (mode == 1) {
      rotation = landscapeDefault ? Surface.ROTATION_90 : Surface.ROTATION_0;
    } else {
      rotation = landscapeDefault ? Surface.ROTATION_0 : Surface.ROTATION_90;
    }

    // Re-enter auto before selecting a new locked angle. On Android 16, changing
    // USER_ROTATION while rotation is already locked can rotate momentarily but
    // then normalize back to the previous lock when a fixed-orientation surface
    // (for example the launcher) resumes. Relatching through Auto makes the new
    // public USER_ROTATION value durable before freezing rotation again.
    Settings.System.putInt(c.getContentResolver(), Settings.System.ACCELEROMETER_ROTATION, 1);
    Settings.System.putInt(c.getContentResolver(), Settings.System.USER_ROTATION, rotation);
    Settings.System.putInt(c.getContentResolver(), Settings.System.ACCELEROMETER_ROTATION, 0);
  }

  public static void setAutoRotate(Context c, int value) {
    setRotationMode(c, value == 1 ? 0 : 1);
  }
}
