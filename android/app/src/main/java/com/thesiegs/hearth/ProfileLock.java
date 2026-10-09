package com.thesiegs.hearth;

import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.SystemClock;
import android.util.Log;

/**
 * Locking the current grown-up profile with Google TV's own profile lock: its "Verify your identity" PIN screen
 * (launcherx ProfileLockWrapperActivity). The right PIN goes back to the profile; Back brings up Google TV's account
 * chooser, which stays until someone picks a profile or enters the PIN (LauncherAccessibilityService holds Hearth
 * back meanwhile). It needs Google TV's profile lock on for the profile (Settings > Accounts & Sign In > the account >
 * Profile lock); without one there's nothing to ask.
 *
 * Asked for from a remote button (ButtonMapper "lock"), holding the profile button, Settings > Profiles, and on
 * waking after the TV slept a while ("lock when the TV sleeps").
 */
final class ProfileLock {
    private static final String TAG = "HearthProfileLock";
    static final String ACTION = "android.apps.tv.launcherx.PROFILE_LOCK_REAUTH";
    private static final String PREFS = "profile_lock";
    private static final String ON_SLEEP_KEY = "lock_on_sleep_minutes";
    /** "Lock when the TV sleeps" is off. */
    static final int OFF = -1;

    /** When the screen last went off (elapsed time, which counts sleep), or 0. */
    private static long sScreenOffAt = 0;

    private ProfileLock() {
    }

    /** Brings up Google TV's PIN screen for the current profile. Not in a kids profile (it has its own lock). */
    static boolean lockNow(Context context) {
        if (ProfileUsers.isKids(context)) return false;
        try {
            context.startActivity(new Intent(ACTION)
                    .setPackage(LauncherAccessibilityService.GOOGLE_TV_PACKAGE)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
            Log.i(TAG, "Locked the profile");
            return true;
        } catch (Exception e) {
            Log.w(TAG, "Couldn't lock the profile", e);
            return false;
        }
    }

    private static SharedPreferences prefs(Context context) {
        return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    /** Minutes the TV must sleep before it locks on waking (0: any sleep), or {@link #OFF}. */
    static int lockOnSleepMinutes(Context context) {
        return prefs(context).getInt(ON_SLEEP_KEY, OFF);
    }

    static void setLockOnSleepMinutes(Context context, int minutes) {
        prefs(context).edit().putInt(ON_SLEEP_KEY, minutes).apply();
    }

    static void onScreenOff() {
        sScreenOffAt = SystemClock.elapsedRealtime();
    }

    /** The TV woke: locks if it slept at least the chosen time. */
    static void onScreenOn(Context context) {
        long offAt = sScreenOffAt;
        sScreenOffAt = 0;
        int minutes = lockOnSleepMinutes(context);
        if (offAt == 0 || minutes == OFF) return;
        long slept = SystemClock.elapsedRealtime() - offAt;
        if (slept >= minutes * 60_000L) {
            Log.i(TAG, "Woke after " + slept / 1000 + " s asleep: locking");
            lockNow(context);
        }
    }
}
