package com.painless.pc;

import android.annotation.TargetApi;
import android.app.Activity;
import android.app.AlertDialog;
import android.content.DialogInterface;
import android.content.DialogInterface.OnClickListener;
import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import android.provider.Settings;
import android.view.View;
import android.widget.CheckBox;

import com.painless.pc.singleton.Globals;

public class PermissionDialog extends Activity implements OnClickListener {

  private Intent mTargetIntent;
  private CheckBox mNeverCheckBox;

  @Override
  protected void onCreate(Bundle args) {
    super.onCreate(args);

    mTargetIntent = getIntent().getParcelableExtra("target");

    final View content = getLayoutInflater().inflate(R.layout.permission_prompt, null);
    mNeverCheckBox = (CheckBox) content.findViewById(R.id.chk_never);

    new AlertDialog.Builder(this)
      .setTitle(R.string.pp_title)
      .setView(content)
      .setPositiveButton(R.string.lbl_settings, this)
      .setNegativeButton(R.string.pp_ignore, this)
      .setOnCancelListener(new DialogInterface.OnCancelListener() {
        @Override
        public void onCancel(DialogInterface dialog) {
          finish();
        }
      })
      .show();
  }

  @TargetApi(23)
  @Override
  public void onClick(DialogInterface dialog, int which) {
    if (which == DialogInterface.BUTTON_POSITIVE) {
      startActivity(new Intent(Settings.ACTION_MANAGE_WRITE_SETTINGS)
        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        .setData(Uri.parse("package:" + getPackageName())));
    } else if (mTargetIntent != null) {
      startActivity(mTargetIntent);
    }

    if (mNeverCheckBox != null && mNeverCheckBox.isChecked()) {
      Globals.getAppPrefs(this).edit().putBoolean("prompt_permission", true).apply();
    }

    finish();
  }

}
