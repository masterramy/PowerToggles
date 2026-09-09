package com.painless.pc.picker;

import static com.painless.pc.util.SettingsDecoder.KEY_COLORS;
import static com.painless.pc.util.SettingsDecoder.KEY_DENSITY;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.net.URL;
import java.net.URLConnection;
import java.util.zip.ZipEntry;
import java.util.zip.ZipFile;

import org.json.JSONException;
import org.json.JSONObject;

import android.app.ListActivity;
import android.content.Intent;
import android.database.Cursor;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.net.Uri;
import android.net.http.HttpResponseCache;
import android.os.AsyncTask;
import android.os.Build;
import android.os.Bundle;
import android.os.Environment;
import android.provider.OpenableColumns;
import android.view.Menu;
import android.view.MenuItem;
import android.view.View;
import android.widget.AdapterView;
import android.widget.AdapterView.OnItemClickListener;
import android.widget.Toast;

import com.painless.pc.R;
import com.painless.pc.picker.theme.ThemeAdapter;
import com.painless.pc.picker.theme.ThemeEntry;
import com.painless.pc.singleton.Debug;
import com.painless.pc.util.SettingsDecoder;
import com.painless.pc.util.Thunk;
import com.painless.pc.util.WidgetSetting;

public class ThemePicker extends ListActivity implements OnItemClickListener {

  private static final String BASE_URL = "https://b4ed1c0ec81643f5b9ce1c461688fb066bf383db-www.googledrive.com/host/0B94XoKFv6ejBZ3VkTzhYX05SOGc/";
  private static final String IMAGE_URL = BASE_URL + "bg/";

  private static final String THEME_EXTENSION = ".pttheme";
  private static final String IMPORT_DIR = "imported-themes";
  private static final int MENU_IMPORT_THEME = 1;
  private static final int REQUEST_IMPORT_THEME = 1001;
  private static final long MAX_THEME_BYTES = 8L * 1024L * 1024L;
  private static final int MAX_CONFIG_CHARS = 64 * 1024;
  private static final int MAX_THEME_DIMENSION = 2048;
  private static final long MAX_THEME_PIXELS = 4L * 1024L * 1024L;
  private static final int MAX_REMOTE_ENTRIES = 100;
  private static final int NETWORK_TIMEOUT_MS = 5000;

  @Thunk ThemeAdapter mAdapter;
  @Thunk boolean mRemoteHeaderAdded = false;
  @Thunk ThemeEntry mServerLoadEntry;

  private boolean mLocalHeaderAdded = false;
  private int mLocalInsertPosition = 0;
  private int mLocalCount = 0;
  private int mRemoteCount = 0;

  @Override
  protected void onCreate(Bundle savedInstanceState) {
    super.onCreate(savedInstanceState);
    setResult(RESULT_CANCELED);

    mAdapter = new ThemeAdapter(this);

    final String themeUrl;

    if (getIntent().getBooleanExtra("folders", false)) {
      ThemeEntry header = new ThemeEntry();
      header.title = R.string.tm_system;
      mAdapter.add(header);

      try {
        ThemeEntry entry = new ThemeEntry();
        entry.config = new JSONObject(SettingsDecoder.CONFIG_DARK);
        entry.backgroundRes = R.drawable.folder_back;
        entry.hideDividers = true;
        WidgetSetting.parseColors(new SettingsDecoder(entry.config), KEY_COLORS, entry.buttonColors, entry.buttonAlphas);
        mAdapter.add(entry);
      } catch (Exception e) {
        Debug.log(e);
      }

      themeUrl = BASE_URL + "folders.txt";
    } else {
      themeUrl = BASE_URL + "themes.txt";
    }

    mLocalInsertPosition = mAdapter.getCount();
    addThemeFiles(getImportedThemeDir());

    // Preserve the legacy shared-root discovery contract only for pre-SAF devices.
    // Modern Android uses explicit document import into app-private storage below.
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.KITKAT) {
      addThemeFiles(new File(Environment.getExternalStorageDirectory(), "Power Toggles"));
    }

    setListAdapter(mAdapter);

    // Install http cache
    try {
      File httpCacheDir = new File(getCacheDir(), "http");
      long httpCacheSize = 4 * 1024 * 1024; // 4 MiB
      HttpResponseCache.install(httpCacheDir, httpCacheSize);
    } catch (IOException e) {
      Debug.log(e);
    }

    mServerLoadEntry = new ThemeEntry();
    mAdapter.add(mServerLoadEntry);

    // Load the legacy remote catalog defensively. The remote service is optional;
    // local/system themes remain usable and failure becomes an explicit terminal state.
    new AsyncTask<Void, ThemeEntry, Boolean>() {

      @Override
      protected Boolean doInBackground(Void... arg0) {
        BufferedReader reader = null;
        try {
          URLConnection connection = new URL(themeUrl).openConnection();
          connection.setConnectTimeout(NETWORK_TIMEOUT_MS);
          connection.setReadTimeout(NETWORK_TIMEOUT_MS);
          reader = new BufferedReader(new InputStreamReader(connection.getInputStream()));
          String line;
          int accepted = 0;
          while (accepted < MAX_REMOTE_ENTRIES && (line = readBoundedLine(reader)) != null) {
            try {
              ThemeEntry entry = new ThemeEntry();
              entry.config = new JSONObject(line);
              String themeId = entry.config.getString("id");
              if (!themeId.matches("[A-Za-z0-9_-]{1,80}")) {
                continue;
              }
              entry.remoteUrl = new URL(IMAGE_URL + themeId + ".png");
              publishProgress(entry);
              accepted++;
            } catch (JSONException e) {
              Debug.log(e);
            }
          }
          return true;
        } catch (Exception e) {
          Debug.log(e);
          return false;
        } finally {
          if (reader != null) {
            try {
              reader.close();
            } catch (Exception e) {
              Debug.log(e);
            }
          }
        }
      }

      @Override
      protected void onProgressUpdate(ThemeEntry... objs) {
        mAdapter.remove(mServerLoadEntry);
        if (!mRemoteHeaderAdded) {
          ThemeEntry header = new ThemeEntry();
          header.title = R.string.tm_remote;
          mAdapter.add(header);
          mRemoteHeaderAdded = true;
        }
        mRemoteCount++;
        mAdapter.add(objs[0]);
      }

      @Override
      protected void onPostExecute(Boolean catalogReached) {
        mAdapter.remove(mServerLoadEntry);
        if (mRemoteCount == 0) {
          ThemeEntry unavailable = new ThemeEntry();
          unavailable.title = R.string.tm_remote_unavailable;
          mAdapter.add(unavailable);
        }
        mAdapter.notifyDataSetChanged();
      }
    }.execute();

    getListView().setOnItemClickListener(this);
  }

  @Override
  public boolean onCreateOptionsMenu(Menu menu) {
    menu.add(Menu.NONE, MENU_IMPORT_THEME, Menu.NONE, R.string.tm_import)
        .setShowAsAction(MenuItem.SHOW_AS_ACTION_IF_ROOM);
    return true;
  }

  @Override
  public boolean onOptionsItemSelected(MenuItem item) {
    if (item.getItemId() == MENU_IMPORT_THEME) {
      Intent intent = new Intent(Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT
          ? Intent.ACTION_OPEN_DOCUMENT
          : Intent.ACTION_GET_CONTENT);
      intent.addCategory(Intent.CATEGORY_OPENABLE);
      // .pttheme is a ZIP container without a registered MIME type. Validate the
      // selected content rather than trusting provider extension/MIME metadata.
      intent.setType("*/*");
      startActivityForResult(intent, REQUEST_IMPORT_THEME);
      return true;
    }
    return super.onOptionsItemSelected(item);
  }

  @Override
  protected void onActivityResult(int requestCode, int resultCode, Intent data) {
    super.onActivityResult(requestCode, resultCode, data);
    if (requestCode != REQUEST_IMPORT_THEME || resultCode != RESULT_OK || data == null || data.getData() == null) {
      return;
    }
    importTheme(data.getData());
  }

  private void importTheme(final Uri uri) {
    new AsyncTask<Void, Void, File>() {

      @Override
      protected File doInBackground(Void... params) {
        try {
          return copyAndValidateTheme(uri);
        } catch (Exception e) {
          Debug.log(e);
          return null;
        }
      }

      @Override
      protected void onPostExecute(File imported) {
        if (imported == null) {
          Toast.makeText(ThemePicker.this, R.string.tm_import_failed, Toast.LENGTH_LONG).show();
          return;
        }
        addLocalTheme(imported);
        mAdapter.notifyDataSetChanged();
        Toast.makeText(ThemePicker.this, R.string.tm_import_success, Toast.LENGTH_SHORT).show();
      }
    }.execute();
  }

  private File copyAndValidateTheme(Uri uri) throws Exception {
    File dir = getImportedThemeDir();
    if (!dir.exists() && !dir.mkdirs()) {
      throw new IOException("Unable to create imported theme directory");
    }

    File temp = File.createTempFile("theme-import-", ".tmp", dir);
    boolean promoted = false;
    try {
      InputStream in = null;
      FileOutputStream out = null;
      try {
        in = getContentResolver().openInputStream(uri);
        if (in == null) {
          throw new IOException("Unable to open selected theme");
        }
        out = new FileOutputStream(temp);
        byte[] buffer = new byte[8192];
        long total = 0;
        int read;
        while ((read = in.read(buffer)) != -1) {
          total += read;
          if (total > MAX_THEME_BYTES) {
            throw new IOException("Theme archive is too large");
          }
          out.write(buffer, 0, read);
        }
      } finally {
        if (out != null) {
          try { out.close(); } catch (Exception e) { Debug.log(e); }
        }
        if (in != null) {
          try { in.close(); } catch (Exception e) { Debug.log(e); }
        }
      }

      validateThemeFile(temp);

      File destination = uniqueThemeDestination(dir, getDisplayName(uri));
      if (!temp.renameTo(destination)) {
        throw new IOException("Unable to promote imported theme");
      }
      promoted = true;
      return destination;
    } finally {
      if (!promoted) {
        temp.delete();
      }
    }
  }

  private void validateThemeFile(File file) throws Exception {
    ZipFile zip = null;
    try {
      zip = new ZipFile(file);
      ZipEntry configEntry = zip.getEntry("theme.txt");
      ZipEntry backEntry = zip.getEntry("back.png");
      if (configEntry == null || backEntry == null) {
        throw new IOException("Theme must contain theme.txt and back.png");
      }

      BufferedReader configReader = null;
      String configLine;
      try {
        configReader = new BufferedReader(new InputStreamReader(zip.getInputStream(configEntry)));
        configLine = readBoundedLine(configReader);
      } finally {
        if (configReader != null) {
          try { configReader.close(); } catch (Exception e) { Debug.log(e); }
        }
      }
      if (configLine == null || configLine.length() == 0) {
        throw new IOException("Theme configuration is empty");
      }

      JSONObject config = new JSONObject(configLine);
      SettingsDecoder decoder = new SettingsDecoder(config);
      int density = decoder.getValue(KEY_DENSITY, getResources().getDisplayMetrics().densityDpi);
      if (density <= 0 || density > 1000) {
        throw new IOException("Invalid theme density");
      }

      BitmapFactory.Options bounds = new BitmapFactory.Options();
      bounds.inJustDecodeBounds = true;
      InputStream boundsStream = null;
      try {
        boundsStream = zip.getInputStream(backEntry);
        BitmapFactory.decodeStream(boundsStream, null, bounds);
      } finally {
        if (boundsStream != null) {
          try { boundsStream.close(); } catch (Exception e) { Debug.log(e); }
        }
      }
      if (bounds.outWidth <= 0 || bounds.outHeight <= 0
          || bounds.outWidth > MAX_THEME_DIMENSION || bounds.outHeight > MAX_THEME_DIMENSION
          || ((long) bounds.outWidth * (long) bounds.outHeight) > MAX_THEME_PIXELS) {
        throw new IOException("Invalid or oversized theme image");
      }

      InputStream imageStream = null;
      Bitmap image = null;
      try {
        imageStream = zip.getInputStream(backEntry);
        image = BitmapFactory.decodeStream(imageStream);
        if (image == null) {
          throw new IOException("Unable to decode theme image");
        }
      } finally {
        if (image != null) {
          image.recycle();
        }
        if (imageStream != null) {
          try { imageStream.close(); } catch (Exception e) { Debug.log(e); }
        }
      }
    } finally {
      if (zip != null) {
        try { zip.close(); } catch (Exception e) { Debug.log(e); }
      }
    }
  }

  private String getDisplayName(Uri uri) {
    Cursor cursor = null;
    try {
      cursor = getContentResolver().query(uri, new String[] { OpenableColumns.DISPLAY_NAME }, null, null, null);
      if (cursor != null && cursor.moveToFirst()) {
        int index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME);
        if (index >= 0) {
          return cursor.getString(index);
        }
      }
    } catch (Exception e) {
      Debug.log(e);
    } finally {
      if (cursor != null) {
        cursor.close();
      }
    }
    return uri.getLastPathSegment();
  }

  private File uniqueThemeDestination(File dir, String displayName) {
    String name = displayName == null ? "imported-theme" : displayName;
    name = name.replaceAll("[^A-Za-z0-9._ -]", "_");
    if (name.length() == 0) {
      name = "imported-theme";
    }
    if (name.length() > 80) {
      name = name.substring(0, 80);
    }
    if (!name.endsWith(THEME_EXTENSION)) {
      name += THEME_EXTENSION;
    }

    String stem = name.substring(0, name.length() - THEME_EXTENSION.length());
    File candidate = new File(dir, name);
    int suffix = 1;
    while (candidate.exists()) {
      candidate = new File(dir, stem + "-" + suffix + THEME_EXTENSION);
      suffix++;
    }
    return candidate;
  }

  private File getImportedThemeDir() {
    return new File(getFilesDir(), IMPORT_DIR);
  }

  private void addThemeFiles(File themeDir) {
    if (!themeDir.exists() || !themeDir.isDirectory()) {
      return;
    }
    File[] files = themeDir.listFiles();
    if (files == null) {
      return;
    }
    for (File f : files) {
      if (f.isFile() && f.getName().endsWith(THEME_EXTENSION)) {
        addLocalTheme(f);
      }
    }
  }

  private void addLocalTheme(File file) {
    if (!mLocalHeaderAdded) {
      ThemeEntry header = new ThemeEntry();
      header.title = R.string.tm_local;
      mAdapter.insert(header, mLocalInsertPosition);
      mLocalHeaderAdded = true;
    }

    ThemeEntry theme = new ThemeEntry();
    theme.themeFile = file;
    mAdapter.insert(theme, mLocalInsertPosition + 1 + mLocalCount);
    mLocalCount++;
  }

  private static String readBoundedLine(BufferedReader reader) throws IOException {
    StringBuilder result = new StringBuilder();
    boolean sawAny = false;
    int value;
    while ((value = reader.read()) != -1) {
      sawAny = true;
      if (value == '\n' || value == '\r') {
        break;
      }
      if (result.length() >= MAX_CONFIG_CHARS) {
        throw new IOException("Theme configuration line is too large");
      }
      result.append((char) value);
    }
    return !sawAny && result.length() == 0 ? null : result.toString();
  }

  @Override
  protected void onPause() {
    HttpResponseCache cache = HttpResponseCache.getInstalled();
    if (cache != null) {
      cache.flush();
    }
    super.onPause();
  }

  @Override
  protected void onDestroy() {
    if (mAdapter != null) {
      mAdapter.mLoader.destroy();
    }
    super.onDestroy();
  }

  @Override
  public void onItemClick(AdapterView<?> parent, View view, int position, long id) {
    ThemeEntry entry = mAdapter.getItem(position);
    if (entry.isLoaded()) {
      setResult(RESULT_OK, new Intent()
          .putExtra("config", entry.config.toString())
          .putExtra("icon", entry.background));
      finish();
    }
  }
}
