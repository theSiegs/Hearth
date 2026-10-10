package com.thesiegs.hearth;

import android.app.AppOpsManager;
import android.content.ComponentName;
import android.content.Context;
import android.content.pm.PackageInstaller;
import android.os.Build;
import android.os.Process;
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

    /** Hidden in AppOpsManager (OPSTR_ACCESS_RESTRICTED_SETTINGS), but the name is what Android 13+ knows it by. */
    private static final String OP_RESTRICTED_SETTINGS = "android:access_restricted_settings";

    /** What a component list may hold before Hearth puts it in a shell command: package and class names only. */
    private static final Pattern SAFE_COMPONENTS = Pattern.compile("[A-Za-z0-9_.$/:]*");

    private SetupFixes() {
    }

    /**
     * Whether Android blocks Hearth's accessibility switches (they show greyed out), from the app-op Android sets on
     * an app installed from a downloaded file. Null when the app-op can't be read; Android 12 and older have none.
     */
    static Boolean restrictedSettingsDenied(Context context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return false;
        try {
            AppOpsManager ops = context.getSystemService(AppOpsManager.class);
            if (ops == null) return null;
            int mode = ops.unsafeCheckOpNoThrow(OP_RESTRICTED_SETTINGS, Process.myUid(), context.getPackageName());
            return mode == AppOpsManager.MODE_ERRORED || mode == AppOpsManager.MODE_IGNORED;
        } catch (RuntimeException e) {
            // An Android that doesn't know the op by that name
            Log.i(TAG, "Can't read the restricted settings app-op: " + e);
            return null;
        }
    }

    /**
     * {@link #restrictedSettingsDenied}, or when that can't be read, a guess from where Hearth was installed from
     * (a downloaded or local file is what Android restricts).
     */
    static boolean mayHaveRestrictedSettings(Context context) {
        Boolean denied = restrictedSettingsDenied(context);
        if (denied != null) return denied;
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return false;
        try {
            int source = context.getPackageManager().getInstallSourceInfo(context.getPackageName()).getPackageSource();
            return source == PackageInstaller.PACKAGE_SOURCE_LOCAL_FILE
                    || source == PackageInstaller.PACKAGE_SOURCE_DOWNLOADED_FILE;
        } catch (Exception e) {
            return false;
        }
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
        return log;
    }
}
