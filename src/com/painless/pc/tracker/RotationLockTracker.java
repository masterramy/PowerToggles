package com.painless.pc.tracker;

import android.content.ContentResolver;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.res.Configuration;
import android.graphics.Point;
import android.provider.Settings;
import android.view.Display;
import android.view.Surface;
import android.view.WindowManager;

import com.painless.pc.R;
import com.painless.pc.RLPicker;
import com.painless.pc.singleton.Globals;

public class RotationLockTracker extends AbstractTracker {

  private boolean mShowPrompt;

  public RotationLockTracker(int trackerId, SharedPreferences pref) {
    super(trackerId, pref, new int[] {
            COLOR_DEFAULT, R.drawable.icon_rotation_port, COLOR_DEFAULT, R.drawable.icon_rotation_land,
            COLOR_ON, R.drawable.icon_toggle_autorotate
    });
  }

  @Override
  public void init(SharedPreferences pref) {
    mShowPrompt = pref.getBoolean("rotation_lock_prompt", true);
  }

  @Override
  public int getActualState(Context context) {
    final ContentResolver cr = context.getContentResolver();
    if (isAutoRotate(cr)) {
      return STATE_ENABLED;
    }

    int rotation = Settings.System.getInt(cr, Settings.System.USER_ROTATION, Surface.ROTATION_0);
    int portraitRotation = isLandScapeDefault(context) ? Surface.ROTATION_90 : Surface.ROTATION_0;
    return rotation == portraitRotation ? STATE_DISABLED : STATE_INTERMEDIATE;
  }

  @Override
  public void toggleState(Context context) {
    if (mShowPrompt) {
      Globals.startIntent(context, Globals.setIncognetoIntent(new Intent(context, RLPicker.class)));
    } else {
      int state = getActualState(context);
      if (state == STATE_ENABLED) {
        RLPicker.setRotationMode(context, 1);
      } else if (state == STATE_DISABLED) {
        RLPicker.setRotationMode(context, 2);
      } else {
        RLPicker.setRotationMode(context, 0);
      }
    }
  }

  @Override
  protected void requestStateChange(Context context, boolean desiredState) {
    // Never Called
  }

  @Override
  public boolean shouldProxy(Context context) {
    return true;
  }

  @Override
  public String getStateText(int state, String[] states, String[] labelArray) {
    return states[7 + mDisplayNumber];
  }

  public static final boolean isLandScapeDefault(Context ctx) {
    WindowManager windowManager = (WindowManager) ctx.getSystemService(Context.WINDOW_SERVICE);
    Display display = windowManager.getDefaultDisplay();
    int rotation = display.getRotation();
    int orientation = ctx.getResources().getConfiguration().orientation;

    // Recover the display's natural orientation from two current-state signals
    // instead of assuming ROTATION_0 is portrait or treating Display.Mode bounds
    // as rotation-invariant. This remains correct for portrait-natural phones and
    // landscape-natural tablets/foldables as the display rotates.
    if (orientation == Configuration.ORIENTATION_LANDSCAPE) {
      return rotation == Surface.ROTATION_0 || rotation == Surface.ROTATION_180;
    }
    if (orientation == Configuration.ORIENTATION_PORTRAIT) {
      return rotation == Surface.ROTATION_90 || rotation == Surface.ROTATION_270;
    }

    // Defensive fallback if Configuration has no usable orientation. Recover the
    // same natural-orientation relationship from current geometry plus rotation.
    Point size = new Point();
    display.getRealSize(size);
    if ((rotation == Surface.ROTATION_0) || (rotation == Surface.ROTATION_180)) {
      return size.x > size.y;
    }
    return size.y > size.x;
  }

  private static boolean isAutoRotate(final ContentResolver resolver) {
    return Settings.System.getInt(resolver, Settings.System.ACCELEROMETER_ROTATION, 1) == 1;
  }
}
