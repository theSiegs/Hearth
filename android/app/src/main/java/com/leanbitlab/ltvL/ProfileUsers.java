package com.leanbitlab.ltvL;

import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.ApplicationInfo;
import android.content.pm.LauncherActivityInfo;
import android.content.pm.PackageManager;
import android.content.pm.ResolveInfo;
import android.os.Bundle;
import android.os.Process;
import android.os.UserHandle;
import android.os.UserManager;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeSet;

/**
 * Google TV runs every profile but the TV owner's as a hidden Android profile user (type com.android.tv.profile)
 * and keeps only the active one's user running: started on a switch in, stopped on a switch out. (That's how every
 * Google TV with profiles does it: Android 12 and later; Android 11 uses quiet mode instead.) So the active
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
    private static final String KEY_PREFIX = "user:";
    private static final String SCREEN_TIME_SERIAL = "screen_time_up_serial";

    /**
     * Restrictions Family Link puts on a supervised (kids) profile's user, whatever the parent allows: on the
     * test TV every kids profile has all of them and the owner none. (Unknown sources is left out: a parent
     * can allow it.)
     */
    private static final String[] SUPERVISION_RESTRICTIONS = {
            "no_config_credentials", "no_grant_admin", "no_add_managed_profile"};

    /** Never blocked by Google TV (Hearth is the home app), so no sign of screen time. */
    private static final Set<String> NEVER_BLOCKED = new HashSet<>(Arrays.asList(
            "com.android.vending"));

    private ProfileUsers() {
    }

    /**
     * The active profile's serial: the running profile user's, or the owner's when none runs (always, on a TV
     * without profiles). UNKNOWN mid-switch (two running).
     */
    static long activeSerial(Context context) {
        UserManager users = (UserManager) context.getSystemService(Context.USER_SERVICE);
        if (users == null) return UNKNOWN;
        try {
            List<UserHandle> profiles = users.getUserProfiles();
            UserHandle me = Process.myUserHandle();
            UserHandle running = null;
            for (UserHandle profile : profiles) {
                // Android 11's Google TV switches by quiet mode rather than by stopping users
                if (profile.equals(me) || !users.isUserRunning(profile) || users.isQuietModeEnabled(profile)) continue;
                if (running != null) return UNKNOWN;
                running = profile;
            }
            return users.getSerialNumberForUser(running != null ? running : me);
        } catch (SecurityException e) {
            return UNKNOWN;
        }
    }

    /**
     * A profile's lasting key ("user:11"): what Hearth stores per-profile things under, so renaming a profile in
     * Google TV doesn't orphan them. Null for UNKNOWN.
     */
    static String key(long serial) {
        return serial == UNKNOWN ? null : KEY_PREFIX + serial;
    }

    /**
     * The name to show for a key: the profile's learned name ("Profile 11" until it has one), or the key itself
     * for a name saved before keys.
     */
    static String displayName(Context context, String key) {
        if (key == null || !key.startsWith(KEY_PREFIX)) return key;
        try {
            long serial = Long.parseLong(key.substring(KEY_PREFIX.length()));
            String name = getName(context, serial);
            return name != null ? name : "Profile " + serial;
        } catch (NumberFormatException e) {
            return key;
        }
    }

    /**
     * Whether the active profile is a kids profile: its user is supervised by Family Link (Google's own record,
     * readable for the profiles of Hearth's user), not merely missing some app approvals. Only when that can't
     * be read does it fall back to Google TV suspending unapproved apps.
     */
    static boolean isKids(Context context) {
        Boolean supervised = isSupervised(context, settledSerial(context));
        return supervised != null ? supervised : anySuspended(context.getPackageManager());
    }

    /**
     * The apps a kids profile may open: approving an app installs it into that profile's user, so they're the
     * user's launchable apps. Null when they can't be read (or for the owner, who has every app).
     */
    static Set<String> approvedApps(Context context, long serial) {
        UserHandle user = otherUser(context, serial);
        Map<String, LauncherActivityInfo> apps = user != null ? ProfileApps.readApps(context, user) : null;
        return apps != null ? new TreeSet<>(apps.keySet()) : null;
    }

    /** The active profile's approved apps ({@link #approvedApps}); null for a grown-up or when unreadable. */
    static Set<String> activeApprovedApps(Context context) {
        long serial = settledSerial(context);
        return Boolean.TRUE.equals(isSupervised(context, serial)) ? approvedApps(context, serial) : null;
    }

    /**
     * Whether this kids profile's screen time is up (bedtime, daily limit): Google TV then blocks even the apps a
     * parent approved, in the kid's own profile user, where Google TV runs them. (In Hearth's user every app is
     * blocked throughout a kids profile, so that says nothing.) False for a grown-up profile; null when it can't
     * tell (no approved app to look at, or the apps can't be read), and only Google TV's own screens say.
     */
    static Boolean isScreenTimeUp(Context context, long serial) {
        Boolean supervised = isSupervised(context, serial);
        if (supervised == null) return null;
        if (!supervised) return false;
        UserHandle user = otherUser(context, serial);
        // Read fresh, not from ProfileApps' cache: this runs right after suspensions change
        Map<String, LauncherActivityInfo> apps = user != null ? ProfileApps.readApps(context, user) : null;
        if (apps == null) return null;
        int checked = 0;
        int blocked = 0;
        for (Map.Entry<String, LauncherActivityInfo> app : apps.entrySet()) {
            String pkg = app.getKey();
            if (NEVER_BLOCKED.contains(pkg) || pkg.equals(context.getPackageName())) continue;
            checked++;
            if ((app.getValue().getApplicationInfo().flags & ApplicationInfo.FLAG_SUSPENDED) != 0) blocked++;
        }
        // All of them: right after a switch some can still carry the last profile's state
        return checked == 0 ? null : blocked == checked;
    }

    /** The settled active serial (as Hearth's service last saw it), else a fresh read. */
    static long settledSerial(Context context) {
        String key = LauncherAccessibilityService.getActiveProfileKey(context);
        if (key != null && key.startsWith(KEY_PREFIX)) {
            try {
                return Long.parseLong(key.substring(KEY_PREFIX.length()));
            } catch (NumberFormatException ignored) {
            }
        }
        return activeSerial(context);
    }

    /** Whether this profile's user carries Family Link's supervision restrictions; null when that can't be read. */
    static Boolean isSupervised(Context context, long serial) {
        UserManager users = (UserManager) context.getSystemService(Context.USER_SERVICE);
        if (users == null || serial == UNKNOWN) return null;
        try {
            UserHandle user = users.getUserForSerialNumber(serial);
            if (user == null) return null;
            Bundle restrictions = users.getUserRestrictions(user);
            for (String restriction : SUPERVISION_RESTRICTIONS) {
                if (restrictions.getBoolean(restriction, false)) return true;
            }
            return false;
        } catch (RuntimeException e) {
            return null;
        }
    }

    /** Whether any launchable app is suspended: Google TV does that only in kids profiles. */
    static boolean anySuspended(PackageManager pm) {
        for (ResolveInfo info : launchables(pm)) {
            if ((info.activityInfo.applicationInfo.flags & ApplicationInfo.FLAG_SUSPENDED) != 0) return true;
        }
        return false;
    }

    /** The launchable activities in Hearth's own user: the TV ones, then the others (an app can be in both). */
    static List<ResolveInfo> launchables(PackageManager pm) {
        List<ResolveInfo> activities = new ArrayList<>();
        for (String category : new String[]{Intent.CATEGORY_LEANBACK_LAUNCHER, Intent.CATEGORY_LAUNCHER}) {
            activities.addAll(pm.queryIntentActivities(new Intent(Intent.ACTION_MAIN).addCategory(category), 0));
        }
        return activities;
    }

    /** The user with this serial when it's another profile's, not Hearth's own; null when it can't be found. */
    static UserHandle otherUser(Context context, long serial) {
        UserManager users = (UserManager) context.getSystemService(Context.USER_SERVICE);
        if (users == null || serial == UNKNOWN) return null;
        try {
            UserHandle user = users.getUserForSerialNumber(serial);
            return user == null || user.equals(Process.myUserHandle()) ? null : user;
        } catch (RuntimeException e) {
            return null;
        }
    }

    /** The serial whose screen time was up when last seen (UNKNOWN: none), so a service restart keeps the lock. */
    static long screenTimeUpSerial(Context context) {
        return prefs(context).getLong(SCREEN_TIME_SERIAL, UNKNOWN);
    }

    static void setScreenTimeUpSerial(Context context, long serial) {
        prefs(context).edit().putLong(SCREEN_TIME_SERIAL, serial).apply();
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

    /** The serial this name was learned for, or UNKNOWN. */
    static long serialOf(Context context, String name) {
        for (Map.Entry<String, ?> entry : prefs(context).getAll().entrySet()) {
            if (name != null && name.equals(entry.getValue()) && entry.getKey().startsWith(NAME_PREFIX)) {
                try {
                    return Long.parseLong(entry.getKey().substring(NAME_PREFIX.length()));
                } catch (NumberFormatException ignored) {
                }
            }
        }
        return UNKNOWN;
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
