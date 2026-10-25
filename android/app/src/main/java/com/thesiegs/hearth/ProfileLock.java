package com.thesiegs.hearth;

import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.util.Log;

/**
 * Locking the current adult profile with Google TV's own profile lock: its "Verify your identity" PIN screen
 * (launcherx ProfileLockWrapperActivity). The right PIN goes back to the profile; Back brings up Google TV's account
 * chooser, which stays until someone picks a profile or enters the PIN (LauncherAccessibilityService holds Hearth
 * back meanwhile). It needs Google TV's profile lock on for the profile (Settings > Accounts & Sign In > the account >
 * Profile lock); without one there's nothing to ask.
 *
 * Asked for from a remote button (ButtonMapper "lock"), holding the profile button and Settings > Profiles.
 *
 * Waking after the TV slept a while (Settings > Profiles > the wake choice) opens Google TV's profile chooser
 * instead: whoever turned the TV on picks who is watching, and a profile with a PIN asks for it before it opens.
 */
final class ProfileLock {
    private static final String TAG = "HearthProfileLock";
    static final String ACTION = "android.apps.tv.launcherx.PROFILE_LOCK_REAUTH";
    private static final String PREFS = "profile_lock";
    private static final String ON_SLEEP_KEY = "lock_on_sleep_minutes";
    /** When the screen last went off (wall clock), kept so a Hearth restart while the TV sleeps (an update) still knows. */
    private static final String OFF_AT_KEY = "screen_off_at";
    /** "Lock when the TV sleeps" is off. */
    static final int OFF = -1;

    private ProfileLock() {
    }

    /** Brings up Google TV's PIN screen for the current profile. Not in a kids profile (it has its own lock). */
    static boolean lockNow(Context context) {
        if (ProfileUsers.isKids(context)) return false;
        // The chooser said this profile has no PIN: Google TV's lock would have nothing to ask
        String name = ProfileUsers.profileName(context, ProfileUsers.settledSerial(context));
        if (name != null && Boolean.FALSE.equals(ProfileUsers.isLocked(context, name))) return false;
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

    static void onScreenOff(Context context) {
        prefs(context).edit().putLong(OFF_AT_KEY, System.currentTimeMillis()).apply();
    }

    /**
     * Hearth started (an update, a restart) with the screen off and no time saved from before: the TV has slept at
     * least since now, so waking still counts it.
     */
    static void onStartedAsleep(Context context) {
        if (prefs(context).getLong(OFF_AT_KEY, 0) == 0) onScreenOff(context);
    }

    /** Whether a wake at {@code now} after the screen went off at {@code offAt} (wall clock; 0: unknown) is due, for {@code minutes}. */
    static boolean due(int minutes, long offAt, long now) {
        if (offAt == 0 || minutes == OFF) return false;
        return now - offAt >= minutes * 60_000L;
    }

    /** The TV woke: opens the profile chooser if it slept at least the chosen time. */
    static void onScreenOn(Context context) {
        SharedPreferences prefs = prefs(context);
        long offAt = prefs.getLong(OFF_AT_KEY, 0);
        prefs.edit().remove(OFF_AT_KEY).apply();
        long now = System.currentTimeMillis();
        if (!due(lockOnSleepMinutes(context), offAt, now)) return;
        Log.i(TAG, "Woke after " + (now - offAt) / 1000 + " s asleep: opening the profile chooser");
        showChooser(context);
    }

    /** Google TV's profile chooser. Not in a kids profile, which has its own lock and bedtime. */
    static boolean showChooser(Context context) {
        if (ProfileUsers.isKids(context)) return false;
        try {
            context.startActivity(LauncherAccessibilityService.profileChooserIntent()
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
            return true;
        } catch (Exception e) {
            Log.w(TAG, "Couldn't open the profile chooser: " + e.getClass().getSimpleName());
            return false;
        }
    }
}
