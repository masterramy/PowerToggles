package com.painless.pc.settings;

import java.util.Locale;

import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;
import android.view.Menu;
import android.view.View;
import android.view.View.OnClickListener;
import android.widget.ArrayAdapter;
import android.widget.EditText;
import android.widget.Spinner;

import com.painless.pc.R;
import com.painless.pc.singleton.Globals;
import com.painless.pc.util.UiUtils;

public class TaskerToggleSetup extends Activity implements OnClickListener {

  static final String EXTRA_STRING_BLURB = "com.twofortyfouram.locale.intent.extra.BLURB"; //$NON-NLS-1$
  static final String EXTRA_BUNDLE = "com.twofortyfouram.locale.intent.extra.BUNDLE"; //$NON-NLS-1$
  static final String EDIT_SETTING_ACTION = "com.twofortyfouram.locale.intent.action.EDIT_SETTING";
  private static final int MAX_INPUT_CHARS = 256;

  private Spinner mNewState;
  private Spinner mToggles;
  private ArrayAdapter<String> mAdapter;
  private EditText mCountText;

  @Override
  protected void onCreate(Bundle savedInstanceState) {
    super.onCreate(savedInstanceState);
    setResult(RESULT_CANCELED);

    // This activity must remain exported for Locale/Tasker interoperability,
    // but it is not a general-purpose external UI entry point.
    Intent launchIntent = getIntent();
    if (launchIntent == null || !EDIT_SETTING_ACTION.equals(launchIntent.getAction())) {
      finish();
      return;
    }

    setContentView(R.layout.tasker_toggle_setup);

    mNewState = (Spinner) findViewById(R.id.newState);
    mToggles = (Spinner) findViewById(R.id.toggles);
    mCountText = (EditText) findViewById(R.id.edit_count);

    mAdapter = new ArrayAdapter<String>(this, R.layout.list_item_normal);
    mAdapter.add(getString(R.string.ps_current_toggle));
    for (String tasks : Globals.getTaskerTasks(this)) {
      mAdapter.add(tasks);
    }
    mToggles.setAdapter(mAdapter);
    String oldState = boundedExtra(launchIntent, "state");
    mNewState.setSelection("true".equals(oldState) ? 1 : ("false".equals(oldState) ? 2 : 0));

    String oldToggle = boundedExtra(launchIntent, "varID");
    int toggleIndex = mAdapter.getPosition(oldToggle);
    mToggles.setSelection(toggleIndex > 0 ? toggleIndex : 0);

    String countText = boundedExtra(launchIntent, "count");
    mCountText.setText((countText != null) ? countText : "");
  }

  private static String boundedExtra(Intent intent, String key) {
    String value = intent.getStringExtra(key);
    if (value == null) {
      return null;
    }
    return value.length() <= MAX_INPUT_CHARS ? value : value.substring(0, MAX_INPUT_CHARS);
  }

  /**
   * Done clicked
   */
  @Override
  public void onClick(View v) {
    Bundle result = new Bundle();

    int toggle = mToggles.getSelectedItemPosition();
    result.putString("varID", (toggle == 0) ? "%toggle" : mAdapter.getItem(toggle));

    int state = mNewState.getSelectedItemPosition();
    result.putString("state", (state == 0) ? "%state" : ((state == 1) ? "true" : "false"));

    String countText = mCountText.getText().toString();
    if (countText.length() > MAX_INPUT_CHARS) {
      countText = countText.substring(0, MAX_INPUT_CHARS);
    }
    result.putString("count", countText.isEmpty() ? "%count" : countText);

    result.putString("net.dinglisch.android.tasker.extras.VARIABLE_REPLACE_KEYS", "varID state count");

    String info = String.format(Locale.ENGLISH, "Set %s to %s",
            (toggle == 0) ? "current toggle" : mAdapter.getItem(toggle),
                    new String[] {"new state", "on", "off"}[state]);

    setResult(
            RESULT_OK,
            new Intent()
            .putExtra(EXTRA_STRING_BLURB, info)
            .putExtra(EXTRA_BUNDLE, result)
            );
    finish();
  }

  @Override
  public boolean onCreateOptionsMenu(Menu menu) {
    return UiUtils.addDoneInMenu(menu, this);
  }
}
