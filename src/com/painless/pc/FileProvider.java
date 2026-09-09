package com.painless.pc;

import android.content.ContentProvider;
import android.content.ContentValues;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
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

/**
 * {@link ContentProvider} for background images and other internal files.
 */
public class FileProvider extends ContentProvider {

  public static final String FOLDER_SHARE_URI = "content://com.painless.pc.file/folder-share";
  public static final String CROP_URI = "content://com.painless.pc.file/crop";

  private static final String TEMP_BACK_IMAGE_NAME = "cback";
  private static final String BACK_IMAGE_PREFIX = "back_";
  private static final String FOLDER_SHARE_FILE_NAME = "folder.pcf";
  private static final String FOLDER_SHARE_PATH = "/folder-share";
  private static final String CONFIG_PATH = "/config";
  private static final String CROP_PATH = "/crop";

  @Override
  public boolean onCreate() {
    return true;
  }

  @Override
  public Cursor query(Uri uri, String[] projection, String selection, String[] selectionArgs, String sortOrder) {
    Debug.log(uri);
    if (!FOLDER_SHARE_PATH.equals(uri.getPath())) {
      return null;
    }

    String[] columns = projection;
    if (columns == null) {
      columns = new String[] { OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE };
    }
    MatrixCursor result = new MatrixCursor(columns, 1);
    Object[] row = new Object[columns.length];
    File file = folderShareFile(getContext());
    for (int i = 0; i < columns.length; i++) {
      if (OpenableColumns.DISPLAY_NAME.equals(columns[i])) {
        row[i] = FOLDER_SHARE_FILE_NAME;
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
    return FOLDER_SHARE_PATH.equals(uri.getPath()) ? "application/zip" : "image/png";
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
    } else if (path != null && path.startsWith("/back")) {
      // Launcher/AppWidget hosts consume this route through RemoteViews. Preserve the
      // historical read contract until exact host grant behavior can be runtime-certified.
      if (!"r".equals(mode)) {
        throw new FileNotFoundException("Widget background is read-only");
      }
      try {
        result = widgetBackFile(getContext(), Integer.parseInt(uri.getQuery()));
      } catch (Exception e) {
        throw new FileNotFoundException();
      }
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

  public static File folderShareFile(Context context) {
    return new File(context.getFilesDir(), FOLDER_SHARE_FILE_NAME);
  }
}
