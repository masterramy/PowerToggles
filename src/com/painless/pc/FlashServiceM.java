package com.painless.pc;

import android.annotation.TargetApi;
import android.content.Context;
import android.hardware.camera2.CameraAccessException;
import android.hardware.camera2.CameraCharacteristics;
import android.hardware.camera2.CameraManager;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;

import com.painless.pc.singleton.Debug;
import com.painless.pc.singleton.Globals;
import com.painless.pc.tracker.FlashStateTracker;

/**
 * Process-scoped controller for the public Android M+ torch API.
 *
 * This deliberately is not an Android Service. A widget/receiver toggle can call
 * CameraManager.setTorchMode directly without relying on background-service or
 * foreground-service exemptions. Android owns the final safety boundary: if the
 * app process exits, a torch it enabled is turned off by the platform.
 */
@TargetApi(Build.VERSION_CODES.M)
public final class FlashServiceM {

  private static final Object LOCK = new Object();

  private static CameraManager sCameraManager;
  private static String sCameraId;
  private static Context sAppContext;
  private static boolean sCallbackRegistered;

  private FlashServiceM() { }

  public static boolean isEnabled(Context context) {
    try {
      ensureInitialized(context);
    } catch (Throwable e) {
      Debug.log(e);
    }
    return FlashService.FLASH_ON;
  }

  public static boolean setEnabled(Context context, boolean enabled) {
    try {
      if (!ensureInitialized(context)) {
        return false;
      }
      sCameraManager.setTorchMode(sCameraId, enabled);
      updateState(enabled);
      return true;
    } catch (Throwable e) {
      Debug.log(e);
      return false;
    }
  }

  private static boolean ensureInitialized(Context context) throws CameraAccessException {
    synchronized (LOCK) {
      if (sAppContext == null) {
        sAppContext = context.getApplicationContext();
      }
      if (sCameraManager == null) {
        sCameraManager = (CameraManager) sAppContext.getSystemService(Context.CAMERA_SERVICE);
      }
      if (sCameraManager == null) {
        return false;
      }
      if (sCameraId == null) {
        sCameraId = findTorchCamera(sCameraManager);
      }
      if (sCameraId == null) {
        return false;
      }
      if (!sCallbackRegistered) {
        sCameraManager.registerTorchCallback(TORCH_CALLBACK, new Handler(Looper.getMainLooper()));
        sCallbackRegistered = true;
      }
      return true;
    }
  }

  private static String findTorchCamera(CameraManager manager) throws CameraAccessException {
    String fallback = null;
    for (String id : manager.getCameraIdList()) {
      CameraCharacteristics characteristics = manager.getCameraCharacteristics(id);
      Boolean flashAvailable = characteristics.get(CameraCharacteristics.FLASH_INFO_AVAILABLE);
      if (flashAvailable == null || !flashAvailable) {
        continue;
      }
      if (fallback == null) {
        fallback = id;
      }
      Integer lensFacing = characteristics.get(CameraCharacteristics.LENS_FACING);
      if (lensFacing != null && lensFacing == CameraCharacteristics.LENS_FACING_BACK) {
        return id;
      }
    }
    return fallback;
  }

  private static void updateState(boolean enabled) {
    boolean changed = FlashService.FLASH_ON != enabled;
    FlashService.FLASH_ON = enabled;
    if (changed && sAppContext != null) {
      Globals.sendCustomAction(sAppContext, FlashStateTracker.CHANGE_ACTION);
    }
  }

  private static final CameraManager.TorchCallback TORCH_CALLBACK =
      new CameraManager.TorchCallback() {
        @Override
        public void onTorchModeChanged(String cameraId, boolean enabled) {
          if (cameraId.equals(sCameraId)) {
            updateState(enabled);
          }
        }

        @Override
        public void onTorchModeUnavailable(String cameraId) {
          if (cameraId.equals(sCameraId)) {
            updateState(false);
          }
        }
      };
}
