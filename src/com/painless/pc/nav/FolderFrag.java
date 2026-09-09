package com.painless.pc.nav;

import java.io.BufferedReader;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.io.StringReader;
import java.util.ArrayList;
import java.util.zip.ZipEntry;
import java.util.zip.ZipFile;
import java.util.zip.ZipOutputStream;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.ClipData;
import android.content.Context;
import android.content.DialogInterface;
import android.content.DialogInterface.OnClickListener;
import android.content.Intent;
import android.content.SharedPreferences;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.preference.PreferenceActivity;
import android.text.TextUtils;
import android.util.SparseBooleanArray;
import android.view.ActionMode;
import android.view.Menu;
import android.view.MenuInflater;
import android.view.MenuItem;
import android.view.View;
import android.widget.AbsListView.MultiChoiceModeListener;
import android.widget.ListView;
import android.widget.ShareActionProvider;
import android.widget.ShareActionProvider.OnShareTargetSelectedListener;
import android.widget.Toast;

import com.painless.pc.FileProvider;
import com.painless.pc.R;
import com.painless.pc.folder.FolderAdapter;
import com.painless.pc.folder.FolderPick;
import com.painless.pc.folder.FolderUtils;
import com.painless.pc.folder.FolderZipReader;
import com.painless.pc.picker.FilePicker;
import com.painless.pc.singleton.BackupUtil;
import com.painless.pc.singleton.Debug;

public class FolderFrag extends AbsListFrag implements MultiChoiceModeListener, OnShareTargetSelectedListener, OnClickListener {

  private static final int REQUEST_BACKUP = 10;
  private static final int REQUEST_RESTORE = 11;
  private static final String BACKUP_FILE_NAME = "power-toggles-folders.pcf";
  private static final long MAX_FOLDER_ARCHIVE_BYTES = 32L * 1024L * 1024L;
  private static final long MAX_FOLDER_NAMES_BYTES = 256L * 1024L;
  private static final int MAX_FOLDER_COUNT = 256;
  private static final int MAX_FOLDER_NAME_CHARS = 512;

  private Context mContext;
  private ArrayList<String> mFolderList;
  private ArrayList<String> mSelectedList;
  private FolderAdapter mAdapter;

  private ActionMode mMode;

  @Override
  public void onCreate(Bundle savedInstanceState) {
    super.onCreate(savedInstanceState);
    setHasOptionsMenu(true);
    mContext = getActivity();
  }

  @Override
  public void onViewCreated(View view, Bundle savedInstanceState) {
    super.onViewCreated(view, savedInstanceState);
    mContext = view.getContext();
    setEmptyMsg(R.string.folder_help_1, R.string.folder_help_2);

    mFolderList = new ArrayList<String>();
    mSelectedList = new ArrayList<String>();
    mAdapter = new FolderAdapter(mContext);

    getListView().setChoiceMode(ListView.CHOICE_MODE_MULTIPLE_MODAL);
    getListView().setMultiChoiceModeListener(this);

    refreshList();
    setListAdapter(mAdapter);
  }

  private void refreshList() {
    String defaultName = getString(R.string.folder_name);
    SharedPreferences prefs = mContext.getSharedPreferences(FolderUtils.PREFS, Context.MODE_PRIVATE);
    mAdapter.clear();
    mFolderList.clear();

    for (String dbName : mContext.databaseList()) {
      if (dbName.matches(FolderUtils.DB_NAME_REGX)) {
        String name = prefs.getString(FolderUtils.KEY_NAME_PREFIX + dbName, defaultName);

        mFolderList.add(dbName);
        mAdapter.add(name);
      }
    }
  }

  @Override
  public void onListItemClick(ListView l, View v, int position, long id) {
    String db = mFolderList.get(position);
    if (getActivity() instanceof PreferenceActivity) {
      Bundle extra = new Bundle();
      extra.putString("id", db);
      ((PreferenceActivity) getActivity()).startPreferencePanel(
              CFolderFrag.class.getName(),
              extra,
              R.string.lbl_customize,
              "",
              null,
              0);
    } else if (getActivity() instanceof FolderPick) {
      ((FolderPick) getActivity()).returnFolder(db, mAdapter.getItem(position));
    }
  }

  @Override
  public void onCreateOptionsMenu(Menu menu, MenuInflater inflater) {
    inflater.inflate(R.menu.folder_restore, menu);
  }

  @Override
  public boolean onOptionsItemSelected(MenuItem item) {
    if (item.getItemId() == R.id.mnu_restore) {
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
        startActivityForResult(new Intent(Intent.ACTION_OPEN_DOCUMENT)
            .addCategory(Intent.CATEGORY_OPENABLE)
            .setType("application/zip"), REQUEST_RESTORE);
      } else {
        startActivityForResult(new Intent(mContext, FilePicker.class)
            .putExtra("savemode", false)
            .putExtra("title", getString(R.string.wp_restore))
            .putExtra("filter", ".pcf"), REQUEST_RESTORE);
      }
    }
    return true;
  }

  @Override
  public void onActivityResult(int requestCode, int resultCode, Intent data) {
    if (resultCode != Activity.RESULT_OK || data == null) {
      return;
    }
    if (requestCode == REQUEST_BACKUP) {
      String[] msgArray = getResources().getStringArray(R.array.wc_export_msg);
      try {
        Uri destination = data.getData();
        String displayDestination;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT && destination != null) {
          OutputStream out = mContext.getContentResolver().openOutputStream(destination, "w");
          if (out == null) {
            throw new Exception("Unable to open folder backup destination");
          }
          saveFolders(out);
          displayDestination = destination.toString();
        } else {
          String fileName = data.getStringExtra("file");
          if (fileName == null) {
            throw new Exception("Folder backup destination missing");
          }
          saveFolders(new FileOutputStream(fileName));
          displayDestination = fileName;
        }
        String msg = String.format(msgArray[1], displayDestination);
        Toast.makeText(mContext, msg, Toast.LENGTH_LONG).show();
        if (mMode != null) {
          mMode.finish();
        }
      } catch (Throwable e) {
        Debug.log(e);
        Toast.makeText(mContext, msgArray[2], Toast.LENGTH_LONG).show();
      }
    } else if (requestCode == REQUEST_RESTORE) {
      try {
        Uri source = data.getData();
        int restored;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT && source != null) {
          restored = restoreBackup(source);
        } else {
          String fileName = data.getStringExtra("file");
          if (fileName == null) {
            throw new Exception("Folder restore source missing");
          }
          restored = restoreBackup(fileName);
        }
        Toast.makeText(mContext, getString(R.string.folder_restore_msg, restored), Toast.LENGTH_LONG).show();
      } catch (Exception e) {
        Debug.log(e);
        Toast.makeText(mContext, R.string.folder_restore_error, Toast.LENGTH_LONG).show();
      }
      refreshList();
    }
  }

  private int restoreBackup(Uri source) throws Exception {
    File temp = File.createTempFile("power_toggles_folder_restore_", ".pcf", mContext.getCacheDir());
    InputStream in = null;
    FileOutputStream out = null;
    try {
      in = mContext.getContentResolver().openInputStream(source);
      if (in == null) {
        throw new Exception("Unable to open folder restore source");
      }
      out = new FileOutputStream(temp);
      BackupUtil.copy(in, out, MAX_FOLDER_ARCHIVE_BYTES);
      out.flush();
      out.close();
      out = null;
      in.close();
      in = null;
      return restoreBackup(temp.getAbsolutePath());
    } finally {
      if (out != null) {
        try { out.close(); } catch (Exception e) { Debug.log(e); }
      }
      if (in != null) {
        try { in.close(); } catch (Exception e) { Debug.log(e); }
      }
      if (temp.exists() && !temp.delete()) {
        Debug.log(new Exception("Unable to delete temporary folder restore file"));
      }
    }
  }

  private int restoreBackup(String fileName) throws Exception {
    File archive = new File(fileName);
    if (!archive.isFile() || archive.length() > MAX_FOLDER_ARCHIVE_BYTES) {
      throw new Exception("Folder backup is invalid or too large");
    }

    ZipFile zip = null;
    BufferedReader reader = null;
    InputStream namesIn = null;
    ByteArrayOutputStream namesOut = null;
    try {
      zip = new ZipFile(archive);
      ZipEntry namesEntry = zip.getEntry("folders.txt");
      if (namesEntry == null) {
        throw new Exception("Folder backup is missing folders.txt");
      }
      if (namesEntry.getSize() > MAX_FOLDER_NAMES_BYTES) {
        throw new Exception("Folder backup names list is too large");
      }
      namesIn = zip.getInputStream(namesEntry);
      namesOut = new ByteArrayOutputStream();
      BackupUtil.copy(namesIn, namesOut, MAX_FOLDER_NAMES_BYTES);
      namesIn.close();
      namesIn = null;
      reader = new BufferedReader(new StringReader(new String(namesOut.toByteArray(), "UTF-8")));

      FolderZipReader folderReader = new FolderZipReader(mContext, zip);
      String line;
      int count = 0;
      while ((line = reader.readLine()) != null) {
        if (count >= MAX_FOLDER_COUNT || line.length() > MAX_FOLDER_NAME_CHARS) {
          throw new Exception("Folder backup metadata exceeds supported limits");
        }
        folderReader.readEntry(line, count);
        count++;
      }
      return folderReader.writeAll();
    } finally {
      if (reader != null) {
        try { reader.close(); } catch (Exception e) { Debug.log(e); }
      }
      if (namesIn != null) {
        try { namesIn.close(); } catch (Exception e) { Debug.log(e); }
      }
      if (namesOut != null) {
        try { namesOut.close(); } catch (Exception e) { Debug.log(e); }
      }
      if (zip != null) {
        try { zip.close(); } catch (Exception e) { Debug.log(e); }
      }
    }
  }

  private void saveFolders(OutputStream os) throws Exception {
    ZipOutputStream outStream = null;
    String defaultName = getString(R.string.folder_name);
    SharedPreferences prefs = mContext.getSharedPreferences(FolderUtils.PREFS, Context.MODE_PRIVATE);
    try {
      outStream = new ZipOutputStream(os);
      int i = 0;
      ArrayList<String> dbNames = new ArrayList<String>();
      for (String db : mSelectedList) {
        BackupUtil.addDbToZip(db, outStream, mContext, i);
        i++;
        dbNames.add(prefs.getString(FolderUtils.KEY_NAME_PREFIX + db, defaultName));
      }

      outStream.putNextEntry(new ZipEntry("folders.txt"));
      outStream.write(TextUtils.join("\n", dbNames).getBytes("UTF-8"));
      outStream.closeEntry();
    } finally {
      if (outStream != null) {
        outStream.close();
      }
    }
  }

  ///////// code for share
  private void setSelectedList() {
    mSelectedList.clear();
    SparseBooleanArray checked = getListView().getCheckedItemPositions();

    for (int i = 0; i<checked.size(); i++) {
      if (checked.valueAt(i)) {
        mSelectedList.add(mFolderList.get(checked.keyAt(i)));
      }
    }
  }

  private Intent buildShareIntent() {
    Uri shareUri = Uri.parse(FileProvider.FOLDER_SHARE_URI);
    Intent intent = new Intent(Intent.ACTION_SEND)
        .setType("application/zip")
        .putExtra(Intent.EXTRA_STREAM, shareUri)
        .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.JELLY_BEAN) {
      intent.setClipData(ClipData.newRawUri("Power Toggles folder backup", shareUri));
    }
    return intent;
  }

  @Override
  public boolean onShareTargetSelected(ShareActionProvider source, Intent intent) {
    setSelectedList();
    if (mSelectedList.size() < 1) {
      return false;
    }
    try {
      saveFolders(new FileOutputStream(FileProvider.folderShareFile(mContext)));
      if (mMode != null) {
        mMode.finish();
      }
      return true;
    } catch (Exception e) {
      Debug.log(e);
      return false;
    }
  }

  ///////// code for multi-select
  @Override
  public boolean onCreateActionMode(ActionMode mode, Menu menu) {
    mode.getMenuInflater().inflate(R.menu.folder_menu, menu);
    ShareActionProvider shareAction = (ShareActionProvider) menu.findItem(R.id.mnu_share).getActionProvider();
    shareAction.setOnShareTargetSelectedListener(this);
    shareAction.setShareIntent(buildShareIntent());
    mMode = mode;
    return true;
  }

  @Override
  public boolean onActionItemClicked(ActionMode mode, MenuItem item) {
    setSelectedList();

    if (mSelectedList.size() < 1) {
      return false;
    }
    if (item.getItemId() == R.id.mnu_delete) {
      new AlertDialog.Builder(mContext)
        .setMessage(getString(R.string.folder_delete_prompt, mSelectedList.size()))
        .setNegativeButton(R.string.act_no, null)
        .setPositiveButton(R.string.act_yes, this)
        .show();
    } else if (item.getItemId() == R.id.mnu_backup) {
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
        startActivityForResult(new Intent(Intent.ACTION_CREATE_DOCUMENT)
            .addCategory(Intent.CATEGORY_OPENABLE)
            .setType("application/zip")
            .putExtra(Intent.EXTRA_TITLE, BACKUP_FILE_NAME), REQUEST_BACKUP);
      } else {
        startActivityForResult(new Intent(mContext, FilePicker.class)
            .putExtra("savemode", true)
            .putExtra("title", getString(R.string.wp_backup))
            .putExtra("filter", ".pcf"), REQUEST_BACKUP);
      }
    }
    return true;
  }

  @Override
  public void onDestroyActionMode(ActionMode mode) {
    if (mMode == mode) {
      mMode = null;
    }
  }

  @Override
  public void onItemCheckedStateChanged(ActionMode mode, int position, long id, boolean checked) { }

  @Override
  public boolean onPrepareActionMode(ActionMode mode, Menu menu) {
    return false;
  }

  /**
   * Called when deleting multiple folders and accepting the confirmation prompt.
   */
  @Override
  public void onClick(DialogInterface dialog, int which) {
    SharedPreferences.Editor editor = mContext.getSharedPreferences(FolderUtils.PREFS, Context.MODE_PRIVATE).edit();
    for (String folderId : mSelectedList) {
      editor.remove(FolderUtils.KEY_NAME_PREFIX + folderId);
      mContext.deleteDatabase(folderId);
    }
    editor.commit();
    if (mMode != null) {
      mMode.finish();
    }
    refreshList();
  }
}
