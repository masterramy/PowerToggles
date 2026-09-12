package com.painless.pc.cfg;

import static com.painless.pc.util.SettingsDecoder.KEY_TRACKER_ARRAY;

import java.io.File;
import java.io.FileOutputStream;
import java.io.OutputStream;
import java.util.zip.ZipEntry;
import java.util.zip.ZipOutputStream;

import org.json.JSONObject;

import android.appwidget.AppWidgetManager;
import android.appwidget.AppWidgetProviderInfo;
import android.content.ComponentName;
import android.content.Intent;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Rect;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.preference.PreferenceActivity;
import android.view.Menu;
import android.view.MenuItem;
import android.view.View;
import android.widget.Toast;

import com.painless.pc.FileProvider;
import com.painless.pc.PCWidgetActivity;
import com.painless.pc.R;
import com.painless.pc.cfg.ConfigButtonHelper.TrackerItem;
import com.painless.pc.cfg.section.BackgroundSection;
import com.painless.pc.cfg.section.ButtonColorsSection;
import com.painless.pc.cfg.section.ClickFeedbackSection;
import com.painless.pc.cfg.section.ConfigExtraData;
import com.painless.pc.cfg.section.ConfigSection;
import com.painless.pc.cfg.section.ConfigSection.ConfigCallback;
import com.painless.pc.cfg.section.DividersSection;
import com.painless.pc.cfg.section.StyleSection;
import com.painless.pc.folder.FolderZipReader;
import com.painless.pc.nav.SettingsFrag;
import com.painless.pc.picker.FilePicker;
import com.painless.pc.picker.ThemePicker;
import com.painless.pc.picker.TogglePicker;
import com.painless.pc.settings.LaunchActivity;
import com.painless.pc.singleton.BackupUtil;
import com.painless.pc.singleton.BackupUtil.BackupData;
import com.painless.pc.singleton.BitmapUtils;
import com.painless.pc.singleton.Debug;
import com.painless.pc.singleton.Globals;
import com.painless.pc.singleton.SettingStorage;
import com.painless.pc.singleton.WidgetDB;
import com.painless.pc.util.ImportExportActivity;
import com.painless.pc.util.SettingsDecoder;
import com.painless.pc.util.Thunk;
import com.painless.pc.util.WidgetSetting;

public class WidgetConfigActivity extends ImportExportActivity<BackupData> implements ConfigCallback {

  private static final String THEME_EXTENSION = ".pttheme";
  private static final String DEFAULT_THEME_NAME = "power-toggles-theme" + THEME_EXTENSION;

	public WidgetConfigActivity() {
		super(R.menu.config_menu, ".zip",
				R.string.wp_backup, R.array.wc_export_msg,
				R.string.wp_restore, R.array.wc_import_msg);
	}

	@Thunk final ConfigSection[] mSections = new ConfigSection[5];
	private ConfigButtonHelper mHelper;
	private TogglePicker mTogglePicker;

	private int mAppWidgetId = AppWidgetManager.INVALID_APPWIDGET_ID;

	private boolean mIsNotification;
	private WidgetSetting mRenderSettings;
	private ConfigExtraData mConfigExtraData;
  private FolderZipReader mPendingFolderImport;

	@Override
	protected void onCreate(Bundle savedInstanceState) {
		super.onCreate(savedInstanceState);
    addActionDoneButton();

		setContentView(R.layout.widget_config_activity);

		// Find the widget id from the intent. The exported activity only accepts
		// framework-owned widget IDs. Existing-widget editing is routed through
		// the non-exported EditWidgetConfigActivity subclass.
		final Intent intent = getIntent();
		final Bundle extras = intent == null ? null : intent.getExtras();
    if (extras == null) {
      finish();
      return;
    }

    int configuredWidgetId = extras.getInt(
        AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID);
    String startSettings;
    if (configuredWidgetId != AppWidgetManager.INVALID_APPWIDGET_ID) {
      if (!isOwnedAppWidgetId(configuredWidgetId)) {
        finish();
        return;
      }
      mAppWidgetId = configuredWidgetId;
      startSettings = SettingStorage.getDefaultSettings(mAppWidgetId);
    } else if (this instanceof EditWidgetConfigActivity) {
      mAppWidgetId = extras.getInt("edit_widget", AppWidgetManager.INVALID_APPWIDGET_ID);
      if (mAppWidgetId == AppWidgetManager.INVALID_APPWIDGET_ID) {
        finish();
        return;
      }
      startSettings = SettingStorage.getSettingString(this, mAppWidgetId);
    } else {
      finish();
      return;
    }

		mIsNotification = (mAppWidgetId == Globals.STATUS_BAR_WIDGET_ID) || (mAppWidgetId == Globals.STATUS_BAR_WIDGET_ID_2);
		if (mIsNotification) {
			getWindow().getDecorView().setBackgroundColor(0xAA000000);
			findViewById(R.id.cfg_trans_sec_1).setVisibility(View.INVISIBLE);
			findViewById(R.id.cfg_trans_sec_2).setVisibility(View.GONE);
		}

		setResult(RESULT_CANCELED, new Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, mAppWidgetId));

		// initiate settings
		Bitmap[] allIcons = WidgetDB.get(this).getAllIcons(mAppWidgetId);
		mRenderSettings = SettingStorage.buildWidgetSettings(startSettings, this, mAppWidgetId, allIcons);

		mConfigExtraData = new ConfigExtraData();
		mConfigExtraData.decoder = new SettingsDecoder(startSettings);
		if (mRenderSettings.backimage != null) {
		  try {
		    mConfigExtraData.backBitmap = BitmapFactory.decodeStream(getContentResolver().openInputStream(mRenderSettings.backimage));
		  } catch (Exception e) {
		    Debug.log(e);
		  }
		}

		mSections[0] = new ButtonColorsSection(this, this);
		mSections[1] = new StyleSection(this, this, mIsNotification);
		mSections[2] = new BackgroundSection(this, this);
    mSections[3] = new DividersSection(this, this);
    mSections[4] = new ClickFeedbackSection(this, this);
		mHelper = new ConfigButtonHelper(this, mIsNotification);

		initUI(mRenderSettings, mConfigExtraData, allIcons);
	}

  private boolean isOwnedAppWidgetId(int widgetId) {
    try {
      AppWidgetProviderInfo info = AppWidgetManager.getInstance(this).getAppWidgetInfo(widgetId);
      return info != null && new ComponentName(this, PCWidgetActivity.class).equals(info.provider);
    } catch (Throwable e) {
      Debug.log(e);
      return false;
    }
  }

	private void initUI(WidgetSetting setting, ConfigExtraData extraData, Bitmap[] icons) {
		mRenderSettings = setting;
		mConfigExtraData = extraData;
		for (ConfigSection s : mSections) {
			s.readSetting(mRenderSettings, mConfigExtraData);
		}
		mHelper.readSettings(mRenderSettings, icons);
		onConfigSectionUpdate();
	}

	@Override
	public void maybeShowAnimation() {
		super.maybeShowAnimation();
	}

	@Override
	public void onConfigSectionUpdate() {
		mHelper.refreshView();
	}

	public void onAddToggleClicked(View v) {
	  if (mHelper.getToggleCount() < 8) {
	    if (mTogglePicker == null) {
	      mTogglePicker = new TogglePicker(this, mHelper);
	    }
	    mTogglePicker.show();
	  } else {
      Toast.makeText(this, R.string.wc_add_toggle_max_err, Toast.LENGTH_LONG).show();
	  }
	}

	public void onThemesClicked(View v) {
	  requestResult(12, new Intent(this, ThemePicker.class), new ResultReceiver() {

      @Override
      public void onResult(int requestCode, Intent data) {
        String config = data.getStringExtra("config");
        Bitmap icon = data.getParcelableExtra("icon");
        SettingsDecoder decoder = new SettingsDecoder(config);

        for (ConfigSection section : mSections) {
          section.readTheme(decoder, icon);
        }

        onConfigSectionUpdate();
      }
    });
	}

	@Override
	protected void onNewIntent(Intent intent) {
	   if (Intent.ACTION_SEARCH.equals(intent.getAction()) && (mTogglePicker != null)) {
	     mTogglePicker.searchIntent(intent);
	   }
	}

	@Override
	public boolean onCreateOptionsMenu(Menu menu) {
	  getMenuInflater().inflate(R.menu.config_menu, menu);
	  return true;
	}

	@Override
	public boolean onOptionsItemSelected(MenuItem item) {
		switch (item.getItemId()) {
			case R.id.ui_prefs :
				startActivity(new Intent(this, LaunchActivity.class).putExtra(PreferenceActivity.EXTRA_SHOW_FRAGMENT, SettingsFrag.class.getName()));
				return true;
			case R.id.ui_guide :
				showGuide();
				return true;
			case R.id.cfg_ex_theme:
			  if (mConfigExtraData.backBitmap == null) {
			    Toast.makeText(this, R.string.wc_ex_theme_image, Toast.LENGTH_LONG).show();
			    return true;
			  }
          startThemeExport();
	        return true;
			default :
				return super.onOptionsItemSelected(item);
		}
	}

  private void startThemeExport() {
    final boolean modern = Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT;
    Intent intent;
    if (modern) {
      intent = new Intent(Intent.ACTION_CREATE_DOCUMENT)
          .addCategory(Intent.CATEGORY_OPENABLE)
          .setType("application/zip")
          .putExtra(Intent.EXTRA_TITLE, DEFAULT_THEME_NAME);
    } else {
      intent = new Intent(this, FilePicker.class)
          .putExtra("savemode", true)
          .putExtra("title", getText(R.string.wc_ex_theme))
          .putExtra("filter", THEME_EXTENSION);
    }

    requestResult(11, intent, new ResultReceiver() {
      @Override
      public void onResult(int requestCode, Intent data) {
        try {
          if (data == null) {
            throw new Exception("Theme export destination missing");
          }
          if (modern) {
            Uri destination = data.getData();
            if (destination == null) {
              throw new Exception("Theme export destination missing");
            }
            exportTheme(destination);
          } else {
            String path = data.getStringExtra("file");
            if (path == null) {
              throw new Exception("Theme export destination missing");
            }
            exportTheme(path);
          }
          Toast.makeText(WidgetConfigActivity.this, R.string.wc_ex_theme_success, Toast.LENGTH_SHORT).show();
        } catch (Exception e) {
          Debug.log(e);
          Toast.makeText(WidgetConfigActivity.this, R.string.wc_ex_theme_failed, Toast.LENGTH_SHORT).show();
        }
      }
    });
  }

	private void showGuide() {
		Rect margins = new Rect();
		getWindow().getDecorView().getWindowVisibleDisplayFrame(margins);

		View btnHolder = findViewById(R.id.prewiewHolder);
		View btn = btnHolder.findViewById(R.id.btn_2);
		if (btn.getVisibility() == View.GONE) {
		  btn = btnHolder.findViewById(R.id.btn_1);
		}
    if (btn.getVisibility() == View.GONE) {
      btn = btnHolder.findViewById(R.id.btn_8);
    }
		startActivity(new Intent(this, ConfigGuide.class)
		    .putExtra("b1", getPos(btn, margins))
		    .putExtra("b2", getPos(findViewById(R.id.btn_add), margins))
		    .putExtra("b3", getPos(findViewById(R.id.cfg_content_scroll), margins)));
		overridePendingTransition(android.R.anim.fade_in, 0);
	}
	private int[] getPos(View v, Rect margins) {
		int[] pos = new int[2];
		v.getLocationOnScreen(pos);
		return new int[] {pos[0] - margins.left, pos[1] - margins.top, v.getWidth(), v.getHeight()};
	}

	private String buildWidgetSettings(boolean saveIcons) {
		String trackerArray = mHelper.getDefinition(mAppWidgetId, saveIcons);
		JSONObject object = new JSONObject();

		try {
      object.put(KEY_TRACKER_ARRAY, trackerArray);
      for (ConfigSection sec : mSections) {
        sec.writeSettings(object);
      }
		} catch (Exception e) {
		  Debug.log(e);
		}

		return object.toString();
	}

	@Override
	public void doExport(OutputStream fileOut) throws Exception {
 		String config = buildWidgetSettings(false);

		ZipOutputStream out = new ZipOutputStream(fileOut);
		int i = 0;
		for (TrackerItem item : mHelper.mItemList) {
		  config += BackupUtil.addTrackerToZip(out, item.tracker, item.originalIcon, i, this);
			i++;
		}
		BackupUtil.addImage(out, mConfigExtraData.backBitmap, "back.png");

		out.putNextEntry(new ZipEntry("config.txt"));
		out.write(config.getBytes());
		out.closeEntry();
		out.close();
	}

  @Override
  public void onDoneClicked() {
    boolean folderCommitCompleted = false;
    try {
      if (mPendingFolderImport != null) {
        mPendingFolderImport.commitAll();
        folderCommitCompleted = true;
      }

      // Save background image
      if (!BitmapUtils.saveBitmap(mConfigExtraData.backBitmap,
              ((BackgroundSection) mSections[2]).getCode(),
              FileProvider.widgetBackFile(this, mAppWidgetId))) {
        deleteFile(FileProvider.backFileName(mAppWidgetId));
      }

      SettingStorage.clearCache();
      SettingStorage.addWidget(this, mAppWidgetId, buildWidgetSettings(true));
      setResult(RESULT_OK, new Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, mAppWidgetId));
      getSharedPreferences(Globals.EXTRA_PREFS_NAME, MODE_PRIVATE).edit().putLong("last_edit" + mAppWidgetId, System.currentTimeMillis()).commit();

      SettingStorage.cleanupUpUnusedWidgets(this);
      PCWidgetActivity.updateAllWidgets(this, true);
      SettingStorage.cleanupCachedPlugins(this);
      SettingStorage.updateConnectivityReceiver(this);

      // Ownership transfers to the saved widget only after every existing save
      // operation above has completed without throwing.
      mPendingFolderImport = null;
      finish();
      maybeShowAnimation();
    } catch (Exception e) {
      Debug.log(e);
      if (folderCommitCompleted && mPendingFolderImport != null) {
        mPendingFolderImport.rollback();
      }
      Toast.makeText(this, R.string.wc_folder_import_commit_failed, Toast.LENGTH_LONG).show();
    }
	}

	@Override
	public BackupData doImportInBackground(File importFile) throws Exception {
	  return BackupUtil.readSettingsStaged(importFile, this, mAppWidgetId);
	}

	@Override
	public void onPostImport(BackupData result) {
    rollbackPendingFolderImport();
    mPendingFolderImport = result.folderImport;
	  ConfigExtraData extra = new ConfigExtraData();
	  extra.backBitmap = result.backImage;
	  extra.decoder = result.decoder;
		initUI(result.settings, extra, result.icons);
	}

  private void rollbackPendingFolderImport() {
    if (mPendingFolderImport != null) {
      mPendingFolderImport.rollback();
      mPendingFolderImport = null;
    }
  }

  @Override
  protected void onDestroy() {
    rollbackPendingFolderImport();
    super.onDestroy();
  }

  private void exportTheme(Uri destination) throws Exception {
    OutputStream out = getContentResolver().openOutputStream(destination, "w");
    if (out == null) {
      throw new Exception("Unable to open theme export destination");
    }
    exportTheme(out);
  }

	@Thunk void exportTheme(String filePath) throws Exception {
    exportTheme(new FileOutputStream(filePath));
	}

  private void exportTheme(OutputStream fileOut) throws Exception {
    // Create theme settings
    JSONObject object = new JSONObject();
    for (ConfigSection sec : mSections) {
      sec.writeTheme(object);
    }

    ZipOutputStream out = new ZipOutputStream(fileOut);
    try {
      BackupUtil.addImage(out, mConfigExtraData.backBitmap, "back.png");
      out.putNextEntry(new ZipEntry("theme.txt"));
      out.write(object.toString().getBytes("UTF-8"));
      out.closeEntry();
    } finally {
      out.close();
    }
	}
}
