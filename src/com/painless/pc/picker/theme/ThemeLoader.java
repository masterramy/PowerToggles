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
import java.util.HashSet;
import java.util.Set;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.zip.ZipEntry;
import java.util.zip.ZipFile;

import org.json.JSONObject;

import android.graphics.Bitmap;
import android.os.Handler;
import android.os.Handler.Callback;
import android.os.Message;
import android.util.Pair;

import com.painless.pc.singleton.BackupUtil;
import com.painless.pc.singleton.Debug;
import com.painless.pc.util.BitmapImportUtils;
import com.painless.pc.util.SettingsDecoder;
import com.painless.pc.util.Thunk;
import com.painless.pc.util.WidgetSetting;

/**
 * Loads app-private or legacy-local theme archives. The former remote gallery
 * was retired because its hosting endpoint no longer exists; ThemePicker now
 * exposes explicit document import instead of issuing a doomed network request.
 */
public class ThemeLoader implements Callback {

  private static final int CONFIG_LOADED = 1;
  private static final long MAX_THEME_CONFIG_BYTES = 256L * 1024L;
  private static final long MAX_THEME_IMAGE_BYTES = 8L * 1024L * 1024L;
  private static final int MAX_RENDER_DIMENSION = 4096;
  private static final long MAX_RENDER_PIXELS = 16L * 1024L * 1024L;

  private final Set<ThemeEntry> mPendingTasks;
  private final BitmapCache mCache;
  private final ThemeAdapter mNotifier;

  private final ExecutorService mLocalService;
  @Thunk final Handler mResponseHandler;

  private final int mDensity;
  private volatile boolean mDestroyed = false;

  public ThemeLoader(ThemeAdapter loadCallback) {
    mNotifier = loadCallback;
    mCache = new BitmapCache();
    mPendingTasks = new HashSet<ThemeEntry>();

    mLocalService = Executors.newSingleThreadExecutor();
    mResponseHandler = new Handler(this);
    mDensity = loadCallback.getContext().getResources().getDisplayMetrics().densityDpi;
  }

  public synchronized void submic(ThemeEntry request) {
    if (mDestroyed || request == null || mPendingTasks.contains(request) || request.failed) {
      return;
    }

    if (request.themeFile != null) {
      mPendingTasks.add(request);
      mLocalService.submit(new LocalThemeLoader(request));
    }
  }

  public void destroy() {
    mDestroyed = true;
    mResponseHandler.removeCallbacksAndMessages(null);
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

  /** Marks a bitmap as being used. */
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

  private class LocalThemeLoader implements Runnable {

    private final ThemeEntry mRequest;

    LocalThemeLoader(ThemeEntry request) {
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

        byte[] configBytes = readEntry(zip, configEntry, MAX_THEME_CONFIG_BYTES);
        BufferedReader reader = new BufferedReader(new InputStreamReader(
            new java.io.ByteArrayInputStream(configBytes), "UTF-8"));
        String config = reader.readLine();
        reader.close();
        if (config == null || config.length() == 0) {
          throw new IllegalArgumentException("Theme configuration is empty");
        }

        mRequest.config = new JSONObject(config);
        Bitmap loaded = BitmapImportUtils.decode(readEntry(zip, backImage, MAX_THEME_IMAGE_BYTES));
        image = parseConfig(mRequest, loaded);
      } catch (Exception e) {
        Debug.log(e);
        mRequest.failed = true;
      } finally {
        if (zip != null) {
          try { zip.close(); } catch (Exception e) { Debug.log(e); }
        }
      }

      deliver(mRequest, image);
    }
  }

  private static byte[] readEntry(ZipFile zip, ZipEntry entry, long maxBytes) throws Exception {
    InputStream in = null;
    ByteArrayOutputStream out = new ByteArrayOutputStream();
    try {
      in = zip.getInputStream(entry);
      BackupUtil.copy(in, out, maxBytes);
      return out.toByteArray();
    } finally {
      if (in != null) {
        try { in.close(); } catch (Exception e) { Debug.log(e); }
      }
      try { out.close(); } catch (Exception e) { Debug.log(e); }
    }
  }

  @Thunk Bitmap parseConfig(ThemeEntry entry, Bitmap loadedIcon) {
    if (loadedIcon == null) {
      throw new IllegalArgumentException("Theme image is missing");
    }
    SettingsDecoder decoder = new SettingsDecoder(entry.config);
    int density = decoder.getValue(KEY_DENSITY, mDensity);
    if (density <= 0 || density > 1000) {
      loadedIcon.recycle();
      throw new IllegalArgumentException("Invalid theme density");
    }

    long scaledWidth = (long) loadedIcon.getWidth() * (long) mDensity / density;
    long scaledHeight = (long) loadedIcon.getHeight() * (long) mDensity / density;
    if (scaledWidth <= 0 || scaledHeight <= 0
        || scaledWidth > MAX_RENDER_DIMENSION || scaledHeight > MAX_RENDER_DIMENSION
        || scaledWidth * scaledHeight > MAX_RENDER_PIXELS) {
      loadedIcon.recycle();
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
