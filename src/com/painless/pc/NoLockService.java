package com.painless.pc;

import android.app.KeyguardManager;
import android.app.KeyguardManager.KeyguardLock;

import com.painless.pc.singleton.Debug;
import com.painless.pc.tracker.NoLockTracker;

public class NoLockService extends PriorityService {

  public NoLockService() {
    super(101, NoLockTracker.CHANGE_ACTION);
  }

	public static boolean NO_LOCK_ON = false;

	private KeyguardLock mLock;

	@Override
	public void onCreate() {
		super.onCreate();
		KeyguardManager manager = (KeyguardManager) getSystemService(KEYGUARD_SERVICE);
		mLock = manager.newKeyguardLock("power toggles");
		try {
			mLock.disableKeyguard();
		} catch (SecurityException e) {
			// Legacy KeyguardLock requires DISABLE_KEYGUARD. Fail closed if the
			// platform/OEM denies it rather than crashing the service process.
			Debug.log(e);
			mLock = null;
			stopSelf();
			return;
		}
		NO_LOCK_ON = true;

		maybeShowNotification("no_lock_hidden", false, R.drawable.icon_toggle_no_lock, R.string.no_lock_action, R.string.click_to_reenable, false);
		broadcastState();
	}

	@Override
	public void onDestroy() {
		if (mLock != null) {
			try {
				mLock.reenableKeyguard();
			} catch (SecurityException e) {
				Debug.log(e);
			}
		}
		clearNotification();
		NO_LOCK_ON = false;
		broadcastState();
		super.onDestroy();
	}
}
