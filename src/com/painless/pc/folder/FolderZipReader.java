package com.painless.pc.folder;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.zip.ZipEntry;
import java.util.zip.ZipFile;

import android.content.Context;
import android.content.SharedPreferences;

import com.painless.pc.singleton.BackupUtil;
import com.painless.pc.singleton.Debug;
import com.painless.pc.util.Thunk;

/**
 * A helper class to reading folder backups from zip.
 */
public class FolderZipReader {

  private static final int MAX_FOLDER_COUNT = 256;
  private static final long MAX_FOLDER_DB_BYTES = 16L * 1024L * 1024L;
  private static final long MAX_TOTAL_FOLDER_DB_BYTES = 64L * 1024L * 1024L;

  private final ArrayList<ParseData> mParsedList = new ArrayList<ParseData>();
  private final HashSet<String> mIgnoreDbNames = new HashSet<String>();

  private final Context context;
  private final ZipFile zip;
  private boolean mStaged;
  private boolean mCommitted;

  public FolderZipReader(Context context, ZipFile zip) {
    this.zip = zip;
    this.context = context;
  }

  /**
   * Reads the folder entry and returns the reserved destination db name.
   */
  public String readEntry(String folderName, int folderId) throws Exception {
    if (mParsedList.size() >= MAX_FOLDER_COUNT) {
      throw new Exception("Folder backup contains too many folders");
    }

    String dbName = FolderUtils.getDbName(folderId);
    ZipEntry folderEntry = zip.getEntry(dbName);
    if (folderEntry == null) {
      // Folder data not present.
      throw new Exception("Folder database entry missing");
    }

    ParseData parseData = new ParseData();
    parseData.destName = FolderUtils.newDbName(context, mIgnoreDbNames);
    parseData.folderName = folderName;
    parseData.srcEntry = folderEntry;

    // Add the new dest name to ignore names, so that it is not picked up next time.
    mIgnoreDbNames.add(parseData.destName);
    mParsedList.add(parseData);
    return parseData.destName;
  }

  /**
   * Copies every embedded folder database into app-private cache files without
   * publishing either the database path or the folder name. This lets callers
   * preview an imported widget and roll it back safely if the editor is cancelled.
   */
  public synchronized int stageAll() throws Exception {
    if (mCommitted || mStaged) {
      return mParsedList.size();
    }

    long totalBytes = 0;
    try {
      for (ParseData parseData : mParsedList) {
        if (Thread.currentThread().isInterrupted()) {
          throw new java.io.InterruptedIOException("Folder import cancelled");
        }
        File stagedFile = File.createTempFile("pt_folder_restore_", ".db", context.getCacheDir());
        parseData.stagedFile = stagedFile;
        FileOutputStream out = null;
        InputStream in = null;
        try {
          out = new FileOutputStream(stagedFile);
          in = zip.getInputStream(parseData.srcEntry);
          long remainingTotal = MAX_TOTAL_FOLDER_DB_BYTES - totalBytes;
          if (remainingTotal <= 0) {
            throw new Exception("Folder backup exceeds total database size limit");
          }
          long copied = BackupUtil.copy(in, out, Math.min(MAX_FOLDER_DB_BYTES, remainingTotal));
          out.flush();
          totalBytes += copied;
        } finally {
          if (in != null) {
            try { in.close(); } catch (Exception e) { Debug.log(e); }
          }
          if (out != null) {
            try { out.close(); } catch (Exception e) { Debug.log(e); }
          }
        }
      }
      mStaged = true;
      return mParsedList.size();
    } catch (Exception e) {
      cleanupStagedFiles();
      throw e;
    }
  }

  /**
   * Publishes staged folder databases and names. No existing database is ever
   * overwritten: a destination collision aborts the whole transaction.
   */
  public synchronized int commitAll() throws Exception {
    if (mCommitted) {
      return mParsedList.size();
    }
    if (!mStaged) {
      stageAll();
    }

    ArrayList<File> publishedFiles = new ArrayList<File>();
    try {
      for (ParseData parseData : mParsedList) {
        if (Thread.currentThread().isInterrupted()) {
          throw new java.io.InterruptedIOException("Folder import cancelled");
        }
        File targetFile = context.getDatabasePath(parseData.destName);
        if (targetFile.exists()) {
          throw new Exception("Folder destination changed while import was pending");
        }
        File parent = targetFile.getParentFile();
        if (parent != null && !parent.exists() && !parent.mkdirs() && !parent.exists()) {
          throw new Exception("Unable to create folder database directory");
        }

        FileInputStream in = null;
        FileOutputStream out = null;
        try {
          in = new FileInputStream(parseData.stagedFile);
          out = new FileOutputStream(targetFile);
          BackupUtil.copy(in, out, MAX_FOLDER_DB_BYTES);
          out.flush();
          publishedFiles.add(targetFile);
          parseData.publishedFile = targetFile;
        } finally {
          if (in != null) {
            try { in.close(); } catch (Exception e) { Debug.log(e); }
          }
          if (out != null) {
            try { out.close(); } catch (Exception e) { Debug.log(e); }
          }
        }
      }

      SharedPreferences.Editor editor = context
          .getSharedPreferences(FolderUtils.PREFS, Context.MODE_PRIVATE).edit();
      for (ParseData parseData : mParsedList) {
        editor.putString(FolderUtils.KEY_NAME_PREFIX + parseData.destName, parseData.folderName);
      }
      if (!editor.commit()) {
        throw new Exception("Unable to publish restored folder names");
      }

      mCommitted = true;
      cleanupStagedFiles();
      return mParsedList.size();
    } catch (Exception e) {
      for (File publishedFile : publishedFiles) {
        if (publishedFile.exists() && !publishedFile.delete()) {
          Debug.log(new Exception("Unable to remove partial restored folder database"));
        }
      }
      SharedPreferences.Editor editor = context
          .getSharedPreferences(FolderUtils.PREFS, Context.MODE_PRIVATE).edit();
      for (ParseData parseData : mParsedList) {
        editor.remove(FolderUtils.KEY_NAME_PREFIX + parseData.destName);
        parseData.publishedFile = null;
      }
      editor.commit();
      cleanupStagedFiles();
      mCommitted = false;
      throw e;
    }
  }

  /**
   * Rolls back either an uncommitted preview or a commit whose caller later
   * failed before publishing the widget configuration.
   */
  public synchronized void rollback() {
    cleanupStagedFiles();
    if (mCommitted) {
      SharedPreferences.Editor editor = context
          .getSharedPreferences(FolderUtils.PREFS, Context.MODE_PRIVATE).edit();
      for (ParseData parseData : mParsedList) {
        editor.remove(FolderUtils.KEY_NAME_PREFIX + parseData.destName);
        File publishedFile = parseData.publishedFile;
        if (publishedFile == null) {
          publishedFile = context.getDatabasePath(parseData.destName);
        }
        if (publishedFile.exists() && !publishedFile.delete()) {
          Debug.log(new Exception("Unable to remove rolled-back folder database"));
        }
        parseData.publishedFile = null;
      }
      editor.commit();
      mCommitted = false;
    }
  }

  /**
   * Legacy eager-publish entry point retained for non-editor callers.
   */
  public int writeAll() throws Exception {
    stageAll();
    return commitAll();
  }

  private void cleanupStagedFiles() {
    for (ParseData parseData : mParsedList) {
      File stagedFile = parseData.stagedFile;
      if (stagedFile != null && stagedFile.exists() && !stagedFile.delete()) {
        Debug.log(new Exception("Unable to remove staged folder database"));
      }
      parseData.stagedFile = null;
    }
    mStaged = false;
  }

  /**
   * A holder class to keep the parse list.
   */
  @Thunk static final class ParseData {
    String destName;
    String folderName;
    ZipEntry srcEntry;
    File stagedFile;
    File publishedFile;
  }
}
