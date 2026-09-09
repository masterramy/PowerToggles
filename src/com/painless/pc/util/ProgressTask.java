package com.painless.pc.util;

import android.app.Activity;
import android.app.ProgressDialog;
import android.content.Context;
import android.os.AsyncTask;
import android.os.Build;

/**
 * AsyncTask helper that owns a progress dialog without publishing completion
 * into an Activity that is already finishing or destroyed.
 */
public abstract class ProgressTask<P, R> extends AsyncTask<P, Void, R> {

	private final ProgressDialog workingDialog;
	private final Activity ownerActivity;

	public ProgressTask(Context context, CharSequence msg) {
		ownerActivity = context instanceof Activity ? (Activity) context : null;
		workingDialog = ProgressDialog.show(context, null, msg, true, false);
	}

	public void onDone(R result) { }

	private boolean canPublishResult() {
		if (ownerActivity == null) {
			return true;
		}
		if (ownerActivity.isFinishing()) {
			return false;
		}
		return Build.VERSION.SDK_INT < Build.VERSION_CODES.JELLY_BEAN_MR1
				|| !ownerActivity.isDestroyed();
	}

	private void dismissDialogSafely() {
		try {
			if (workingDialog.isShowing()) {
				workingDialog.dismiss();
			}
		} catch (RuntimeException ignored) {
			// The Activity/window may have disappeared between the lifecycle check
			// and dismissal. Never turn teardown into a customer-visible crash.
		}
	}

	@Override
	protected final void onPostExecute(R result) {
		dismissDialogSafely();
		if (canPublishResult()) {
			onDone(result);
		}
	}

	@Override
	protected final void onCancelled(R result) {
		dismissDialogSafely();
	}

	@Override
	protected final void onCancelled() {
		dismissDialogSafely();
	}
}
