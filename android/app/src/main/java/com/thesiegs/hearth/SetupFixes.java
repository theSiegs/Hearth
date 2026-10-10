package com.thesiegs.hearth;

import android.content.ComponentName;
import android.content.Context;
import android.content.SharedPreferences;
import android.content.pm.PackageInstaller;
import android.os.Build;
import android.provider.Settings;
import android.util.Log;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;
import java.util.regex.Pattern;

/**
 * What Hearth's first-run setup asks Android about, and the few fixes it may run itself over its own loopback adb
 * ({@link SelfAdb}) once the parent has approved "Allow debugging?". Each fix is a fixed, named set of commands
 * built here (Flutter only names the fix), and Flutter shows them to the parent before it runs any. They only ever
 * touch Hearth's own permissions.
 */
final class SetupFixes {
    private static final String TAG = "HearthSetup";

    /** Lift Android 13+'s block on a downloaded app's accessibility switches. */
    static final String RESTRICTED_SETTINGS = "restricted_settings";
    static final String HOME_BUTTON_FIX = "home_button_fix";
    static final String PROFILE_PAIRING = "profile_pairing";
    static final String WATCH_NEXT = "watch_next";
    static final String NOTIFICATION_ACCESS = "notification_access";

    private static final String PREFS = "hearth_setup";
    /** The install (its lastUpdateTime) whose block Hearth lifted itself: an update may bring the block back. */
    private static final String LIFTED_FOR_INSTALL = "restricted_lifted_for";

    /** What a component list may hold before Hearth puts it in a shell command: package and class names only. */
    private static final Pattern SAFE_COMPONENTS = Pattern.compile("[A-Za-z0-9_.$/:]*");

    private SetupFixes() {
    }

    /**
     * Whether Android may block Hearth's accessibility switches (they show greyed out): Android 13+ does that to an app
     * installed from a downloaded or local file. The block itself is the ACCESS_RESTRICTED_SETTINGS app-op, but Android
     * doesn't let an app read it, not even its own (it wants MANAGE_APPOPS; seen on Android 14), so this goes by where
     * Hearth was installed from, unless Hearth lifted the block itself for this install.
     */
    static boolean mayHaveRestrictedSettings(Context context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return false;
        try {
            long installed = context.getPackageManager().getPackageInfo(context.getPackageName(), 0).lastUpdateTime;
            if (prefs(context).getLong(LIFTED_FOR_INSTALL, 0) == installed) return false;
            int source = context.getPackageManager().getInstallSourceInfo(context.getPackageName()).getPackageSource();
            return source == PackageInstaller.PACKAGE_SOURCE_LOCAL_FILE
                    || source == PackageInstaller.PACKAGE_SOURCE_DOWNLOADED_FILE;
        } catch (Exception e) {
            return false;
        }
    }

    /** Hearth lifted the block on this install with its own adb: its switches aren't blocked until the next install. */
    private static void rememberLifted(Context context) {
        try {
            long installed = context.getPackageManager().getPackageInfo(context.getPackageName(), 0).lastUpdateTime;
            prefs(context).edit().putLong(LIFTED_FOR_INSTALL, installed).apply();
        } catch (Exception e) {
            Log.w(TAG, "Couldn't note the lifted block", e);
        }
    }

    private static SharedPreferences prefs(Context context) {
        return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    /** Whether the TV's debugging switch (Developer options) is on: self-adb needs it. Apps may read this setting. */
    static boolean isAdbEnabled(Context context) {
        return Settings.Global.getInt(context.getContentResolver(), Settings.Global.ADB_ENABLED, 0) == 1;
    }

    /** The shell commands a fix runs, for the parent to see first; null for a fix Hearth doesn't know. */
    static List<String> commands(Context context, String fix) {
        String pkg = context.getPackageName();
        if (fix == null) return null;
        switch (fix) {
            case RESTRICTED_SETTINGS:
                return Collections.singletonList("appops set " + pkg + " ACCESS_RESTRICTED_SETTINGS allow");
            case HOME_BUTTON_FIX:
                return accessibilityCommands(context, LauncherAccessibilityService.class);
            case PROFILE_PAIRING:
                return accessibilityCommands(context, ProfilePairingService.class);
            case WATCH_NEXT:
                // What requestWatchNextPermission asks for; either of the two lets Hearth read Watch Next
                return Collections.singletonList("pm grant " + pkg + " android.permission.READ_TV_LISTINGS");
            case NOTIFICATION_ACCESS:
                return Collections.singletonList("cmd notification allow_listener "
                        + new ComponentName(context, LauncherNotificationListenerService.class).flattenToString());
            default:
                return null;
        }
    }

    /**
     * Turns one of Hearth's accessibility services on next to the ones already on: the list is one setting, so it's
     * rewritten whole. Null when the current list has something Hearth won't put in a command.
     */
    private static List<String> accessibilityCommands(Context context, Class<?> service) {
        String component = new ComponentName(context, service).flattenToString();
        String current = Settings.Secure.getString(context.getContentResolver(),
                Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES);
        List<String> services = new ArrayList<>();
        if (current != null && !current.isEmpty()) services.addAll(Arrays.asList(current.split(":")));
        // Android may list Hearth's own services by their short name (".LauncherAccessibilityService")
        String shortName = new ComponentName(context, service).flattenToShortString();
        if (!services.contains(component) && !services.contains(shortName)) services.add(component);
        String list = String.join(":", services);
        if (!SAFE_COMPONENTS.matcher(list).matches()) return null;
        return Arrays.asList(
                "settings put secure enabled_accessibility_services '" + list + "'",
                "settings put secure accessibility_enabled 1");
    }

    /**
     * Runs the fixes' commands over self-adb, in order, and returns what the shell said. Call off the main thread.
     * The first time, the TV shows "Allow debugging?"; until the parent approves it this throws.
     */
    static List<String> run(Context context, List<String> fixes) throws Exception {
        List<String> commands = new ArrayList<>();
        for (String fix : fixes) {
            List<String> fixCommands = commands(context, fix);
            if (fixCommands == null) throw new IllegalArgumentException("Not a setup fix: " + fix);
            commands.addAll(fixCommands);
        }
        List<String> log = new ArrayList<>();
        try (SelfAdb shell = SelfAdb.open(context)) {
            for (String command : commands) {
                String output = shell.run(command);
                Log.i(TAG, "Ran " + command + (output == null || output.isEmpty() ? "" : ": " + output.trim()));
                if (output != null && !output.trim().isEmpty()) log.add(output.trim());
            }
        }
        if (fixes.contains(RESTRICTED_SETTINGS)) rememberLifted(context);
        return log;
    }
}
