package com.painless.pc.tracker;

import android.app.Activity;
import android.content.Context;
import android.content.SharedPreferences;
import android.database.Cursor;
import android.os.Bundle;

import com.painless.pc.folder.FolderDb;
import com.painless.pc.folder.FolderUtils;
import com.painless.pc.singleton.Globals;

/** Debug-only exact-state fixture/verifier for Folder publication QA. */
public final class PublicationFolderProbeActivity extends Activity {

  public static final String NAME = "QA Folder 314159";
  private static final String PROBE_PREFS = "publication_folder_probe";

  @Override
  protected void onCreate(Bundle state) {
    super.onCreate(state);
    String probe = getIntent().getStringExtra("probe");
    if ("seed".equals(probe)) {
      seed();
    } else if ("verify_deleted".equals(probe)) {
      verifyDeleted();
    } else if ("verify_restored".equals(probe)) {
      verifyRestored();
    } else if ("cleanup".equals(probe)) {
      cleanup();
    }
    finish();
  }

  private void seed() {
    cleanupNamedFolders();
    String dbName = FolderUtils.newDbName(this);
    FolderDb db = new FolderDb(this, dbName);
    db.addTracker(new HomeCommand(43, Globals.getAppPrefs(this)), null, 0);
    db.close();
    FolderUtils.setName(NAME, dbName, this);
    getSharedPreferences(PROBE_PREFS, MODE_PRIVATE).edit()
        .putString("seed_db", dbName)
        .putBoolean("seeded", true)
        .commit();
  }

  private void verifyDeleted() {
    SharedPreferences probe = getSharedPreferences(PROBE_PREFS, MODE_PRIVATE);
    String original = probe.getString("seed_db", "");
    boolean originalExists = false;
    for (String dbName : databaseList()) {
      if (dbName.equals(original)) {
        originalExists = true;
      }
    }
    int namedCount = countNamedFolders(false);
    probe.edit()
        .putBoolean("deleted_original_absent", !originalExists)
        .putInt("deleted_named_count", namedCount)
        .commit();
  }

  private void verifyRestored() {
    SharedPreferences probe = getSharedPreferences(PROBE_PREFS, MODE_PRIVATE);
    int namedCount = countNamedFolders(true);
    probe.edit()
        .putInt("restored_named_count", namedCount)
        .commit();
  }

  private int countNamedFolders(boolean verifySemanticRow) {
    SharedPreferences names = getSharedPreferences(FolderUtils.PREFS, Context.MODE_PRIVATE);
    int count = 0;
    boolean semanticOk = false;
    String restoredDb = "";
    for (String dbName : databaseList()) {
      if (!dbName.matches(FolderUtils.DB_NAME_REGX)
          || !NAME.equals(names.getString(FolderUtils.KEY_NAME_PREFIX + dbName, ""))) {
        continue;
      }
      count++;
      restoredDb = dbName;
      if (verifySemanticRow) {
        FolderDb db = new FolderDb(this, dbName);
        Cursor cursor = db.getAllEntries();
        while (cursor.moveToNext()) {
          if (cursor.getInt(FolderDb.POS_POSITION) == 0
              && "43".equals(cursor.getString(FolderDb.POS_DEFINITION))) {
            semanticOk = true;
          }
        }
        cursor.close();
        db.close();
      }
    }
    if (verifySemanticRow) {
      getSharedPreferences(PROBE_PREFS, MODE_PRIVATE).edit()
          .putBoolean("restored_semantic_row", semanticOk)
          .putString("restored_db", restoredDb)
          .commit();
    }
    return count;
  }

  private void cleanup() {
    cleanupNamedFolders();
    getSharedPreferences(PROBE_PREFS, MODE_PRIVATE).edit().clear().commit();
  }

  private void cleanupNamedFolders() {
    SharedPreferences names = getSharedPreferences(FolderUtils.PREFS, Context.MODE_PRIVATE);
    SharedPreferences.Editor editor = names.edit();
    for (String dbName : databaseList()) {
      if (dbName.matches(FolderUtils.DB_NAME_REGX)
          && NAME.equals(names.getString(FolderUtils.KEY_NAME_PREFIX + dbName, ""))) {
        editor.remove(FolderUtils.KEY_NAME_PREFIX + dbName);
        deleteDatabase(dbName);
      }
    }
    editor.commit();
  }
}
