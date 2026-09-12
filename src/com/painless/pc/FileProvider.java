package com.painless.pc;

import android.content.ContentProvider;
import android.content.ContentValues;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.content.pm.ResolveInfo;
import android.database.Cursor;
import android.database.MatrixCursor;
import android.net.Uri;
import android.os.Binder;
import android.os.ParcelFileDescriptor;
import android.os.Process;
import android.provider.OpenableColumns;

import com.painless.pc.singleton.Debug;

import java.io.File;
import java.io.FileNotFoundException;
import java.util.List;
import java.util.UUID;

/**
 * {@link ContentProvider} for background images and other internal files.
 */
public class FileProvider extends ContentProvider {

  private static final String AUTHORITY = "com.painless.pc.file";
  public static final String FOLDER_SHARE_URI = "content://" + AUTHORITY + "/folder-share";
  public static final String WIDGET_SHARE_URI = "content://" + AUTHORITY + "/widget-share";
  public static final String CROP_URI = "content://" + AUTHORITY + "/crop";

  private static final String TEMP_BACK_IMAGE_NAME = "cback";
  private static final String BACK_IMAGE_PREFIX = "back_";
  private static final String BACK_PATH_SEGMENT = "back";
  private static final String BACK_TOKEN_PREFS = "file_provider_capabilities";
  private static final String BACK_TOKEN_PREFIX = "widget_back_";
  private static final String FOLDER_SHARE_FILE_NAME = "folder.pcf";
  private static final String WIDGET_SHARE_FILE_NAME = "widget.zip";
  private static final String FOLDER_SHARE_PATH = "/folder-share";
  private static final String WIDGET_SHARE_PATH = "/widget-share";
  private static final String CONFIG_PATH = "/config";
  private static final String CROP_PATH = "/crop";

  @Override
  public boolean onCreate() {
    return true;
  }

  @Override
  public Cursor query(Uri uri, String[] projection, String selection, String[] selectionArgs, String sortOrder) {
    Debug.log(uri);
    String path = uri.getPath();
    File file;
    String displayName;
    if (FOLDER_SHARE_PATH.equals(path)) {
      enforceReadGrant(uri, "folder share metadata");
      file = folderShareFile(getContext());
      displayName = FOLDER_SHARE_FILE_NAME;
    } else if (WIDGET_SHARE_PATH.equals(path)) {
      enforceReadGrant(uri, "widget share metadata");
      file = widgetShareFile(getContext());
      displayName = WIDGET_SHARE_FILE_NAME;
    } else {
      return null;
    }

    String[] columns = projection;
    if (columns == null) {
      columns = new String[] { OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE };
    }
    MatrixCursor result = new MatrixCursor(columns, 1);
    Object[] row = new Object[columns.length];
    for (int i = 0; i < columns.length; i++) {
      if (OpenableColumns.DISPLAY_NAME.equals(columns[i])) {
        row[i] = displayName;
      } else if (OpenableColumns.SIZE.equals(columns[i])) {
        row[i] = file.length();
      } else {
        row[i] = null;
      }
    }
    result.addRow(row);
    return result;
  }

  @Override
  public String getType(Uri uri) {
    String path = uri.getPath();
    return (FOLDER_SHARE_PATH.equals(path) || WIDGET_SHARE_PATH.equals(path))
        ? "application/zip" : "image/png";
  }

  @Override
  public Uri insert(Uri uri, ContentValues values) {
    return null;
  }

  @Override
  public int delete(Uri uri, String selection, String[] selectionArgs) {
    return 0;
  }

  @Override
  public int update(Uri uri, ContentValues values, String selection, String[] selectionArgs) {
    return 0;
  }

  @Override
  public ParcelFileDescriptor openFile(Uri uri, String mode) throws FileNotFoundException {
    String path = uri.getPath();
    File result;
    if (FOLDER_SHARE_PATH.equals(path)) {
      if (!"r".equals(mode)) {
        throw new FileNotFoundException("Folder share is read-only");
      }
      enforceReadGrant(uri, "folder share");
      result = folderShareFile(getContext());
    } else if (WIDGET_SHARE_PATH.equals(path)) {
      if (!"r".equals(mode)) {
        throw new FileNotFoundException("Widget share is read-only");
      }
      enforceReadGrant(uri, "widget share");
      result = widgetShareFile(getContext());
    } else if (isWidgetBackUri(uri)) {
      // RemoteViews image URIs are dereferenced by the launcher/SystemUI process.
      // AppWidgetService validates that *this app* can access the URI but does not
      // automatically grant that URI to every host. Keep this route exported/read-only,
      // while requiring an unguessable per-widget capability for all new external reads.
      if (!"r".equals(mode)) {
        throw new FileNotFoundException("Widget background is read-only");
      }
      result = resolveWidgetBackFile(uri);
    } else if (CONFIG_PATH.equals(path)) {
      if (!"r".equals(mode)) {
        throw new FileNotFoundException("Configuration preview is read-only");
      }
      enforceSameUid("configuration preview");
      result = tempBackImage(getContext());
    } else if (CROP_PATH.equals(path)) {
      int callerUid = Binder.getCallingUid();
      if (callerUid == Process.myUid()) {
        if (!"r".equals(mode)) {
          throw new FileNotFoundException("App crop result is read-only");
        }
      } else {
        // The selected crop activity receives an exact temporary READ grant to this
        // app-owned output URI via ClipData. Treat that grant as the capability token
        // for a write-only crop result, avoiding a broad WRITE grant that would also
        // propagate to the user's source image in Intent data.
        if (!("w".equals(mode) || "wt".equals(mode))) {
          throw new FileNotFoundException("External crop output is write-only");
        }
        enforceReadGrant(uri, "crop output");
      }
      result = cropFile(getContext());
    } else {
      throw new FileNotFoundException();
    }
    return ParcelFileDescriptor.open(result, modeToMode(mode));
  }

  private boolean isWidgetBackUri(Uri uri) {
    List<String> segments = uri.getPathSegments();
    return segments != null && !segments.isEmpty() && BACK_PATH_SEGMENT.equals(segments.get(0));
  }

  private File resolveWidgetBackFile(Uri uri) throws FileNotFoundException {
    Context context = getContext();
    if (context == null) {
      throw new FileNotFoundException();
    }

    int callerUid = Binder.getCallingUid();
    List<String> segments = uri.getPathSegments();

    // New capability URI: /back/<widgetId>/<unguessable-token>
    if (segments != null && segments.size() == 3 && BACK_PATH_SEGMENT.equals(segments.get(0))) {
      try {
        int widgetId = Integer.parseInt(segments.get(1));
        String suppliedToken = segments.get(2);
        if (callerUid != Process.myUid()) {
          String expectedToken = getExistingWidgetBackToken(context, widgetId);
          if (expectedToken == null || !expectedToken.equals(suppliedToken)) {
            throw new SecurityException("Widget background capability required");
          }
        }
        return widgetBackFile(context, widgetId);
      } catch (NumberFormatException e) {
        throw new FileNotFoundException();
      }
    }

    // Same-UID compatibility for historical internal URIs of the form /back/?<id>.
    // During an app upgrade a launcher may briefly retain an already-rendered old
    // RemoteViews. Permit only the currently resolved HOME host (or Android system UID)
    // to consume that legacy URI until the next widget update publishes a capability URI.
    if (segments != null && segments.size() == 1 && BACK_PATH_SEGMENT.equals(segments.get(0))) {
      if (callerUid != Process.myUid() && callerUid != Process.SYSTEM_UID && !isCurrentHomeUid(context, callerUid)) {
        throw new SecurityException("Legacy widget background access denied");
      }
      try {
        return widgetBackFile(context, Integer.parseInt(uri.getQuery()));
      } catch (Exception e) {
        throw new FileNotFoundException();
      }
    }

    throw new FileNotFoundException();
  }

  private boolean isCurrentHomeUid(Context context, int callerUid) {
    try {
      Intent homeIntent = new Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME);
      ResolveInfo home = context.getPackageManager().resolveActivity(homeIntent, PackageManager.MATCH_DEFAULT_ONLY);
      return home != null && home.activityInfo != null && home.activityInfo.applicationInfo != null
          && home.activityInfo.applicationInfo.uid == callerUid;
    } catch (Throwable e) {
      Debug.log(e);
      return false;
    }
  }

  private void enforceSameUid(String route) {
    if (Binder.getCallingUid() != Process.myUid()) {
      throw new SecurityException("Same-UID access required for " + route);
    }
  }

  private void enforceReadGrant(Uri uri, String route) {
    int callerUid = Binder.getCallingUid();
    if (callerUid == Process.myUid()) {
      return;
    }
    Context context = getContext();
    if (context == null || context.checkUriPermission(
        uri,
        Binder.getCallingPid(),
        callerUid,
        Intent.FLAG_GRANT_READ_URI_PERMISSION) != PackageManager.PERMISSION_GRANTED) {
      throw new SecurityException("Read grant required for " + route);
    }
  }

  /**
   * Copied from ContentResolver.java
   */
  private static int modeToMode(String mode) {
      int modeBits;
      if ("r".equals(mode)) {
          modeBits = ParcelFileDescriptor.MODE_READ_ONLY;
      } else if ("w".equals(mode) || "wt".equals(mode)) {
          modeBits = ParcelFileDescriptor.MODE_WRITE_ONLY
                  | ParcelFileDescriptor.MODE_CREATE
                  | ParcelFileDescriptor.MODE_TRUNCATE;
      } else if ("wa".equals(mode)) {
          modeBits = ParcelFileDescriptor.MODE_WRITE_ONLY
                  | ParcelFileDescriptor.MODE_CREATE
                  | ParcelFileDescriptor.MODE_APPEND;
      } else if ("rw".equals(mode)) {
          modeBits = ParcelFileDescriptor.MODE_READ_WRITE
                  | ParcelFileDescriptor.MODE_CREATE;
      } else if ("rwt".equals(mode)) {
          modeBits = ParcelFileDescriptor.MODE_READ_WRITE
                  | ParcelFileDescriptor.MODE_CREATE
                  | ParcelFileDescriptor.MODE_TRUNCATE;
      } else {
          throw new IllegalArgumentException("Invalid mode: " + mode);
      }
      return modeBits;
  }

  public static String backFileName(int widgetId) {
    return BACK_IMAGE_PREFIX + widgetId;
  }

  public static File tempBackImage(Context context) {
    return new File(context.getCacheDir(), TEMP_BACK_IMAGE_NAME);
  }

  public static File cropFile(Context context) {
    return new File(context.getCacheDir(), "crop.png");
  }

  public static File widgetBackFile(Context context, int widgetId) {
    return new File(context.getFilesDir(), backFileName(widgetId));
  }

  /** Returns the launcher-facing capability URI for a widget background image. */
  public static Uri widgetBackUri(Context context, int widgetId) {
    File backFile = widgetBackFile(context, widgetId);
    return new Uri.Builder()
        .scheme("content")
        .authority(AUTHORITY)
        .appendPath(BACK_PATH_SEGMENT)
        .appendPath(Integer.toString(widgetId))
        .appendPath(getOrCreateWidgetBackToken(context, widgetId))
        .fragment(Long.toString(backFile.lastModified()))
        .build();
  }

  private static String getExistingWidgetBackToken(Context context, int widgetId) {
    return context.getSharedPreferences(BACK_TOKEN_PREFS, Context.MODE_PRIVATE)
        .getString(BACK_TOKEN_PREFIX + widgetId, null);
  }

  private static synchronized String getOrCreateWidgetBackToken(Context context, int widgetId) {
    SharedPreferences prefs = context.getSharedPreferences(BACK_TOKEN_PREFS, Context.MODE_PRIVATE);
    String key = BACK_TOKEN_PREFIX + widgetId;
    String token = prefs.getString(key, null);
    if (token == null || token.length() < 32) {
      token = UUID.randomUUID().toString().replace("-", "") + UUID.randomUUID().toString().replace("-", "");
      if (!prefs.edit().putString(key, token).commit()) {
        throw new IllegalStateException("Unable to persist widget background capability");
      }
    }
    return token;
  }

  public static File folderShareFile(Context context) {
    return new File(context.getFilesDir(), FOLDER_SHARE_FILE_NAME);
  }

  public static File widgetShareFile(Context context) {
    return new File(context.getFilesDir(), WIDGET_SHARE_FILE_NAME);
  }
}