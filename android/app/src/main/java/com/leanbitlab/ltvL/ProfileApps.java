package com.leanbitlab.ltvL;

import android.content.ComponentName;
import android.content.Context;
import android.content.pm.ApplicationInfo;
import android.content.pm.LauncherActivityInfo;
import android.content.pm.LauncherApps;
import android.os.SystemClock;
import android.os.UserHandle;
import android.os.UserManager;

import java.util.HashMap;
import java.util.Map;

/**
 * The switchboard: Google TV runs every profile but the owner's in its own profile user, with its own copies of the
 * apps (a kid's are the ones a parent approved), and blocks the owner's copies while such a profile is on. So while
 * one is active, Hearth shows that user's apps and opens them there (LauncherApps.startMainActivity, which reaches
 * the profiles of Hearth's user). Only an app's main screen can be opened in another user directly; deep links go
 * through that profile's Hearth agent (AgentHub).
 */
final class ProfileApps {
    /** Not for the active profile: the owner's own apps apply. */
    static final int OWNER = 0;
    /** In the active profile's user and usable. */
    static final int AVAILABLE = 1;
    /** In the active profile's user but blocked there (screen time). */
    static final int BLOCKED = 2;
    /** Not in the active profile's user (not approved for that kid). */
    static final int ABSENT = 3;

    private static final long CACHE_MS = 2_000;
    private static UserHandle sCachedUser;
    private static Map<String, LauncherActivityInfo> sCachedApps;
    private static long sCachedAt;

    private ProfileApps() {
    }

    /** The active profile's user when it isn't Hearth's own (the owner's) and is running; else null. */
    static UserHandle activeProfileUser(Context context) {
        UserHandle user = ProfileUsers.otherUser(context, ProfileUsers.settledSerial(context));
        if (user == null) return null;
        UserManager users = (UserManager) context.getSystemService(Context.USER_SERVICE);
        try {
            return users.isUserRunning(user) ? user : null;
        } catch (RuntimeException e) {
            return null;
        }
    }

    /** A user's launchable apps by package (its first activity for each), read now; null when they can't be read. */
    static Map<String, LauncherActivityInfo> readApps(Context context, UserHandle user) {
        LauncherApps launcherApps = (LauncherApps) context.getSystemService(Context.LAUNCHER_APPS_SERVICE);
        if (launcherApps == null) return null;
        try {
            Map<String, LauncherActivityInfo> apps = new HashMap<>();
            for (LauncherActivityInfo activity : launcherApps.getActivityList(null, user)) {
                apps.putIfAbsent(activity.getComponentName().getPackageName(), activity);
            }
            return apps;
        } catch (RuntimeException e) {
            return null;
        }
    }

    /** The active profile user's launchable apps by package (cached briefly: app lists ask once per app). */
    private static synchronized Map<String, LauncherActivityInfo> apps(Context context, UserHandle user) {
        long now = SystemClock.elapsedRealtime();
        if (user.equals(sCachedUser) && sCachedApps != null && now - sCachedAt < CACHE_MS) return sCachedApps;
        Map<String, LauncherActivityInfo> apps = readApps(context, user);
        if (apps == null) apps = new HashMap<>();
        sCachedUser = user;
        sCachedApps = apps;
        sCachedAt = now;
        return apps;
    }

    /** OWNER, AVAILABLE, BLOCKED or ABSENT for this package in the active profile. */
    static int state(Context context, String packageName) {
        UserHandle user = activeProfileUser(context);
        if (user == null) return OWNER;
        LauncherActivityInfo activity = apps(context, user).get(packageName);
        if (activity == null) return ABSENT;
        return (activity.getApplicationInfo().flags & ApplicationInfo.FLAG_SUSPENDED) != 0 ? BLOCKED : AVAILABLE;
    }

    /**
     * Opens the app in the active profile's user. Null when the owner's profile is on (open it as usual); false when
     * that profile doesn't have the app (never the owner's copy instead).
     */
    static Boolean launch(Context context, String packageName) {
        UserHandle user = activeProfileUser(context);
        if (user == null || packageName == null) return null;
        if (!apps(context, user).containsKey(packageName)) return false;
        // This profile's own pairing (its copies may be signed in to an account with everyone's profiles)
        ProfilePairingService.onAppLaunching(context, packageName);
        return startMain(context, user, packageName);
    }

    private static boolean startMain(Context context, UserHandle user, String packageName) {
        LauncherActivityInfo activity = apps(context, user).get(packageName);
        if (activity == null) return false;
        try {
            LauncherApps launcherApps = (LauncherApps) context.getSystemService(Context.LAUNCHER_APPS_SERVICE);
            ComponentName component = activity.getComponentName();
            launcherApps.startMainActivity(component, user, null, null);
            return true;
        } catch (RuntimeException e) {
            return false;
        }
    }

    /**
     * Opens what the intent points at in the active profile's user. Null when the owner's profile is on (start it
     * as usual). Deep links can't reach another user from here, so they go through that profile's Hearth agent
     * (AgentHub); without one the app opens at its main screen. False when that profile doesn't have the app.
     */
    static Boolean open(Context context, android.content.Intent intent) {
        if (intent == null) return null;
        UserHandle user = activeProfileUser(context);
        if (user == null) return null;
        String pkg = intent.getPackage() != null ? intent.getPackage()
                : intent.getComponent() != null ? intent.getComponent().getPackageName() : null;
        // Through that profile's agent the exact link opens; without one, the app's main screen
        long serial = ProfileUsers.settledSerial(context);
        if (pkg == null || !apps(context, user).containsKey(pkg)) return false;
        ProfilePairingService.onAppLaunching(context, pkg);
        return AgentHub.open(context, serial, user, intent.toUri(android.content.Intent.URI_INTENT_SCHEME))
                || startMain(context, user, pkg);
    }
}
