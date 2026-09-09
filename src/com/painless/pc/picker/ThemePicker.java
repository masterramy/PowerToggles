package com.painless.pc.picker;

import static com.painless.pc.util.SettingsDecoder.KEY_COLORS;
import static com.painless.pc.util.SettingsDecoder.KEY_DENSITY;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.util.zip.ZipEntry;
import java.util.zip.ZipFile;

import org.json.JSONObject;

import android.app.ListActivity;
import android.content.Intent;
import android.database.Cursor;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.net.Uri;
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
import com.painless.pc.singleton.BackupUtil;
import com.painless.pc.singleton.Debug;
import com.painless.pc.util.BitmapImportUtils;
import com.painless.pc.util.SettingsDecoder;
import com.painless.pc.util.Thunk;
import com.painless.pc.util.WidgetSetting;

/**
 * Theme browser for built-in, imported, and pre-SAF legacy local themes.
 *
 * The original online catalog was hosted on a retired Google Drive endpoint and
 * is intentionally no longer contacted. Modern Android exposes explicit SAF
 * import instead, so opening this screen never waits on a known-dead network
 * service or suggests that a remote gallery is still available.
 */
public class ThemePicker extends ListActivity implements OnItemClickListener {

  private static final String THEME_EXTENSION = ".pttheme";
  private static final String IMPORT_DIR = "imported-themes";
  private static final int MENU_IMPORT_THEME = 1;
  private static final int REQUEST_IMPORT_THEME = 1001;
  private static final long MAX_THEME_BYTES = 8L * 1024L * 1024L;
  private static final int MAX_CONFIG_CHARS = 64 * 1024;
  private static final int MAX_THEME_DIMENSION = 2048;
  private static final long MAX_THEME_PIXELS = 4L * 1024L * 1024L;
  private static final int MAX_LOCAL_THEMES = 256;

  @Thunk ThemeAdapter mAdapter;

  private boolean mLocalHeaderAdded = false;
  private int mLocalInsertPosition = 0;
  private int mLocalCount = 0;

  @Override
  protected void onCreate(Bundle savedInstanceState) {
    super.onCreate(savedInstanceState);
    setResult(RESULT_CANCELED);

    mAdapter = new ThemeAdapter(this);

    if (getIntent().getBooleanExtra("folders", false)) {
      ThemeEntry header = new ThemeEntry();
      header.title = R.string.tm_system;
      mAdapter.add(header);

      try {
        ThemeEntry entry = new ThemeEntry();
        entry.config = new JSONObject(SettingsDecoder.CONFIG_DARK);
        entry.backgroundRes = R.drawable.folder_back;
        entry.hideDividers = true;
        WidgetSetting.parseColors(new SettingsDecoder(entry.config), KEY_COLORS,
            entry.buttonColors, entry.buttonAlphas);
        mAdapter.add(entry);
      } catch (Exception e) {
        Debug.log(e);
      }
    }

    mLocalInsertPosition = mAdapter.getCount();
    addThemeFiles(getImportedThemeDir());

    // Preserve discovery of historical /Power Toggles files only on devices
    // predating Storage Access Framework. Android 4.4+ uses explicit import.
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.KITKAT) {
      addThemeFiles(new File(Environment.getExternalStorageDirectory(), "Power Toggles"));
    }

    setListAdapter(mAdapter);
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
      // .pttheme is a ZIP container without a registered MIME type. Validate
      // content rather than trusting provider extension/MIME metadata.
      intent.setType("*/*");
      startActivityForResult(intent, REQUEST_IMPORT_THEME);
      return true;
    }
    return super.onOptionsItemSelected(item);
  }

  @Override
  protected void onActivityResult(int requestCode, int resultCode, Intent data) {
    super.onActivityResult(requestCode, resultCode, data);
    if (requestCode != REQUEST_IMPORT_THEME || resultCode != RESULT_OK
        || data == null || data.getData() == null) {
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
        if (isFinishing()) {
          return;
        }
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
        BackupUtil.copy(in, out, MAX_THEME_BYTES);
        out.flush();
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
      if (!promoted && temp.exists() && !temp.delete()) {
        Debug.log(new Exception("Unable to delete rejected theme import"));
      }
    }
  }

  private void validateThemeFile(File file) throws Exception {
    if (file == null || !file.isFile() || file.length() > MAX_THEME_BYTES) {
      throw new IOException("Theme archive is invalid or too large");
    }

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
        configReader = new BufferedReader(new InputStreamReader(zip.getInputStream(configEntry), "UTF-8"));
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

      byte[] imageBytes = readEntry(zip, backEntry, MAX_THEME_BYTES);
      Bitmap image = BitmapImportUtils.decode(imageBytes);
      if (image == null || image.getWidth() > MAX_THEME_DIMENSION || image.getHeight() > MAX_THEME_DIMENSION
          || ((long) image.getWidth() * (long) image.getHeight()) > MAX_THEME_PIXELS) {
        if (image != null) {
          image.recycle();
        }
        throw new IOException("Invalid or oversized theme image");
      }
      image.recycle();
    } finally {
      if (zip != null) {
        try { zip.close(); } catch (Exception e) { Debug.log(e); }
      }
    }
  }

  private static byte[] readEntry(ZipFile zip, ZipEntry entry, long maxBytes) throws Exception {
    InputStream in = null;
    java.io.ByteArrayOutputStream out = new java.io.ByteArrayOutputStream();
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

  private String getDisplayName(Uri uri) {
    Cursor cursor = null;
    try {
      cursor = getContentResolver().query(uri,
          new String[] { OpenableColumns.DISPLAY_NAME }, null, null, null);
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
        try { cursor.close(); } catch (Exception e) { Debug.log(e); }
      }
    }
    return uri.getLastPathSegment();
  }

  private File uniqueThemeDestination(File dir, String displayName) throws IOException {
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
    while (candidate.exists() && suffix <= MAX_LOCAL_THEMES) {
      candidate = new File(dir, stem + "-" + suffix + THEME_EXTENSION);
      suffix++;
    }
    if (candidate.exists()) {
      throw new IOException("Too many imported themes with the same name");
    }
    return candidate;
  }

  private File getImportedThemeDir() {
    return new File(getFilesDir(), IMPORT_DIR);
  }

  private void addThemeFiles(File themeDir) {
    if (mLocalCount >= MAX_LOCAL_THEMES || !themeDir.exists() || !themeDir.isDirectory()) {
      return;
    }
    File[] files = themeDir.listFiles();
    if (files == null) {
      return;
    }
    java.util.Arrays.sort(files);
    for (File f : files) {
      if (mLocalCount >= MAX_LOCAL_THEMES) {
        break;
      }
      if (f.isFile() && f.getName().endsWith(THEME_EXTENSION)) {
        addLocalTheme(f);
      }
    }
  }

  private void addLocalTheme(File file) {
    if (file == null || mLocalCount >= MAX_LOCAL_THEMES) {
      return;
    }
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
  protected void onDestroy() {
    if (mAdapter != null) {
      mAdapter.mLoader.destroy();
    }
    super.onDestroy();
  }

  @Override
  public void onItemClick(AdapterView<?> parent, View view, int position, long id) {
    ThemeEntry entry = mAdapter.getItem(position);
    if (entry != null && entry.isLoaded() && entry.config != null) {
      setResult(RESULT_OK, new Intent()
          .putExtra("config", entry.config.toString())
          .putExtra("icon", entry.background));
      finish();
    }
  }
}
