package com.thesiegs.hearth;

import android.content.Context;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

/**
 * Lets a parent put Hearth's OWN apps (Hearth, HearthTube) into the TV's other Google TV profiles and — just as
 * easily — take them back out. Entirely parent-controlled: see the entry points below, each reached only from a
 * Settings action the parent started.
 *
 * <h3>Two kinds of profile, one difference</h3>
 * <ul>
 *   <li><b>Supervised kids profiles</b> — Google TV's launcher uninstalls any non-Play app from them at every
 *       profile start, so these are added with {@code keepInstalled = true}: the per-user "block uninstall" flag
 *       ({@link KidsBlockUninstallMain}) keeps the copy.</li>
 *   <li><b>Other adult profiles</b> — the launcher leaves their apps alone, so these are added with
 *       {@code keepInstalled = false}: a plain install, no flag. This is purely a convenience so another adult in
 *       the family doesn't have to sideload Hearth themselves.</li>
 * </ul>
 * The caller ({@code MainActivity}) classifies each profile (supervised vs. not) and passes the right
 * {@code keepInstalled}; this class never guesses.
 *
 * <h3>User control is enforced, not just documented</h3>
 * <ul>
 *   <li>{@link #addToProfiles} and {@link #removeFromProfiles} require {@code confirmedByParent == true} and throw
 *       otherwise, so neither runs as a side effect of anything automatic.</li>
 *   <li>They act only on the user ids the caller passes, and touch only {@link #OWN_PACKAGES} — Hearth and
 *       HearthTube — never any other app.</li>
 *   <li>{@link #state} only reads; Settings shows it so nothing is hidden.</li>
 *   <li>Adding is reversible: {@link #removeFromProfiles} releases any keep-installed flag and uninstalls the copy.
 *       No device-admin is used, so nothing can be left stuck (shell can always lift the flag).</li>
 * </ul>
 *
 * <h3>The one safety rule</h3>
 * A kept copy can't be uninstalled until its flag is lifted ({@code DELETE_FAILED_OWNER_BLOCKED}). So
 * {@link #removeFromProfiles} lifts the flag BEFORE it uninstalls, and Hearth's own uninstall flow must run
 * {@link #removeFromProfiles} first — otherwise kid copies would be orphaned once Hearth (and its adb) is gone.
 */
public final class ProfileAppAccess {

    /** Hearth's app id, without the debug suffix. */
    public static final String HEARTH = BuildConfig.HEARTH_APP_ID;
    public static final String HEARTHTUBE = "com.thesiegs.hearthtube";
    /** Hearth's own packages: the ONLY packages this feature ever installs, protects, or removes. */
    private static final String[] OWN_PACKAGES = {HEARTH, HEARTHTUBE};

    /** The owner (TV account) user, whose copy of each app the others are cloned from via install-existing. */
    private static final int OWNER_USER = 0;

    /** The class {@link KidsBlockUninstallMain} runs as, invoked via app_process over the shell connection. */
    private static final String HELPER_CLASS = KidsBlockUninstallMain.class.getName();

    private ProfileAppAccess() {
    }

    /**
     * Runs a single command as the {@code shell} user. The only implementation is {@link SelfAdb} (Hearth's own
     * loopback adb connection). A tiny interface so the provisioning logic has no direct dependency on the transport.
     */
    public interface ShellRunner {
        String run(String command) throws Exception;
    }

    /** One app's state in one profile, for the Settings "what's where" view. */
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
     * Parent-initiated: add Hearth's apps to the given profiles. Called only from a Settings action.
     *
     * @param userIds           the profile user ids to act on (supervised kids and/or adults — caller decides).
     * @param keepInstalled     true for supervised kids (set the block-uninstall flag so the launcher can't strip
     *                          them); false for adult profiles (plain install — the launcher leaves them alone).
     * @param confirmedByParent must be true; the in-code record that a parent started this.
     * @return a human-readable log of what was done.
     */
    public static List<String> addToProfiles(Context context, ShellRunner shell, List<Integer> userIds,
            boolean keepInstalled, boolean confirmedByParent) throws Exception {
        requireParent(confirmedByParent, "add Hearth to other profiles");
        String apk = context.getPackageCodePath();
        List<String> log = new ArrayList<>();
        for (int user : userIds) {
            for (String pkg : OWN_PACKAGES) {
                // Only clone apps the owner actually has: install-existing fails for a package not installed in
                // user 0 (e.g. HearthTube not installed yet), so skip it and say so rather than log a failure.
                if (!isInstalledForUser(shell, pkg, OWNER_USER)) {
                    log.add(String.format(Locale.US, "user %d: skipped %s (not installed for the owner)", user, pkg));
                    continue;
                }
                // INSTALL here: make the owner's copy launchable in this profile (instant — APK already on device).
                shell.run("pm install-existing --user " + user + " " + pkg);
                if (keepInstalled) {
                    // KEEP here (kids only): stop the launcher uninstalling it at the next profile start.
                    setProtected(shell, apk, pkg, user, true);
                    log.add(String.format(Locale.US, "user %d: added + kept %s", user, pkg));
                } else {
                    log.add(String.format(Locale.US, "user %d: added %s", user, pkg));
                }
            }
        }
        return log;
    }

    /**
     * Parent-initiated: release any keep-installed flag and uninstall Hearth's apps from the given profiles — the
     * clean undo of {@link #addToProfiles}, and the step Hearth must run on itself before it can be uninstalled.
     * Safe for adult profiles too: lifting a flag that was never set is a no-op.
     */
    public static List<String> removeFromProfiles(Context context, ShellRunner shell, List<Integer> userIds,
            boolean confirmedByParent) throws Exception {
        requireParent(confirmedByParent, "remove Hearth from other profiles");
        String apk = context.getPackageCodePath();
        List<String> log = new ArrayList<>();
        for (int user : userIds) {
            for (String pkg : OWN_PACKAGES) {
                // SAFETY: release the flag FIRST — a kept package can't be uninstalled (DELETE_FAILED_OWNER_BLOCKED).
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
     * them. Removal-only (it never installs or protects), so no parent confirmation is needed — this is the undo that
     * must be able to run on its own to avoid leaving zombies behind.
     */
    public static List<String> cleanupUser(Context context, ShellRunner shell, int userId) throws Exception {
        return removeFromProfiles(context, shell, java.util.Collections.singletonList(userId), true);
    }

    /** Read-only: for the given profiles, which have Hearth / HearthTube and whether each is kept (flagged). */
    public static List<AppStatus> state(Context context, ShellRunner shell, List<Integer> userIds) throws Exception {
        String apk = context.getPackageCodePath();
        List<AppStatus> out = new ArrayList<>();
        for (int user : userIds) {
            for (String pkg : OWN_PACKAGES) {
                out.add(new AppStatus(user, pkg, isInstalledForUser(shell, pkg, user),
                        isProtected(shell, apk, pkg, user)));
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

    private static void requireParent(boolean confirmedByParent, String action) {
        if (!confirmedByParent) {
            throw new IllegalStateException("Refusing to " + action + ": not a parent-confirmed action.");
        }
    }

    private static boolean isInstalledForUser(ShellRunner shell, String pkg, int user) throws Exception {
        String target = "package:" + pkg;
        for (String line : shell.run("pm list packages --user " + user).split("\\r?\\n")) {
            if (line.trim().equals(target)) return true;
        }
        return false;
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
