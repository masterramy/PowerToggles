package com.painless.pc.togglebay;

import android.content.Context;
import android.content.SharedPreferences;
import android.net.Uri;

import com.painless.pc.BuildConfig;

import java.io.File;
import java.util.UUID;

/**
 * ToggleBay public-identity boundary for the certified file-provider implementation.
 *
 * The inherited provider behavior remains unchanged; this class only owns public URI
 * construction so the installed application can coexist with the historical package.
 */
public class FileProvider extends com.painless.pc.FileProvider {

  private static final String AUTHORITY = BuildConfig.APPLICATION_ID + ".file";
  public static final String FOLDER_SHARE_URI = "content://" + AUTHORITY + "/folder-share";
  public static final String WIDGET_SHARE_URI = "content://" + AUTHORITY + "/widget-share";
  public static final String CROP_URI = "content://" + AUTHORITY + "/crop";
  public static final String CONFIG_URI_PREFIX = "content://" + AUTHORITY + "/config#";

  private static final String BACK_PATH_SEGMENT = "back";
  private static final String BACK_TOKEN_PREFS = "file_provider_capabilities";
  private static final String BACK_TOKEN_PREFIX = "widget_back_";

  /** Returns the launcher-facing capability URI using ToggleBay's public authority. */
  public static Uri widgetBackUri(Context context, int widgetId) {
    File backFile = com.painless.pc.FileProvider.widgetBackFile(context, widgetId);
    return new Uri.Builder()
        .scheme("content")
        .authority(AUTHORITY)
        .appendPath(BACK_PATH_SEGMENT)
        .appendPath(Integer.toString(widgetId))
        .appendPath(getOrCreateWidgetBackToken(context, widgetId))
        .fragment(Long.toString(backFile.lastModified()))
        .build();
  }

  private static synchronized String getOrCreateWidgetBackToken(Context context, int widgetId) {
    SharedPreferences prefs = context.getSharedPreferences(BACK_TOKEN_PREFS, Context.MODE_PRIVATE);
    String key = BACK_TOKEN_PREFIX + widgetId;
    String token = prefs.getString(key, null);
    if (token == null || token.length() < 32) {
      token = UUID.randomUUID().toString().replace("-", "")
          + UUID.randomUUID().toString().replace("-", "");
      if (!prefs.edit().putString(key, token).commit()) {
        throw new IllegalStateException("Unable to persist widget background capability");
      }
    }
    return token;
  }
}
