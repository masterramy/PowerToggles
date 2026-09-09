package com.painless.pc.picker.theme;

import static com.painless.pc.util.SettingsDecoder.DEFAULT_DIVIDER_COLOR;
import static com.painless.pc.util.SettingsDecoder.KEY_COLORS;
import static com.painless.pc.util.SettingsDecoder.KEY_DENSITY;
import static com.painless.pc.util.SettingsDecoder.KEY_DIVIDER_COLOR;
import static com.painless.pc.util.SettingsDecoder.KEY_HIDE_DIVIDERS;
import static com.painless.pc.util.SettingsDecoder.KEY_PADDING;
import static com.painless.pc.util.SettingsDecoder.KEY_STRETCH;

import java.io.BufferedReader;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.net.URLConnection;
import java.util.HashSet;
import java.util.Set;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.zip.ZipEntry;
import java.util.zip.ZipFile;

import org.json.JSONObject;

import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.os.Handler;
import android.os.Handler.Callback;
import android.os.Message;
import android.util.Pair;

import com.painless.pc.singleton.BackupUtil;
import com.painless.pc.singleton.Debug;
import com.painless.pc.util.SettingsDecoder;
import com.painless.pc.util.Thunk;
import com.painless.pc.util.WidgetSetting;

/**
 * A class to handle theme loading
 */
public class ThemeLoader implements Callback {

  private static final int CONFIG_LOADED = 1;
  private static final int NETWORK_TIMEOUT_MS = 5000;
  private static final int MAX_REMOTE_IMAGE_BYTES = 4 * 1024 * 1024;
  private static final int MAX_REMOTE_IMAGE_DIMENSION = 2048;
  private static final long MAX_REMOTE_IMAGE_PIXELS = 4L * 1024L * 1024L;
  private static final int MAX_RENDER_DIMENSION = 4096;

  private final Set<ThemeEntry> mPendingTasks;
  private final BitmapCache mCache;
  private final ThemeAdapter mNotifier;

  private final ExecutorService mLocalService;
  private final ExecutorService mRemoteService;
  @Thunk final Handler mResponseHandler;

  private final int mDensity;
  private volatile boolean mDestroyed = false;

  public ThemeLoader(ThemeAdapter loadCallback) {
    mNotifier = loadCallback;
    mCache = new BitmapCache();
    mPendingTasks = new HashSet<ThemeEntry>();

    mRemoteService = Executors.newFixedThreadPool(3);
    mLocalService = Executors.newSingleThreadExecutor();
    mResponseHandler = new Handler(this);
    mDensity = loadCallback.getContext().getResources().getDisplayMetrics().densityDpi;
  }

  public synchronized void submic(ThemeEntry request) {
    if (mDestroyed || mPendingTasks.contains(request) || request.failed) {
      // Request already pending or loader is gone.
      return;
    }

    if (request.themeFile != null) {
      mPendingTasks.add(request);
      mLocalService.submit(new LocalThemeLoader(request));
    } else if (request.remoteUrl != null) {
      mPendingTasks.add(request);
      mRemoteService.submit(new RemoteThemeLoader(request));
    }
  }

  public void destroy() {
    mDestroyed = true;
    mResponseHandler.removeCallbacksAndMessages(null);
    mRemoteService.shutdownNow();
    mLocalService.shutdownNow();
    mCache.evictAll();
  }

  @SuppressWarnings("unchecked")
  @Override
  public boolean handleMessage(Message msg) {
    if (msg.what == CONFIG_LOADED) {
      Pair<ThemeEntry, Bitmap> result = (Pair<ThemeEntry, Bitmap>) msg.obj;
      ThemeEntry request = result.first;
      if (mDestroyed) {
        if (result.second != null) {
          result.second.recycle();
        }
        return true;
      }
      request.background = result.second;
      if (result.second != null) {
        mCache.put(result.second, request);
      }
      mPendingTasks.remove(request);
      mNotifier.notifyDataSetChanged();
      return true;
    }
    return false;
  }

  /**
   * Marks a bitmap as being used.
   */
  public void register(Bitmap img) {
    mCache.get(img);
  }

  private void deliver(ThemeEntry request, Bitmap image) {
    if (mDestroyed) {
      if (image != null) {
        image.recycle();
      }
      return;
    }
    Message.obtain(mResponseHandler, CONFIG_LOADED, Pair.create(request, image)).sendToTarget();
  }

  /**
   * A task to load local themes.
   */
  private class LocalThemeLoader implements Runnable {

    private final ThemeEntry mRequest;

    public LocalThemeLoader(ThemeEntry request) {
      mRequest = request;
    }

    @Override
    public void run() {
      Bitmap image = null;
      ZipFile zip = null;
      try {
        zip = new ZipFile(mRequest.themeFile);
        ZipEntry configEntry = zip.getEntry("theme.txt");
        ZipEntry backImage = zip.getEntry("back.png");
        if (configEntry == null || backImage == null) {
          throw new IllegalArgumentException("Theme archive is incomplete");
        }

        BufferedReader reader = new BufferedReader(new InputStreamReader(zip.getInputStream(configEntry)));
        String config = reader.readLine();
        reader.close();

        mRequest.config = new JSONObject(config);
        image = parseConfig(mRequest, BitmapFactory.decodeStream(zip.getInputStream(backImage)));
      } catch (Exception e) {
        Debug.log(e);
        mRequest.failed = true;
      } finally {
        if (zip != null) {
          try {
            zip.close();
          } catch (Exception e) {
            Debug.log(e);
          }
        }
      }

      deliver(mRequest, image);
    }
  }

  /**
   * A task to load remote themes.
   */
  private class RemoteThemeLoader implements Runnable {

    private final ThemeEntry mRequest;

    public RemoteThemeLoader(ThemeEntry request) {
      mRequest = request;
    }

    @Override
    public void run() {
      Bitmap image = null;
      try {
        image = parseConfig(mRequest, loadRemoteBitmap(mRequest));
      } catch (Exception e) {
        Debug.log(e);
        mRequest.failed = true;
      }
      deliver(mRequest, image);
    }
  }

  private Bitmap loadRemoteBitmap(ThemeEntry request) throws Exception {
    URLConnection connection = request.remoteUrl.openConnection();
    connection.setConnectTimeout(NETWORK_TIMEOUT_MS);
    connection.setReadTimeout(NETWORK_TIMEOUT_MS);

    InputStream in = null;
    ByteArrayOutputStream out = new ByteArrayOutputStream();
    try {
      in = connection.getInputStream();
      byte[] buffer = new byte[8192];
      int total = 0;
      int read;
      while ((read = in.read(buffer)) != -1) {
        total += read;
        if (total > MAX_REMOTE_IMAGE_BYTES) {
          throw new IllegalArgumentException("Remote theme image is too large");
        }
        out.write(buffer, 0, read);
      }
    } finally {
      if (in != null) {
        try { in.close(); } catch (Exception e) { Debug.log(e); }
      }
    }

    byte[] data = out.toByteArray();
    BitmapFactory.Options bounds = new BitmapFactory.Options();
    bounds.inJustDecodeBounds = true;
    BitmapFactory.decodeByteArray(data, 0, data.length, bounds);
    if (bounds.outWidth <= 0 || bounds.outHeight <= 0
        || bounds.outWidth > MAX_REMOTE_IMAGE_DIMENSION || bounds.outHeight > MAX_REMOTE_IMAGE_DIMENSION
        || ((long) bounds.outWidth * (long) bounds.outHeight) > MAX_REMOTE_IMAGE_PIXELS) {
      throw new IllegalArgumentException("Invalid remote theme image dimensions");
    }

    Bitmap bitmap = BitmapFactory.decodeByteArray(data, 0, data.length);
    if (bitmap == null) {
      throw new IllegalArgumentException("Unable to decode remote theme image");
    }
    return bitmap;
  }

  @Thunk Bitmap parseConfig(ThemeEntry entry, Bitmap loadedIcon) {
    if (loadedIcon == null) {
      throw new IllegalArgumentException("Theme image is missing");
    }
    SettingsDecoder decoder = new SettingsDecoder(entry.config);
    int density = decoder.getValue(KEY_DENSITY, mDensity);
    if (density <= 0) {
      throw new IllegalArgumentException("Invalid theme density");
    }

    long scaledWidth = (long) loadedIcon.getWidth() * (long) mDensity / density;
    long scaledHeight = (long) loadedIcon.getHeight() * (long) mDensity / density;
    if (scaledWidth <= 0 || scaledHeight <= 0
        || scaledWidth > MAX_RENDER_DIMENSION || scaledHeight > MAX_RENDER_DIMENSION) {
      throw new IllegalArgumentException("Theme render dimensions are invalid");
    }

    Bitmap resized = Bitmap.createScaledBitmap(loadedIcon,
            (int) scaledWidth,
            (int) scaledHeight,
            true);
    if (resized != loadedIcon) {
      loadedIcon.recycle();
    }

    entry.padding = notmalizeRect(decoder, KEY_PADDING, density);

    entry.stretch = new float[4];

    float[] sizes = new float[] {resized.getWidth(), resized.getHeight()};
    int[] stretch = notmalizeRect(decoder, KEY_STRETCH, density);
    for (int i = 0; i < 4; i++) {
      entry.stretch[i] = stretch[i] / sizes[i & 1];
    }

    entry.hideDividers = decoder.is(KEY_HIDE_DIVIDERS, true);
    entry.dividerColor = decoder.getValue(KEY_DIVIDER_COLOR, DEFAULT_DIVIDER_COLOR);
    WidgetSetting.parseColors(decoder, KEY_COLORS, entry.buttonColors, entry.buttonAlphas);

    return resized;
  }

  private int[] notmalizeRect(SettingsDecoder decoder, String key, int settingDensity) {
    return BackupUtil.normalizeRect(decoder, key, mDensity, settingDensity);
  }
}
