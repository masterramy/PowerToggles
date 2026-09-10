package com.painless.pc.singleton;

import static com.painless.pc.util.SettingsDecoder.KEY_DENSITY;
import static com.painless.pc.util.SettingsDecoder.KEY_PADDING;
import static com.painless.pc.util.SettingsDecoder.KEY_STRETCH;
import static com.painless.pc.util.SettingsDecoder.KEY_TRACKER_ARRAY;

import java.io.BufferedReader;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.io.StringReader;
import java.util.zip.ZipEntry;
import java.util.zip.ZipFile;
import java.util.zip.ZipOutputStream;

import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.graphics.Bitmap;
import android.net.Uri;

import com.painless.pc.FileProvider;
import com.painless.pc.PCWidgetActivity;
import com.painless.pc.TrackerManager;
import com.painless.pc.cfg.section.BackgroundSection;
import com.painless.pc.folder.FolderUtils;
import com.painless.pc.folder.FolderZipReader;
import com.painless.pc.tracker.AbstractTracker;
import com.painless.pc.tracker.PluginTracker;
import com.painless.pc.tracker.SimpleShortcut;
import com.painless.pc.util.BitmapImportUtils;
import com.painless.pc.util.SettingsDecoder;
import com.painless.pc.util.WidgetSetting;

/** Utility class to handle backup and restores. */
public class BackupUtil {
  private static final long MAX_CONFIG_BYTES = 256L * 1024L;
  private static final long MAX_IMAGE_BYTES = 8L * 1024L * 1024L;
  private static final int MAX_SCALED_BACKGROUND_DIMENSION = 4096;
  private static final long MAX_SCALED_BACKGROUND_PIXELS = 16L * 1024L * 1024L;

  public static void createBackup(OutputStream os, int widgetId, Context context) throws Exception {
    ZipOutputStream outStream = null;
    try {
      outStream = new ZipOutputStream(os);
      String widgetConfig = SettingStorage.getSettingString(context, widgetId);
      Bitmap[] allIcons = WidgetDB.get(context).getAllIcons(widgetId);
      WidgetSetting setting = SettingStorage.buildWidgetSettings(widgetConfig, context, widgetId, allIcons);
      for (int i = 0; i < 8 ; i++) widgetConfig += addTrackerToZip(outStream, setting.trackers[i], allIcons[i], i, context);
      if (setting.backimage != null) {
        outStream.putNextEntry(new ZipEntry("back.png"));
        copy(context.getContentResolver().openInputStream(setting.backimage), outStream);
        outStream.closeEntry();
      }
      outStream.putNextEntry(new ZipEntry("config.txt"));
      outStream.write(widgetConfig.getBytes());
      outStream.closeEntry();
    } finally { if (outStream != null) outStream.close(); }
  }

  public static String addTrackerToZip(ZipOutputStream zip, AbstractTracker tracker, Bitmap icon, int pos, Context context) throws Exception {
    addImage(zip, icon, pos + ".png");
    if (tracker == null) return "";
    if (tracker instanceof SimpleShortcut) {
      SimpleShortcut shrt = (SimpleShortcut) tracker;
      Intent intent = shrt.getIntent();
      if (FolderUtils.ACTION.equals(intent.getAction())) addDbToZip(intent.getData().getQuery(), zip, context, pos);
      return "\n" + intent.toUri(Intent.URI_INTENT_SCHEME) + "\n" + shrt.getLabel(null);
    } else if (tracker instanceof PluginTracker) {
      PluginTracker plugin = (PluginTracker) tracker;
      return "\n" + plugin.getIntent().toUri(Intent.URI_INTENT_SCHEME) + "\n" + plugin.getLabel(null);
    }
    return "";
  }

  public static void addDbToZip(String dbName, ZipOutputStream zip, Context context, int pos) throws Exception {
    FileInputStream in = new FileInputStream(context.getDatabasePath(dbName));
    try {
      zip.putNextEntry(new ZipEntry(FolderUtils.getDbName(pos)));
      copy(in, zip);
      zip.closeEntry();
    } finally { in.close(); }
  }

  public static void addImage(ZipOutputStream zip, Bitmap icon, String name) throws Exception {
    if (icon != null) {
      zip.putNextEntry(new ZipEntry(name));
      BitmapUtils.compressImage(icon).writeTo(zip);
      zip.closeEntry();
    }
  }

  public static BackupData readSettings(File importFile, Context context, int widgetId) throws Exception {
    return readSettingsInternal(importFile, context, widgetId, true);
  }

  /**
   * Parses a widget backup for editor preview while staging embedded folder
   * databases privately. The caller must commit or roll back data.folderImport.
   */
  public static BackupData readSettingsStaged(File importFile, Context context, int widgetId) throws Exception {
    return readSettingsInternal(importFile, context, widgetId, false);
  }

  private static BackupData readSettingsInternal(File importFile, Context context, int widgetId,
      boolean commitFolders) throws Exception {
    ZipFile zip = null;
    FolderZipReader folderReader = null;
    try {
      zip = new ZipFile(importFile);
      byte[] configBytes = readZipEntry(zip, zip.getEntry("config.txt"), MAX_CONFIG_BYTES, true);
      BufferedReader reader = new BufferedReader(new StringReader(new String(configBytes)));
      String settingsLine = reader.readLine();
      if (settingsLine == null) throw new Exception("Missing widget settings");
      SettingsDecoder decoder = new SettingsDecoder(settingsLine);
      AbstractTracker[] trackers = new AbstractTracker[8];
      Bitmap[] allIcons = new Bitmap[8];
      String[] ids = decoder.getTrackerDef().split(",");
      SharedPreferences pref = Globals.getAppPrefs(context);
      if (ids.length == 0) throw new Exception("No trackers to import");
      folderReader = new FolderZipReader(context, zip);
      String newTrackerList = "";
      for (int i = 0; i<8 && i<ids.length; i++) {
        if (Thread.currentThread().isInterrupted()) throw new java.io.InterruptedIOException("Widget import cancelled");
        String id = ids[i];
        if (id.startsWith("ss_")) {
          String intentLine = reader.readLine(), folderName = reader.readLine();
          if (intentLine == null || folderName == null) throw new Exception("Incomplete shortcut backup data");
          Intent intent = Intent.parseUri(intentLine, 0);
          SimpleShortcut shrt = new SimpleShortcut(intent, folderName);
          shrt.setId(SimpleShortcut.getId(widgetId, i)); trackers[i] = shrt;
          if (FolderUtils.ACTION.equals(intent.getAction())) intent.setData(Uri.parse("folder/?" + folderReader.readEntry(folderName, i)));
        } else if (id.startsWith("pl_")) {
          String intentLine = reader.readLine(), label = reader.readLine();
          if (intentLine == null || label == null) throw new Exception("Incomplete plugin backup data");
          trackers[i] = new PluginTracker(id.substring(3), Intent.parseUri(intentLine, Intent.URI_INTENT_SCHEME), label);
        } else trackers[i] = TrackerManager.getTracker(Integer.parseInt(id), pref);
        if (trackers[i] == null) throw new Exception("Unsupported tracker in backup");
        newTrackerList += trackers[i].getId() + ",";
        ZipEntry iconEntry = zip.getEntry(i + ".png");
        if (iconEntry != null) {
          Bitmap importedIcon = BitmapImportUtils.decode(readZipEntry(zip, iconEntry, MAX_IMAGE_BYTES, true));
          if (importedIcon == null) throw new Exception("Invalid or oversized widget icon");
          allIcons[i] = BitmapUtils.resizeToIconSize(importedIcon, context, false);
        }
      }
      if (newTrackerList.length() == 0) throw new Exception("No valid trackers in backup");
      decoder.settings.put(KEY_TRACKER_ARRAY, newTrackerList.substring(0, newTrackerList.length() - 1));
      BackupData data = new BackupData();
      data.settings = new WidgetSetting(context, trackers, decoder, widgetId, allIcons); data.settings.backimage = null; data.decoder = decoder;
      int deviceDensity = context.getResources().getDisplayMetrics().densityDpi;
      int settingDensity = decoder.getValue(KEY_DENSITY, deviceDensity); if (settingDensity <= 0) settingDensity = deviceDensity;
      normalizeRect(decoder, KEY_PADDING, deviceDensity, settingDensity); normalizeRect(decoder, KEY_STRETCH, deviceDensity, settingDensity);
      ZipEntry backImage = zip.getEntry("back.png");
      if (backImage != null) {
        Bitmap back = BitmapImportUtils.decode(readZipEntry(zip, backImage, MAX_IMAGE_BYTES, true));
        if (back == null) throw new Exception("Invalid or oversized widget background");
        long targetWidth = Math.max(1L, ((long) back.getWidth() * deviceDensity) / settingDensity);
        long targetHeight = Math.max(1L, ((long) back.getHeight() * deviceDensity) / settingDensity);
        if (targetWidth > MAX_SCALED_BACKGROUND_DIMENSION || targetHeight > MAX_SCALED_BACKGROUND_DIMENSION || targetWidth * targetHeight > MAX_SCALED_BACKGROUND_PIXELS) {
          back.recycle(); throw new Exception("Scaled widget background is too large");
        }
        data.backImage = Bitmap.createScaledBitmap(back, (int) targetWidth, (int) targetHeight, true); if (back != data.backImage) back.recycle();
      }
      if (Thread.currentThread().isInterrupted()) throw new java.io.InterruptedIOException("Widget import cancelled");

      folderReader.stageAll();
      if (Thread.currentThread().isInterrupted()) {
        folderReader.rollback();
        throw new java.io.InterruptedIOException("Widget import cancelled");
      }
      if (commitFolders) {
        folderReader.commitAll();
      } else {
        data.folderImport = folderReader;
        folderReader = null;
      }
      data.icons = allIcons;
      return data;
    } finally {
      if (folderReader != null) {
        folderReader.rollback();
      }
      if (zip != null) zip.close();
    }
  }

  private static byte[] readZipEntry(ZipFile zip, ZipEntry entry, long maxBytes, boolean required) throws Exception {
    if (entry == null) { if (required) throw new Exception("Required backup entry missing"); return null; }
    InputStream in = null; ByteArrayOutputStream out = new ByteArrayOutputStream();
    try { in = zip.getInputStream(entry); copy(in, out, maxBytes); return out.toByteArray(); }
    finally { if (in != null) try { in.close(); } catch (Exception e) { Debug.log(e); } try { out.close(); } catch (Exception e) { Debug.log(e); } }
  }

  public static boolean importBackup(String importFile, Context context, int widgetId) {
    try {
      BackupData data = readSettings(new File(importFile), context, widgetId);
      if (Thread.currentThread().isInterrupted()) return false;
      String backFileName = FileProvider.backFileName(widgetId);
      if (!BitmapUtils.saveBitmap(data.backImage, data.decoder.getRect(KEY_STRETCH), FileProvider.widgetBackFile(context, widgetId))) context.deleteFile(backFileName);
      WidgetDB db = WidgetDB.get(context); db.deleteToggles(widgetId);
      for (int i = 0; i < 8; i++) {
        AbstractTracker tracker = data.settings.trackers[i]; if (tracker == null) continue;
        if (tracker.getId().startsWith("ss_")) { SimpleShortcut shrt = (SimpleShortcut) tracker; shrt.setId(SimpleShortcut.getId(widgetId, i)); db.saveShrt(shrt, data.icons[i]); }
        else if (data.icons[i] != null) { db.saveIcon(SimpleShortcut.getId(widgetId, i), data.icons[i]); if (tracker.getId().startsWith("pl_")) PluginDB.get(context).save((PluginTracker) tracker); }
      }
      WidgetDB.closeAll(); SettingStorage.clearCache(); SettingStorage.addWidget(context, widgetId, data.decoder.settings.toString());
      context.getSharedPreferences(Globals.EXTRA_PREFS_NAME, Context.MODE_PRIVATE).edit().putLong("last_edit" + widgetId, System.currentTimeMillis()).commit();
      PCWidgetActivity.fullUpdateSingleWidgets(context, widgetId); SettingStorage.cleanupCachedPlugins(context); return true;
    } catch (Exception e) { Debug.log(e); return false; }
  }

  public static void copy(InputStream in, OutputStream out) throws Exception { copy(in, out, Long.MAX_VALUE); }
  public static long copy(InputStream in, OutputStream out, long maxBytes) throws Exception {
    if (in == null || out == null) throw new Exception("Unable to copy null stream");
    byte[] bucket = new byte[8 * 1024]; int bytesRead; long total = 0;
    while (true) {
      if (Thread.currentThread().isInterrupted()) throw new java.io.InterruptedIOException("Stream copy cancelled");
      bytesRead = in.read(bucket); if (bytesRead == -1) break;
      total += bytesRead; if (total > maxBytes) throw new java.io.IOException("Input exceeds maximum supported size");
      out.write(bucket, 0, bytesRead);
    }
    return total;
  }

  public static int[] normalizeRect(SettingsDecoder decoder, String key, int deviceDensity, int settingDensity) {
    int[] rect = decoder.getRect(key); for (int i = 0; i < 4; i++) rect[i] = rect[i] * deviceDensity / settingDensity;
    try { decoder.settings.put(key, BackgroundSection.getStr(rect)); } catch (Exception e) { }
    return rect;
  }
  public static final class BackupData {
    public WidgetSetting settings;
    public Bitmap[] icons;
    public SettingsDecoder decoder;
    public Bitmap backImage;
    public FolderZipReader folderImport;
  }
}
