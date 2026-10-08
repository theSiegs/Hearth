package com.leanbitlab.ltvL;

import android.content.Context;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

/**
 * Lets a parent put Hearth's OWN apps (Hearth, HearthTube) into their kids' Google TV profiles and — just as
 * easily — take them back out. Entirely parent-controlled: see the three entry points below, each of which maps to
 * one row in Settings -> Setup &amp; permissions and does nothing unless the parent started it.
 *
 * <h3>Why this is needed</h3>
 * Google TV's launcher uninstalls any non-Play app from a kids profile at every profile start. The only thing that
 * keeps a copy is Android's per-user "block uninstall" flag ({@link KidsBlockUninstallMain}). Setting that flag needs
 * the {@code shell} user, which Hearth reaches over its own loopback adb connection ({@link SelfAdb}) after the
 * parent approves one on-screen "Allow debugging?" prompt.
 *
 * <h3>User control is the whole point (and is enforced here, not just documented)</h3>
 * <ul>
 *   <li>{@link #addToKidsProfiles} and {@link #removeFromKidsProfiles} both require {@code confirmedByParent == true}
 *       and throw otherwise, so neither can run as a side effect of anything automatic.</li>
 *   <li>They act ONLY on the {@code kidUserIds} the caller passes — Hearth supplies the <em>supervised</em> kids
 *       profiles (see {@code ProfileUsers.isSupervised}), never a grown-up or half-provisioned user.</li>
 *   <li>They touch ONLY {@link #OWN_PACKAGES} — Hearth and HearthTube — never any other app.</li>
 *   <li>{@link #state} only reads; the Settings screen shows it so nothing is hidden.</li>
 *   <li>Adding protects a copy; removing releases the protection <em>and</em> uninstalls the copy. A clean,
 *       reversible round trip — no device-admin, nothing that can be left stuck (see {@link #removeFromKidsProfiles}).
 *       </li>
 * </ul>
 *
 * <h3>The one safety rule</h3>
 * A protected copy cannot be uninstalled until its flag is lifted (Android returns
 * {@code DELETE_FAILED_OWNER_BLOCKED}). So {@link #removeFromKidsProfiles} always lifts the flag BEFORE it
 * uninstalls, and Hearth's own uninstall flow must run {@link #removeFromKidsProfiles} first — otherwise the kid
 * copies would be orphaned once Hearth is gone and the flag can no longer be lifted from the device.
 */
public final class KidsAppAccess {

    /** Hearth's own packages: the ONLY packages this feature ever installs, protects, or removes. */
    public static final String HEARTH = "com.leanbitlab.ltvL";
    public static final String HEARTHTUBE = "com.thesiegs.hearthtube";
    private static final String[] OWN_PACKAGES = {HEARTH, HEARTHTUBE};

    /** The owner (TV account) user, whose copy of each app the kid copies are cloned from via install-existing. */
    private static final int OWNER_USER = 0;

    /** The class {@link KidsBlockUninstallMain} runs as, invoked via app_process over the shell connection. */
    private static final String HELPER_CLASS = "com.leanbitlab.ltvL.KidsBlockUninstallMain";

    private KidsAppAccess() {
    }

    /**
     * Runs a single command as the {@code shell} user. The only implementation is {@link SelfAdb} (Hearth's own
     * loopback adb connection). Kept as a tiny interface so the provisioning logic below has no direct dependency on
     * the adb transport and can be unit-tested with a fake.
     */
    public interface ShellRunner {
        /** Runs {@code command} and returns its combined stdout+stderr. Throws if the command can't be run. */
        String run(String command) throws Exception;
    }

    /** One app's state in one kid profile, for the Settings "what's where" view. */
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
     * Parent-initiated: add Hearth's apps to the given kids profiles and protect them from the launcher's uninstall.
     * Called ONLY from Settings -> "Add Hearth to kids' profiles" after the parent reads what it will do and confirms.
     *
     * @param kidUserIds        the <em>supervised</em> kid profile user ids to act on (Hearth supplies these).
     * @param confirmedByParent must be {@code true}; it is the in-code record that a parent started this.
     * @return a human-readable log of what was done, for the Settings screen to show back.
     */
    public static List<String> addToKidsProfiles(Context context, ShellRunner shell, List<Integer> kidUserIds,
            boolean confirmedByParent) throws Exception {
        requireParent(confirmedByParent, "add Hearth to kids' profiles");
        String apk = context.getPackageCodePath();
        List<String> log = new ArrayList<>();
        for (int user : kidUserIds) {
            for (String pkg : OWN_PACKAGES) {
                // Only clone apps the owner actually has: install-existing fails for a package not installed in
                // user 0 (e.g. HearthTube not installed yet), so skip it and say so rather than log a failure.
                if (!isInstalledForUser(shell, pkg, OWNER_USER)) {
                    log.add(String.format(Locale.US, "user %d: skipped %s (not installed for the owner)", user, pkg));
                    continue;
                }
                // 1) INSTALL here: make the owner's copy launchable in this profile. The APK is already on the
                //    device, so this just flips the per-user bit — no download.
                shell.run("pm install-existing --user " + user + " " + pkg);
                // 2) PROTECT here: keep the launcher from uninstalling it at the next profile start.
                setProtected(shell, apk, pkg, user, true);
                log.add(String.format(Locale.US, "user %d: added + protected %s", user, pkg));
            }
        }
        return log;
    }

    /**
     * Parent-initiated: remove Hearth's apps from the given kids profiles and release their protection. Called ONLY
     * from Settings -> "Remove Hearth from kids' profiles". Also the step Hearth must run on itself before it can be
     * uninstalled, so nothing is left behind.
     *
     * @param kidUserIds        the kid profile user ids to act on.
     * @param confirmedByParent must be {@code true}.
     * @return a human-readable log of what was done.
     */
    public static List<String> removeFromKidsProfiles(Context context, ShellRunner shell, List<Integer> kidUserIds,
            boolean confirmedByParent) throws Exception {
        requireParent(confirmedByParent, "remove Hearth from kids' profiles");
        String apk = context.getPackageCodePath();
        List<String> log = new ArrayList<>();
        for (int user : kidUserIds) {
            for (String pkg : OWN_PACKAGES) {
                // SAFETY: release the protection FIRST. A protected package can't be uninstalled
                // (DELETE_FAILED_OWNER_BLOCKED), so lifting the flag before the uninstall is what keeps this a clean,
                // reversible operation with nothing stuck.
                setProtected(shell, apk, pkg, user, false);
                // UNINSTALL here: remove this profile's copy. The owner's device-wide copy is untouched.
                shell.run("pm uninstall --user " + user + " " + pkg);
                log.add(String.format(Locale.US, "user %d: unprotected + removed %s", user, pkg));
            }
        }
        return log;
    }

    /** Read-only: for the given kids profiles, which have Hearth / HearthTube and whether each is protected. */
    public static List<AppStatus> state(Context context, ShellRunner shell, List<Integer> kidUserIds)
            throws Exception {
        String apk = context.getPackageCodePath();
        List<AppStatus> out = new ArrayList<>();
        for (int user : kidUserIds) {
            for (String pkg : OWN_PACKAGES) {
                out.add(new AppStatus(user, pkg, isInstalledForUser(shell, pkg, user),
                        isProtected(shell, apk, pkg, user)));
            }
        }
        return out;
    }

    // --- internals ---

    private static void requireParent(boolean confirmedByParent, String action) {
        if (!confirmedByParent) {
            // Deliberately a hard failure: this code only ever acts on an explicit parent action from Settings.
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
        // Reads the flag (no third argument) and parses the helper's fixed "blockUninstall=<bool>" line.
        String out = shell.run("CLASSPATH=" + apk + " app_process /system/bin " + HELPER_CLASS + " " + pkg + " "
                + user);
        return out != null && out.contains("blockUninstall=true");
    }
}
