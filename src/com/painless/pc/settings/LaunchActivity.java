package com.painless.pc.settings;

import java.util.ArrayList;
import java.util.List;

import android.content.Context;
import android.os.Bundle;
import android.preference.PreferenceActivity;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.ArrayAdapter;
import android.widget.ListAdapter;
import android.widget.TextView;

import com.painless.pc.R;
import com.painless.pc.nav.CFolderFrag;
import com.painless.pc.nav.FolderFrag;
import com.painless.pc.nav.HomeFrag;
import com.painless.pc.nav.InfoFrag;
import com.painless.pc.nav.NotifyFrag;
import com.painless.pc.nav.SettingsFrag;
import com.painless.pc.nav.TCacheFrag;
import com.painless.pc.nav.TogglePrefFrag;
import com.painless.pc.util.ReflectionUtil;

public class LaunchActivity extends PreferenceActivity {

  private List<Header> mHeaders;

  @Override
  protected void onCreate(Bundle savedInstanceState) {
    if ((getIntent().getComponent() != null)
            && getIntent().getComponent().getClassName().endsWith("NotificationSettings")) {
      getIntent().putExtra(PreferenceActivity.EXTRA_SHOW_FRAGMENT, NotifyFrag.class.getName());
    }
    super.onCreate(savedInstanceState);
    setTitle(getIntent().getIntExtra(EXTRA_SHOW_FRAGMENT_TITLE, R.string.app_name));
  }

  @Override
  public void onBuildHeaders(List<Header> target) {
    loadHeadersFromResource(R.xml.main_headers, target);
    mHeaders = target;
  }

  @Override
  protected boolean isValidFragment(String fragmentName) {
    // LaunchActivity is exported for the launcher and notification-settings alias.
    // PreferenceActivity also accepts EXTRA_SHOW_FRAGMENT from its launching Intent,
    // so validate against the complete in-app navigation set instead of trusting an
    // arbitrary Fragment class name supplied by another app.
    return HomeFrag.class.getName().equals(fragmentName)
        || NotifyFrag.class.getName().equals(fragmentName)
        || FolderFrag.class.getName().equals(fragmentName)
        || SettingsFrag.class.getName().equals(fragmentName)
        || InfoFrag.class.getName().equals(fragmentName)
        || TogglePrefFrag.class.getName().equals(fragmentName)
        || TCacheFrag.class.getName().equals(fragmentName)
        || CFolderFrag.class.getName().equals(fragmentName);
  }

  @Override
  public void setListAdapter(ListAdapter adapter) {
    if (adapter == null) {
      super.setListAdapter(adapter);
    } else {
      super.setListAdapter(new HeaderAdapter(this, getMyHeaders()));
    }
  }

  @Override
  public Header onGetInitialHeader() {
    return getMyHeaders().get(1);
  }

  @SuppressWarnings("unchecked")
  private List<Header> getMyHeaders() {
    if (mHeaders == null) {
      mHeaders = (List<Header>) new ReflectionUtil(this, PreferenceActivity.class).invokeGetter("getHeaders");
    }
    if (mHeaders == null) {
      onBuildHeaders(new ArrayList<Header>());
    }
    return mHeaders;
  }

  private static class HeaderAdapter extends ArrayAdapter<Header> {

    private final LayoutInflater mInflater;

    public HeaderAdapter(Context context, List<Header> headers) {
      super(context, R.layout.list_item_header, headers);
      mInflater = LayoutInflater.from(context);
    }
 
    @Override
    public View getView(int position, View convertView, ViewGroup parent) {
      Header item = getItem(position);
      TextView view = (TextView) ((convertView == null) ? mInflater.inflate(
          (item.fragment == null && item.intent == null)
          ? R.layout.list_item_header : R.layout.list_item_normal, parent, false) : convertView);
      view.setCompoundDrawablesWithIntrinsicBounds(item.iconRes, 0, 0, 0);
      view.setText(item.titleRes);
      return view;
    }

    @Override
    public boolean areAllItemsEnabled() {
      return false;
    }

    @Override
    public boolean isEnabled(int position) {
      Header item = getItem(position);
      return item.fragment != null || item.intent != null;
    }

    @Override
    public int getViewTypeCount() {
      return 2;
    }

    @Override
    public int getItemViewType(int position) {
      return isEnabled(position) ? 1 : 0;
    }
  }
}

