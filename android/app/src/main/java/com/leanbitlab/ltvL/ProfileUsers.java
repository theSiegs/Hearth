package com.leanbitlab.ltvL;

import android.content.Context;
import android.content.SharedPreferences;
import android.os.Process;
import android.os.UserHandle;
import android.os.UserManager;

import java.util.List;
import java.util.Map;

/**
 * Google TV runs every profile but the TV owner's as a hidden Android profile user (type com.android.tv.profile)
 * and keeps only the active one's user running: started on a switch in, stopped on a switch out. So the active
 * profile can be read at any time, keyed by the user's serial number (which never changes), and Android announces
 * switches with PROFILE_ACCESSIBLE / PROFILE_INACCESSIBLE. The users' own names are all "configured_user", so each
 * serial's profile name is still learned from Google TV's chooser, once.
 */
final class ProfileUsers {
    static final long UNKNOWN = -1;
    static final String ACTION_PROFILE_ACCESSIBLE = "android.intent.action.PROFILE_ACCESSIBLE";
    static final String ACTION_PROFILE_INACCESSIBLE = "android.intent.action.PROFILE_INACCESSIBLE";
    private static final String PREFS = "ltv_profile_users";
    private static final String NAME_PREFIX = "name|";

    private ProfileUsers() {
    }

    /**
     * The active profile's serial: the running profile user's, or the owner's when none runs. UNKNOWN on a TV
     * without profile users, or mid-switch (two running).
     */
    static long activeSerial(Context context) {
        UserManager users = (UserManager) context.getSystemService(Context.USER_SERVICE);
        if (users == null) return UNKNOWN;
        try {
            List<UserHandle> profiles = users.getUserProfiles();
            if (profiles.size() < 2) return UNKNOWN;
            UserHandle me = Process.myUserHandle();
            UserHandle running = null;
            for (UserHandle profile : profiles) {
                if (profile.equals(me) || !users.isUserRunning(profile)) continue;
                if (running != null) return UNKNOWN;
                running = profile;
            }
            return users.getSerialNumberForUser(running != null ? running : me);
        } catch (SecurityException e) {
            return UNKNOWN;
        }
    }

    /** The TV owner's serial (Hearth runs as the owner). */
    static long ownerSerial(Context context) {
        UserManager users = (UserManager) context.getSystemService(Context.USER_SERVICE);
        return users != null ? users.getSerialNumberForUser(Process.myUserHandle()) : UNKNOWN;
    }

    private static SharedPreferences prefs(Context context) {
        return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    /** The Google TV profile name learned for this serial, or null. */
    static String getName(Context context, long serial) {
        return serial == UNKNOWN ? null : prefs(context).getString(NAME_PREFIX + serial, null);
    }

    /** Whether this name was learned for a different serial. */
    static boolean isOtherProfile(Context context, long serial, String name) {
        if (name == null) return false;
        for (Map.Entry<String, ?> entry : prefs(context).getAll().entrySet()) {
            if (name.equals(entry.getValue()) && !entry.getKey().equals(NAME_PREFIX + serial)) return true;
        }
        return false;
    }

    /** Remembers which profile a serial is; a name moves off any other serial (profile names are unique). */
    static void setName(Context context, long serial, String name) {
        if (serial == UNKNOWN || name == null || name.isEmpty()) return;
        SharedPreferences prefs = prefs(context);
        SharedPreferences.Editor editor = prefs.edit();
        for (Map.Entry<String, ?> entry : prefs.getAll().entrySet()) {
            if (name.equals(entry.getValue())) editor.remove(entry.getKey());
        }
        editor.putString(NAME_PREFIX + serial, name).apply();
    }
}
