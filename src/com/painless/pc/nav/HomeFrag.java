package com.painless.pc.nav;

import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.OutputStream;

import android.annotation.TargetApi;
import android.app.Activity;
import android.app.AlertDialog;
import android.appwidget.AppWidgetHost;
import android.appwidget.AppWidgetManager;
import android.content.ClipData;
import android.content.ComponentName;
import android.content.Context;
import android.content.DialogInterface;
import android.content.Intent;
import android.content.SharedPreferences;
import android.graphics.Color;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.text.Html;
import android.util.Log;
import android.view.LayoutInflater;
import android.view.MenuItem;
import android.view.View;
import android.view.View.OnClickListener;
import android.view.ViewGroup;
import android.widget.ArrayAdapter;
import android.widget.LinearLayout;
import android.widget.ListView;
import android.widget.PopupMenu;
import android.widget.PopupMenu.OnMenuItemClickListener;
import android.widget.RemoteViews;
import android.widget.TextView;
import android.widget.Toast;

import com.painless.pc.FileProvider;
import com.painless.pc.PCWidgetActivity;
import com.painless.pc.R;
import com.painless.pc.picker.FilePicker;
import com.painless.pc.singleton.BackupUtil;
import com.painless.pc.singleton.Debug;
import com.painless.pc.singleton.Globals;
import com.painless.pc.singleton.SettingStorage;
import com.painless.pc.util.Thunk;
import com.painless.pc.util.WidgetSetting;

public class HomeFrag extends AbsListFrag {

  private static final int REQUEST_BACKUP = 10;
  private static final int REQUEST_RESTORE = 11;
  private static final String DEFAULT_BACKUP_NAME = "power-toggles-widget.zip";
  private static final long MAX_WIDGET_BACKUP_BYTES = 32L * 1024L * 1024L;

  @Thunk Context mContext;
  @Thunk LayoutInflater mLf;
  @Thunk SharedPreferences mExtraPrefs;
  private MyAdapter mAdapter;

  private ListItem mItemUnderAction;
  private int mPendingWidgetId = AppWidgetManager.INVALID_APPWIDGET_ID;

  @Override
  public void onViewCreated(View view, Bundle savedInstanceState) {
    super.onViewCreated(view, savedInstanceState);
    mContext = view.getContext();
    mLf = LayoutInflater.from(mContext);
    mExtraPrefs = mContext.getSharedPreferences(Globals.EXTRA_PREFS_NAME, Context.MODE_PRIVATE);
    setEmptyMsg(R.string.wp_no_widget, R.string.wp_add_help);

    mAdapter = new MyAdapter(mContext);
    setListAdapter(mAdapter);
    getListView().setDividerHeight(0);
    getListView().setSelector(android.R.color.transparent);
  }

  @Override
  public void onResume() {
    super.onResume();
    if (mAdapter != null) {
      mAdapter.clear();
      final AppWidgetManager awm = AppWidgetManager.getInstance(mContext);
      for (final int widgetId : awm.getAppWidgetIds(new ComponentName(mContext, PCWidgetActivity.class))) {
        Log.e("PC", "WidgetID " + widgetId);
        mAdapter.add(new ListItem(widgetId, this));
      }
    }
  }

  @Thunk void handleMenuClicked(View target, MenuItem item) {
    mItemUnderAction = (ListItem) target.getTag(R.id.btn_menu);
    if (mItemUnderAction == null) {
      return;
    }
    mPendingWidgetId = mItemUnderAction.widgetId;
    switch(item.getItemId()) {
      case R.id.mnu_share:
        shareWidget(mPendingWidgetId);
        break;
      case R.id.mnu_backup:
        startBackupPicker();
        break;
      case R.id.mnu_restore:
        startRestorePicker();
        break;
      case R.id.mnu_delete:
        new AlertDialog.Builder(mContext)
            .setTitle(R.string.wp_delete)
            .setMessage(Html.fromHtml(getString(R.string.wp_delete_msg)))
            .setNegativeButton(R.string.act_cancel, null)
            .setPositiveButton(R.string.act_delete, new DialogInterface.OnClickListener() {

              @Override
              public void onClick(DialogInterface dialog, int which) {
                dialog.dismiss();
                doDelete();
              }
            }).create().show();
        break;
    }
  }

  private void shareWidget(int widgetId) {
    FileOutputStream out = null;
    try {
      File shareFile = FileProvider.widgetShareFile(mContext);
      out = new FileOutputStream(shareFile, false);
      BackupUtil.createBackup(out, widgetId, mContext);
      out = null; // BackupUtil closes the supplied stream through ZipOutputStream.

      Uri shareUri = Uri.parse(FileProvider.WIDGET_SHARE_URI);
      Intent shareIntent = new Intent(Intent.ACTION_SEND)
          .setType("application/zip")
          .putExtra(Intent.EXTRA_STREAM, shareUri)
          .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
          .setClipData(ClipData.newRawUri("Power Toggles widget backup", shareUri));
      startActivity(Intent.createChooser(shareIntent, getString(R.string.wp_share)));
    } catch (Throwable e) {
      Debug.log(e);
      Toast.makeText(mContext, R.string.msg_unknown_error, Toast.LENGTH_LONG).show();
    } finally {
      if (out != null) {
        try { out.close(); } catch (Exception e) { Debug.log(e); }
      }
    }
  }

  private void startBackupPicker() {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
      Intent picker = new Intent(Intent.ACTION_CREATE_DOCUMENT)
          .addCategory(Intent.CATEGORY_OPENABLE)
          .setType("application/zip")
          .putExtra(Intent.EXTRA_TITLE, DEFAULT_BACKUP_NAME);
      startActivityForResult(picker, REQUEST_BACKUP);
    } else {
      Intent picker = new Intent(mContext, FilePicker.class)
          .putExtra("savemode", true)
          .putExtra("title", getString(R.string.wp_backup))
          .putExtra("filter", ".zip");
      startActivityForResult(picker, REQUEST_BACKUP);
    }
  }

  private void startRestorePicker() {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
      Intent picker = new Intent(Intent.ACTION_OPEN_DOCUMENT)
          .addCategory(Intent.CATEGORY_OPENABLE)
          .setType("application/zip");
      startActivityForResult(picker, REQUEST_RESTORE);
    } else {
      Intent picker = new Intent(mContext, FilePicker.class)
          .putExtra("savemode", false)
          .putExtra("title", getString(R.string.wp_restore))
          .putExtra("filter", ".zip");
      startActivityForResult(picker, REQUEST_RESTORE);
    }
  }

  @Thunk void doDelete() {
    if (mItemUnderAction == null) {
      return;
    }
    try {
      AppWidgetHost host = new AppWidgetHost(mContext.getApplicationContext(), 0);
      host.deleteAppWidgetId(mItemUnderAction.widgetId);
      mAdapter.remove(mItemUnderAction);
    } catch (Throwable e) {
      Debug.log(e);
      Toast.makeText(mContext, R.string.msg_unknown_error, Toast.LENGTH_LONG).show();
    }
  }

  @Override
  public void onActivityResult(int requestCode, int resultCode, Intent data) {
    if (resultCode != Activity.RESULT_OK || data == null
        || mPendingWidgetId == AppWidgetManager.INVALID_APPWIDGET_ID) {
      return;
    }

    if (requestCode == REQUEST_BACKUP) {
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
        backupToUri(data.getData(), mPendingWidgetId);
      } else {
        backupToLegacyPath(data.getStringExtra("file"), mPendingWidgetId);
      }
    } else if (requestCode == REQUEST_RESTORE) {
      boolean restored = Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT
          ? restoreFromUri(data.getData(), mPendingWidgetId)
          : restoreFromLegacyPath(data.getStringExtra("file"), mPendingWidgetId);
      if (!restored) {
        Toast.makeText(mContext, getResources().getStringArray(R.array.wc_import_msg)[1], Toast.LENGTH_LONG).show();
      }
      onResume();
    }
  }

  private void backupToUri(Uri destination, int widgetId) {
    String[] msgArray = getResources().getStringArray(R.array.wc_export_msg);
    if (destination == null) {
      Toast.makeText(mContext, msgArray[2], Toast.LENGTH_LONG).show();
      return;
    }
    OutputStream out = null;
    try {
      out = mContext.getContentResolver().openOutputStream(destination, "w");
      if (out == null) {
        throw new IllegalStateException("Unable to open backup destination");
      }
      BackupUtil.createBackup(out, widgetId, mContext);
      out = null; // BackupUtil closes via ZipOutputStream.
      Toast.makeText(mContext, String.format(msgArray[1], destination.toString()), Toast.LENGTH_LONG).show();
    } catch (Throwable e) {
      Debug.log(e);
      Toast.makeText(mContext, msgArray[2], Toast.LENGTH_LONG).show();
    } finally {
      if (out != null) {
        try { out.close(); } catch (Exception e) { Debug.log(e); }
      }
    }
  }

  private void backupToLegacyPath(String fileName, int widgetId) {
    String[] msgArray = getResources().getStringArray(R.array.wc_export_msg);
    if (fileName == null) {
      Toast.makeText(mContext, msgArray[2], Toast.LENGTH_LONG).show();
      return;
    }
    try {
      BackupUtil.createBackup(new FileOutputStream(fileName), widgetId, mContext);
      Toast.makeText(mContext, String.format(msgArray[1], fileName), Toast.LENGTH_LONG).show();
    } catch (Throwable e) {
      Debug.log(e);
      Toast.makeText(mContext, msgArray[2], Toast.LENGTH_LONG).show();
    }
  }

  private boolean restoreFromUri(Uri source, int widgetId) {
    if (source == null) {
      return false;
    }
    File temp = null;
    InputStream in = null;
    FileOutputStream out = null;
    try {
      temp = File.createTempFile("power_toggles_widget_restore_", ".zip", mContext.getCacheDir());
      in = mContext.getContentResolver().openInputStream(source);
      if (in == null) {
        return false;
      }
      out = new FileOutputStream(temp);
      BackupUtil.copy(in, out, MAX_WIDGET_BACKUP_BYTES);
      out.close();
      out = null;
      in.close();
      in = null;
      return BackupUtil.importBackup(temp.getAbsolutePath(), mContext, widgetId);
    } catch (Throwable e) {
      Debug.log(e);
      return false;
    } finally {
      if (out != null) {
        try { out.close(); } catch (Exception e) { Debug.log(e); }
      }
      if (in != null) {
        try { in.close(); } catch (Exception e) { Debug.log(e); }
      }
      if (temp != null && temp.exists() && !temp.delete()) {
        Debug.log(new Exception("Unable to delete temporary widget restore file"));
      }
    }
  }

  private boolean restoreFromLegacyPath(String fileName, int widgetId) {
    return fileName != null && BackupUtil.importBackup(fileName, mContext, widgetId);
  }

  @Override
  public void onListItemClick(ListView l, View v, int position, long id) {
    Globals.showWidgetConfig(mAdapter.getItem(position).widgetId, mContext, false);
  }

  private static class MyAdapter extends ArrayAdapter<ListItem> {

    public MyAdapter(Context context) {
      super(context, 0);
    }

    @Override
    public View getView(int position, View convertView, ViewGroup parent) {
      return getItem(position).getDisplayView();
    }
  }

  /**
   * Just a holder class so that adapter.remove does not remove the first item in the list.
   */
  private static class ListItem {
    @Thunk final int widgetId;
    private final WidgetSetting settings;
    private final HomeFrag parent;

    private View displayView;

    @Thunk ListItem(int widgetId, HomeFrag parent) {
      this.widgetId = widgetId;
      this.settings = SettingStorage.getSettingForWidget(parent.mContext, widgetId);
      this.parent = parent;
    }

    @Thunk View getDisplayView() {
      if (displayView == null) {
        displayView = parent.mLf.inflate(R.layout.widget_picker_card, null);
        RemoteViews widgetPreview = PCWidgetActivity.getRemoteView(parent.mContext, settings, false, widgetId);

        MyPopupMenu menu = new MyPopupMenu(parent, displayView.findViewById(R.id.btn_menu));
        menu.getMenuInflater().inflate(R.menu.widget_menu, menu.getMenu());

        displayView.findViewById(R.id.btn_menu).setTag(R.id.btn_menu, this);

        LinearLayout wrapper = (LinearLayout) displayView.findViewById(R.id.layout_wrapper);
        wrapper.addView(widgetPreview.apply(parent.mContext, wrapper));
        wrapper.setEnabled(false);

        for (int id : Globals.BUTTONS) {
          View btn = wrapper.findViewById(id);
          btn.setClickable(false);
          btn.setFocusable(false);
          btn.setBackgroundColor(Color.TRANSPARENT);
        }

        ((TextView) displayView.findViewById(R.id.txt_time)).setText(
            Globals.getTimeDiff(parent.mExtraPrefs.getLong("last_edit" + widgetId, 0), parent.mContext));
      }
      return displayView;
    }
  }

  private static class MyPopupMenu extends PopupMenu implements OnMenuItemClickListener, OnClickListener {

    private final View mAnchor;
    private final HomeFrag mParent;

    @TargetApi(Build.VERSION_CODES.KITKAT)
    public MyPopupMenu(HomeFrag parent, View anchor) {
      super(parent.mContext, anchor);
      mAnchor = anchor;
      mParent = parent;
      mAnchor.setOnClickListener(this);
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
        mAnchor.setOnTouchListener(getDragToOpenListener());
      }
      setOnMenuItemClickListener(this);
    }

    @Override
    public boolean onMenuItemClick(MenuItem item) {
      mParent.handleMenuClicked(mAnchor, item);
      return true;
    }

    @Override
    public void onClick(View v) {
      show();
    }
  }
}
