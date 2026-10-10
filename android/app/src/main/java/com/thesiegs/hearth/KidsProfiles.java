package com.thesiegs.hearth;

import android.content.Context;
import android.content.SharedPreferences;
import android.content.pm.LauncherApps;
import android.content.pm.PackageManager;
import android.os.Process;
import android.os.UserHandle;
import android.os.UserManager;
import android.util.Log;

import java.net.ConnectException;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.ScheduledFuture;
import java.util.concurrent.TimeUnit;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Hearth on the TV's kids' profiles: which they are, whether Hearth (and HearthTube, when the owner has it) is on
 * each, and putting them there or taking them off. The commands are {@link ProfileAppAccess}'s, run over Hearth's
 * own adb ({@link SelfAdb}).
 *
 * <p>Google TV runs each kids' profile as an Android user of its own that Family Link supervises
 * ({@link ProfileUsers#isSupervised}). A grown-up's profile is another Google account in the owner's user, which has
 * Hearth already, so there's nothing to put anywhere for them. Google TV also keeps a spare profile user, made ahead
 * of time for the next profile added: it isn't supervised, so it's never one of these.
 *
 * <h3>New kids' profiles</h3>
 * Once a parent has put Hearth on the kids' profiles (the setup flow, or Fix in Settings) and the TV trusts Hearth's
 * adb key, Hearth puts itself on a kids' profile added later too ({@link #autoFixSoon}), within these limits:
 * <ul>
 *   <li>Only while that profile isn't running, as when the parent's Fix runs from their own profile: a running kids'
 *       profile's launcher checks its apps the moment one is added.</li>
 *   <li>Once per app and profile. Each add sends the parent a Family Link "app added" notice, so a copy that doesn't
 *       stay isn't put back over and over: Settings shows that profile as needing a fix instead.</li>
 *   <li>Never where connecting could ask "Allow debugging?": the TV must have run a command for Hearth's key before.
 *       If it no longer answers like that, Hearth stops trying until a parent's own action works again.</li>
 * </ul>
 * Taking Hearth off the kids' profiles ({@link #remove}) stops all of it.
 */
final class KidsProfiles {
    private static final String TAG = "HearthKids";
    private static final String PREFS = "hearth_kids_profiles";
    /** A parent put Hearth on the kids' profiles and hasn't taken it off since: new ones get it too. */
    private static final String KEEP = "keep";
    /** "auto|serial|package": Hearth put that app on that kids' profile by itself once already. */
    private static final String AUTO_PREFIX = "auto|";
    /** How long a parent's action may wait on adb, "Allow debugging?" included (the setup flow waits as long). */
    private static final int PARENT_TIMEOUT_MS = 120_000;
    /** How long one read may take otherwise: the commands answer in a second or two. */
    private static final int QUIET_TIMEOUT_MS = 30_000;
    /** After a profile switch, Google TV's own checks on the profiles' apps go first. */
    private static final long AUTO_DELAY_MS = 20_000;

    /** One thread: Hearth's own adds run one at a time, and a newer request replaces one still waiting. */
    private static final ScheduledExecutorService AUTO = Executors.newSingleThreadScheduledExecutor();
    private static ScheduledFuture<?> sPendingAuto;
    /** Held while anything here changes the profiles: a parent's Fix or Remove and Hearth's own adds never overlap. */
    private static final Object WORK = new Object();

    private KidsProfiles() {
    }

    /** One kids' profile, and which of Hearth's apps Android lists there. */
    static final class Kid {
        final int userId;
        final long serial;
        final String name;
        final boolean running;
        final boolean hearth;
        final boolean hearthTube;

        Kid(int userId, long serial, String name, boolean running, boolean hearth, boolean hearthTube) {
            this.userId = userId;
            this.serial = serial;
            this.name = name;
            this.running = running;
            this.hearth = hearth;
            this.hearthTube = hearthTube;
        }
    }

    /**
     * The kids' profiles: the Family Link-supervised profiles of Hearth's user, with Hearth's apps as Android lists
     * them there (no adb needed to see what's installed, only to change it).
     */
    static List<Kid> list(Context context) {
        List<Kid> kids = new ArrayList<>();
        UserManager users = (UserManager) context.getSystemService(Context.USER_SERVICE);
        if (users == null) return kids;
        UserHandle me = Process.myUserHandle();
        try {
            for (UserHandle profile : users.getUserProfiles()) {
                if (profile.equals(me)) continue;
                long serial = users.getSerialNumberForUser(profile);
                if (!Boolean.TRUE.equals(ProfileUsers.isSupervised(context, serial))) continue;
                int userId = userIdOf(profile);
                if (userId <= ProfileAppAccess.OWNER_USER) continue;
                kids.add(new Kid(userId, serial, ProfileUsers.getName(context, serial), isRunning(users, profile),
                        Boolean.TRUE.equals(hasApp(context, ProfileAppAccess.HEARTH, profile)),
                        Boolean.TRUE.equals(hasApp(context, ProfileAppAccess.HEARTHTUBE, profile))));
            }
        } catch (RuntimeException e) {
            Log.w(TAG, "Couldn't list the kids' profiles", e);
        }
        return kids;
    }

    /** How many kids' profiles have everything Hearth puts there: Hearth, and HearthTube when the owner has it. */
    static int countReady(Context context, List<Kid> kids) {
        boolean tube = hearthTubeOnOwner(context);
        int ready = 0;
        for (Kid kid : kids) {
            if (kid.hearth && (!tube || kid.hearthTube)) ready++;
        }
        return ready;
    }

    /**
     * For Settings and the setup flow: each kids' profile and what's on it, and how things stand. With
     * {@code checkProtection}, also whether each copy is kept (Google TV can't remove it), read over Hearth's adb, but
     * only when the TV trusts Hearth's key already: looking never asks "Allow debugging?".
     */
    static Map<String, Object> state(Context context, boolean checkProtection) {
        List<Kid> kids = list(context);
        Map<Integer, Map<String, ProfileAppAccess.AppStatus>> read = null;
        boolean adb = SetupFixes.isAdbEnabled(context);
        if (checkProtection && !kids.isEmpty() && adb && SelfAdb.isTrusted(context)) {
            try (SelfAdb shell = SelfAdb.open(context, QUIET_TIMEOUT_MS)) {
                read = new HashMap<>();
                for (ProfileAppAccess.AppStatus s : ProfileAppAccess.state(context.getPackageCodePath(), shell,
                        userIds(kids))) {
                    read.computeIfAbsent(s.userId, u -> new HashMap<>()).put(s.packageName, s);
                }
            } catch (Exception e) {
                Log.i(TAG, "Couldn't read whether the kids' copies are kept: " + e);
                read = null;
                if (!refused(e)) SelfAdb.forgetTrusted(context);
            }
        }
        List<Map<String, Object>> rows = new ArrayList<>();
        for (Kid kid : kids) {
            Map<String, Object> row = new HashMap<>();
            row.put("userId", kid.userId);
            // What Hearth keeps the profile's own settings under (its YouTube limit)
            row.put("profileKey", ProfileUsers.key(kid.serial));
            row.put("name", kid.name);
            row.put("running", kid.running);
            Map<String, ProfileAppAccess.AppStatus> apps = read != null ? read.get(kid.userId) : null;
            putApp(row, "hearth", kid.hearth, apps != null ? apps.get(ProfileAppAccess.HEARTH) : null);
            putApp(row, "hearthTube", kid.hearthTube, apps != null ? apps.get(ProfileAppAccess.HEARTHTUBE) : null);
            rows.add(row);
        }
        Map<String, Object> state = new HashMap<>();
        state.put("kids", rows);
        state.put("hearthTubeOnOwner", hearthTubeOnOwner(context));
        state.put("keep", prefs(context).getBoolean(KEEP, false));
        state.put("trusted", SelfAdb.isTrusted(context));
        state.put("adbEnabled", adb);
        state.put("protectionRead", read != null);
        return state;
    }

    /** One app's columns in a row: installed (adb's word when it was read), and kept when known. */
    private static void putApp(Map<String, Object> row, String name, boolean listed, ProfileAppAccess.AppStatus read) {
        row.put(name, read != null ? read.installed : listed);
        row.put(name + "Kept", read != null ? read.protectedFromRemoval : null);
    }

    /**
     * A parent's Fix (Settings, or the setup flow's kids' step): puts Hearth's apps on every kids' profile where one
     * is missing or not kept, and from now on on new kids' profiles too. The first time, the TV asks "Allow
     * debugging?"; until the parent allows it this throws. Call off the main thread.
     */
    static List<String> fix(Context context) throws Exception {
        synchronized (WORK) {
            // A parent's fix: each profile may get one more try of Hearth's own later
            setKeep(context, true);
            List<Kid> kids = list(context);
            if (kids.isEmpty()) return new ArrayList<>();
            try (SelfAdb shell = SelfAdb.open(context, PARENT_TIMEOUT_MS)) {
                List<String> log = ProfileAppAccess.addToKids(context.getPackageCodePath(), shell, userIds(kids));
                Log.i(TAG, "Fixed the kids' profiles: " + log);
                return log;
            }
        }
    }

    /**
     * A parent's Remove (Settings, and Uninstall Hearth before it opens Android's uninstall): takes Hearth's apps off
     * every kids' profile, and any other profile user they're on (left from older versions), and stops putting them on
     * new ones. Needs no adb when there's nothing to take off. Call off the main thread.
     */
    static List<String> remove(Context context) throws Exception {
        cancelAuto();
        synchronized (WORK) {
            setKeep(context, false);
            List<Integer> users = removalTargets(context);
            if (users.isEmpty()) return new ArrayList<>();
            try (SelfAdb shell = SelfAdb.open(context, PARENT_TIMEOUT_MS)) {
                List<String> log = ProfileAppAccess.remove(context.getPackageCodePath(), shell, users);
                Log.i(TAG, "Took Hearth off the other profiles: " + log);
                return log;
            }
        }
    }

    /** Whether new kids' profiles get Hearth; either way Hearth's own tries so far are forgotten. */
    private static void setKeep(Context context, boolean keep) {
        SharedPreferences prefs = prefs(context);
        SharedPreferences.Editor editor = prefs.edit().putBoolean(KEEP, keep);
        for (String key : prefs.getAll().keySet()) {
            if (key.startsWith(AUTO_PREFIX)) editor.remove(key);
        }
        editor.apply();
    }

    /**
     * Every kids' profile, and every other profile user where Android lists one of Hearth's apps or can't say: what
     * Remove takes Hearth off.
     */
    private static List<Integer> removalTargets(Context context) {
        List<Integer> users = userIds(list(context));
        UserManager um = (UserManager) context.getSystemService(Context.USER_SERVICE);
        if (um == null) return users;
        UserHandle me = Process.myUserHandle();
        for (UserHandle profile : um.getUserProfiles()) {
            int userId = userIdOf(profile);
            if (profile.equals(me) || userId <= ProfileAppAccess.OWNER_USER || users.contains(userId)) continue;
            Boolean hearth = hasApp(context, ProfileAppAccess.HEARTH, profile);
            Boolean tube = hasApp(context, ProfileAppAccess.HEARTHTUBE, profile);
            if (!Boolean.FALSE.equals(hearth) || !Boolean.FALSE.equals(tube)) users.add(userId);
        }
        return users;
    }

    /**
     * After a profile switch, or when Hearth's service starts: in a little while, puts Hearth's apps on the kids'
     * profiles that need them, within the limits in this class's notes. Only in the owner's user.
     */
    static synchronized void autoFixSoon(Context context) {
        if (AgentService.isAgent(context)) return;
        Context app = context.getApplicationContext();
        if (sPendingAuto != null) sPendingAuto.cancel(false);
        sPendingAuto = AUTO.schedule(() -> autoFix(app), AUTO_DELAY_MS, TimeUnit.MILLISECONDS);
    }

    private static synchronized void cancelAuto() {
        if (sPendingAuto != null) sPendingAuto.cancel(false);
        sPendingAuto = null;
    }

    private static void autoFix(Context context) {
        synchronized (WORK) {
            autoFixNow(context);
        }
    }

    private static void autoFixNow(Context context) {
        SharedPreferences prefs = prefs(context);
        Map<Kid, List<String>> fixes = autoFixes(prefs.getBoolean(KEEP, false),
                SelfAdb.isTrusted(context) && SetupFixes.isAdbEnabled(context), list(context),
                hearthTubeOnOwner(context), prefs.getAll().keySet());
        if (fixes.isEmpty()) return;
        Map<Integer, List<String>> packages = new LinkedHashMap<>();
        for (Map.Entry<Kid, List<String>> fix : fixes.entrySet()) packages.put(fix.getKey().userId, fix.getValue());
        boolean tried = true;
        try (SelfAdb shell = SelfAdb.open(context, QUIET_TIMEOUT_MS)) {
            List<String> log = ProfileAppAccess.addToKids(context.getPackageCodePath(), shell, packages);
            Log.i(TAG, "Put Hearth on kids' profiles by itself: " + log);
        } catch (Exception e) {
            // Nobody listening (debugging off since, or after a restart): nothing ran, so the next switch tries again.
            // Anything else may have run, and may mean the TV no longer trusts Hearth's key: no more tries of its own
            tried = !refused(e);
            Log.i(TAG, "Couldn't put Hearth on the kids' profiles by itself: " + e);
            if (tried) SelfAdb.forgetTrusted(context);
        }
        if (!tried) return;
        SharedPreferences.Editor editor = prefs.edit();
        for (Map.Entry<Kid, List<String>> fix : fixes.entrySet()) {
            for (String pkg : fix.getValue()) editor.putBoolean(autoKey(fix.getKey().serial, pkg), true);
        }
        editor.apply();
    }

    /**
     * What Hearth may put on the kids' profiles by itself: nothing unless a parent has put Hearth on them
     * ({@code keep}) and the TV trusts Hearth's key; then, for each kids' profile that isn't running, each of
     * Hearth's apps missing there that Hearth hasn't put there by itself before ({@code done}: the saved keys).
     * HearthTube only when the owner has it.
     */
    static Map<Kid, List<String>> autoFixes(boolean keep, boolean trusted, List<Kid> kids, boolean hearthTubeOnOwner,
            Set<String> done) {
        Map<Kid, List<String>> fixes = new LinkedHashMap<>();
        if (!keep || !trusted) return fixes;
        for (Kid kid : kids) {
            if (kid.running) continue;
            List<String> missing = new ArrayList<>();
            if (!kid.hearth && !done.contains(autoKey(kid.serial, ProfileAppAccess.HEARTH))) {
                missing.add(ProfileAppAccess.HEARTH);
            }
            if (hearthTubeOnOwner && !kid.hearthTube && !done.contains(autoKey(kid.serial, ProfileAppAccess.HEARTHTUBE))) {
                missing.add(ProfileAppAccess.HEARTHTUBE);
            }
            if (!missing.isEmpty()) fixes.put(kid, missing);
        }
        return fixes;
    }

    static String autoKey(long serial, String pkg) {
        return AUTO_PREFIX + serial + "|" + pkg;
    }

    /** The adb connection was refused or unreachable: nothing was sent, so nothing ran. */
    static boolean refused(Throwable e) {
        for (Throwable t = e; t != null; t = t.getCause()) {
            if (t instanceof ConnectException || t instanceof java.net.NoRouteToHostException) return true;
        }
        return false;
    }

    // --- internals ---

    private static SharedPreferences prefs(Context context) {
        return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    private static List<Integer> userIds(List<Kid> kids) {
        List<Integer> ids = new ArrayList<>();
        for (Kid kid : kids) ids.add(kid.userId);
        return ids;
    }

    /** Whether the owner (Hearth's own user) has HearthTube: only then do the kids' profiles get it. */
    static boolean hearthTubeOnOwner(Context context) {
        try {
            context.getPackageManager().getPackageInfo(ProfileAppAccess.HEARTHTUBE, 0);
            return true;
        } catch (PackageManager.NameNotFoundException e) {
            return false;
        }
    }

    /** Whether Android lists the app's screen in that profile's user; null when it can't say. */
    private static Boolean hasApp(Context context, String pkg, UserHandle user) {
        try {
            LauncherApps apps = (LauncherApps) context.getSystemService(Context.LAUNCHER_APPS_SERVICE);
            return apps != null ? !apps.getActivityList(pkg, user).isEmpty() : null;
        } catch (RuntimeException e) {
            return null;
        }
    }

    /** Whether the profile's user runs (it's the profile on now); counts as running when that can't be read. */
    private static boolean isRunning(UserManager users, UserHandle profile) {
        try {
            return users.isUserRunning(profile);
        } catch (RuntimeException e) {
            return true;
        }
    }

    /** The integer user id behind a {@link UserHandle} (needed for {@code pm --user}); -1 if unknown. */
    static int userIdOf(UserHandle handle) {
        try {
            // UserHandle.getIdentifier() is @hide, so reach it reflectively; fall back to parsing "UserHandle{N}".
            return (int) UserHandle.class.getMethod("getIdentifier").invoke(handle);
        } catch (Exception e) {
            Matcher m = Pattern.compile("\\d+").matcher(String.valueOf(handle));
            return m.find() ? Integer.parseInt(m.group()) : -1;
        }
    }
}
