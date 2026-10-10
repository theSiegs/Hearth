package com.thesiegs.hearth;

import android.content.Context;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;

/**
 * The shell commands that put Hearth's OWN apps (Hearth, HearthTube) on the TV's kids' profiles, keep them there,
 * and take them back off. Which users are kids' profiles, and when to act, is {@link KidsProfiles}' call; this class
 * only runs the commands, as the {@code shell} user over Hearth's own adb ({@link SelfAdb}).
 *
 * <p>Only kids' profiles get them: Google TV runs each one as an Android user of its own, supervised by Family Link.
 * A grown-up's profile is another Google account in the owner's user, which has Hearth already.
 *
 * <h3>Kept installed</h3>
 * Google TV's launcher uninstalls every app that didn't come from the Play Store from a kids' profile, at each
 * profile start and whenever an app there changes. So each copy gets Android's per-user "block uninstall" flag
 * ({@link KidsBlockUninstallMain}), which stops that.
 *
 * <h3>Limits that hold whoever calls</h3>
 * <ul>
 *   <li>Only {@link #OWN_PACKAGES}, Hearth and HearthTube: never another app.</li>
 *   <li>Never the owner's user: {@link #addToKids} and {@link #remove} refuse user 0.</li>
 *   <li>Only what the owner has: install-existing copies the owner's app, so one the owner doesn't have is skipped.</li>
 *   <li>Adding changes only what's out of place: a copy that's there and kept is left alone, so Family Link's "app
 *       added" notice goes out only for a copy that's actually added.</li>
 * </ul>
 *
 * <h3>The one safety rule</h3>
 * A kept copy can't be uninstalled until its flag is lifted ({@code DELETE_FAILED_OWNER_BLOCKED}). So
 * {@link #remove} lifts the flag BEFORE it uninstalls, and Hearth's own uninstall flow runs it first: otherwise the
 * kids' copies would be left behind once Hearth (and its adb) is gone. Shell can always lift the flag, so nothing can
 * get stuck.
 */
public final class ProfileAppAccess {

    /** Hearth's app id, without the debug suffix. */
    public static final String HEARTH = BuildConfig.HEARTH_APP_ID;
    public static final String HEARTHTUBE = "com.thesiegs.hearthtube";
    /** Hearth's own packages: the ONLY packages this class ever installs, protects, or removes. */
    static final String[] OWN_PACKAGES = {HEARTH, HEARTHTUBE};

    /** The owner (TV account) user, whose copy of each app the kids' copies are made from via install-existing. */
    static final int OWNER_USER = 0;

    /** The class {@link KidsBlockUninstallMain} runs as, invoked via app_process over the shell connection. */
    private static final String HELPER_CLASS = KidsBlockUninstallMain.class.getName();

    private ProfileAppAccess() {
    }

    /**
     * Runs a single command as the {@code shell} user. The only implementation is {@link SelfAdb} (Hearth's own
     * loopback adb connection); tests pass a fake. A tiny interface so the commands have no direct dependency on the
     * transport.
     */
    public interface ShellRunner {
        String run(String command) throws Exception;
    }

    /** One app's state in one profile, for Settings' kids' profiles page. */
    public static final class AppStatus {
        public final int userId;
        public final String packageName;
        public final boolean installed;
        public final boolean protectedFromRemoval;

        AppStatus(int userId, String packageName, boolean installed, boolean protectedFromRemoval) {
            this.userId = userId;
            this.packageName = packageName;
            this.installed = installed;
            this.protectedFromRemoval = protectedFromRemoval;
        }
    }

    /**
     * Puts Hearth's apps on the given kids' profiles and keeps them there: for each app the owner has, adds the copy
     * where it's missing and sets the keep flag where it isn't set. Only for user ids {@link KidsProfiles} found to
     * be kids' profiles.
     *
     * @param apk Hearth's own APK, which the flag helper runs from.
     * @return a short log of what was done.
     */
    static List<String> addToKids(String apk, ShellRunner shell, List<Integer> kidUserIds) throws Exception {
        Map<Integer, List<String>> packages = new LinkedHashMap<>();
        for (int user : kidUserIds) packages.put(user, Arrays.asList(OWN_PACKAGES));
        return addToKids(apk, shell, packages);
    }

    /** {@link #addToKids(String, ShellRunner, List)} for only some of Hearth's apps on each profile. */
    static List<String> addToKids(String apk, ShellRunner shell, Map<Integer, List<String>> packagesByUser)
            throws Exception {
        List<String> log = new ArrayList<>();
        Set<String> owner = installedFor(shell, OWNER_USER);
        for (Map.Entry<Integer, List<String>> entry : packagesByUser.entrySet()) {
            int user = entry.getKey();
            requireOtherUser(user);
            Set<String> there = installedFor(shell, user);
            for (String pkg : OWN_PACKAGES) {
                if (!entry.getValue().contains(pkg)) continue;
                // install-existing copies the owner's app, so one the owner doesn't have (HearthTube not installed
                // yet) is skipped rather than logged as a failure
                if (!owner.contains(pkg)) {
                    log.add(String.format(Locale.US, "user %d: skipped %s (not installed for the owner)", user, pkg));
                    continue;
                }
                boolean added = false;
                if (!there.contains(pkg)) {
                    // Keep first: while that profile runs, Google TV's launcher checks its apps as soon as one is
                    // added, and would remove the copy before a flag set afterwards could stop it
                    setProtected(shell, apk, pkg, user, true);
                    shell.run("pm install-existing --user " + user + " " + pkg);
                    added = true;
                }
                // Set it again when it didn't take: the flag may only hold for a copy that's installed
                boolean kept = isProtected(shell, apk, pkg, user);
                if (!kept) setProtected(shell, apk, pkg, user, true);
                if (added) {
                    log.add(String.format(Locale.US, "user %d: added and kept %s", user, pkg));
                } else if (!kept) {
                    log.add(String.format(Locale.US, "user %d: kept %s", user, pkg));
                }
            }
        }
        return log;
    }

    /**
     * Lifts the keep flag and uninstalls Hearth's apps from the given profiles: the undo of {@link #addToKids}, and
     * the step Hearth runs before it's uninstalled itself. Safe on any profile but the owner's: lifting a flag that
     * was never set, or uninstalling an app that isn't there, changes nothing.
     */
    static List<String> remove(String apk, ShellRunner shell, List<Integer> userIds) throws Exception {
        List<String> log = new ArrayList<>();
        for (int user : userIds) {
            requireOtherUser(user);
            for (String pkg : OWN_PACKAGES) {
                // SAFETY: release the flag FIRST: a kept package can't be uninstalled (DELETE_FAILED_OWNER_BLOCKED)
                setProtected(shell, apk, pkg, user, false);
                shell.run("pm uninstall --user " + user + " " + pkg);
                log.add(String.format(Locale.US, "user %d: removed %s", user, pkg));
            }
        }
        return log;
    }

    /**
     * Automatic, safe self-cleanup used when Hearth is being removed (a profile's agent found owner-Hearth gone):
     * releases any keep flag and uninstalls Hearth's own apps for that one profile, so Google TV's launcher drops
     * them. Removal only (it never installs or protects): the undo that must be able to run on its own so nothing is
     * left behind.
     */
    static List<String> cleanupUser(Context context, ShellRunner shell, int userId) throws Exception {
        return remove(context.getPackageCodePath(), shell, Collections.singletonList(userId));
    }

    /** Read-only: for the given profiles, which have Hearth / HearthTube and whether each is kept (flagged). */
    static List<AppStatus> state(String apk, ShellRunner shell, List<Integer> userIds) throws Exception {
        List<AppStatus> out = new ArrayList<>();
        for (int user : userIds) {
            Set<String> there = installedFor(shell, user);
            for (String pkg : OWN_PACKAGES) {
                out.add(new AppStatus(user, pkg, there.contains(pkg), isProtected(shell, apk, pkg, user)));
            }
        }
        return out;
    }

    /**
     * Sets the keep-installed flag on one of Hearth's apps in one profile and reports whether it holds. Used by a
     * profile's agent to replace the old device-admin protection with the flag (AgentService.retireOldAdmin).
     */
    static boolean keepInstalled(Context context, ShellRunner shell, String pkg, int userId) throws Exception {
        String apk = context.getPackageCodePath();
        setProtected(shell, apk, pkg, userId, true);
        return isProtected(shell, apk, pkg, userId);
    }

    // --- internals ---

    private static void requireOtherUser(int user) {
        if (user <= OWNER_USER) {
            throw new IllegalArgumentException("Refusing to act on user " + user + ": only other profiles' users.");
        }
    }

    /** Hearth's own packages installed for this user, from one {@code pm list packages}. */
    private static Set<String> installedFor(ShellRunner shell, int user) throws Exception {
        Set<String> own = new HashSet<>();
        String out = shell.run("pm list packages --user " + user);
        if (out == null) return own;
        for (String line : out.split("\\r?\\n")) {
            for (String pkg : OWN_PACKAGES) {
                if (line.trim().equals("package:" + pkg)) own.add(pkg);
            }
        }
        return own;
    }

    private static void setProtected(ShellRunner shell, String apk, String pkg, int user, boolean value)
            throws Exception {
        shell.run("CLASSPATH=" + apk + " app_process /system/bin " + HELPER_CLASS + " " + pkg + " " + user + " "
                + value);
    }

    private static boolean isProtected(ShellRunner shell, String apk, String pkg, int user) throws Exception {
        String out = shell.run("CLASSPATH=" + apk + " app_process /system/bin " + HELPER_CLASS + " " + pkg + " "
                + user);
        return out != null && out.contains("blockUninstall=true");
    }
}
