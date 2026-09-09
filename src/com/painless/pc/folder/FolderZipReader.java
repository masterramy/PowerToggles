package com.painless.pc.folder;

import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.zip.ZipEntry;
import java.util.zip.ZipFile;

import android.content.Context;

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

  public FolderZipReader(Context context, ZipFile zip) {
    this.zip = zip;
    this.context = context;
  }

  /**
   * Reads the folder entry and returns the destination db name.
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

  public int writeAll() throws Exception {
    ArrayList<File> writtenFiles = new ArrayList<File>();
    long totalBytes = 0;
    try {
      for (ParseData parseData : mParsedList) {
        File targetFile = context.getDatabasePath(parseData.destName);
        FileOutputStream out = null;
        InputStream in = null;
        try {
          out = new FileOutputStream(targetFile);
          in = zip.getInputStream(parseData.srcEntry);
          long remainingTotal = MAX_TOTAL_FOLDER_DB_BYTES - totalBytes;
          if (remainingTotal <= 0) {
            throw new Exception("Folder backup exceeds total database size limit");
          }
          long copied = BackupUtil.copy(in, out, Math.min(MAX_FOLDER_DB_BYTES, remainingTotal));
          out.flush();
          totalBytes += copied;
          writtenFiles.add(targetFile);
        } finally {
          if (in != null) {
            try { in.close(); } catch (Exception e) { Debug.log(e); }
          }
          if (out != null) {
            try { out.close(); } catch (Exception e) { Debug.log(e); }
          }
        }
      }

      // Publish names only after every embedded database has copied successfully.
      for (ParseData parseData : mParsedList) {
        FolderUtils.setName(parseData.folderName, parseData.destName, context);
      }
      return mParsedList.size();
    } catch (Exception e) {
      for (File writtenFile : writtenFiles) {
        if (writtenFile.exists() && !writtenFile.delete()) {
          Debug.log(new Exception("Unable to remove partial restored folder database"));
        }
      }
      throw e;
    }
  }

  /**
   * A holder class to keep the parse list.
   */
  @Thunk static final class ParseData {
    String destName;
    String folderName;
    ZipEntry srcEntry;
  }
}
