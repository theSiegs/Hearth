package com.leanbitlab.ltvL;

import android.content.Context;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.os.Build;

/** What Hearth knows about the companion apps it installs and updates (see companion_apps_page.dart). */
final class CompanionApps {
    static final String HEARTHTUBE = "com.thesiegs.hearthtube";
    /** Dart's "companion_auto_update" setting. */
    private static final String AUTO_UPDATE_KEY = FlutterPrefs.key("companion_auto_update");

    private CompanionApps() {
    }

    /**
     * Hearth installed the app (it's the installer of record), so Android lets Hearth update it without asking.
     * An app installed some other way (adb, Downloader) asks once, the first time Hearth updates it.
     */
    static boolean installedByHearth(Context context, String packageName) {
        if (packageName == null) return false;
        try {
            PackageManager pm = context.getPackageManager();
            String installer = Build.VERSION.SDK_INT >= Build.VERSION_CODES.R
                    ? pm.getInstallSourceInfo(packageName).getInstallingPackageName()
                    : pm.getInstallerPackageName(packageName);
            return context.getPackageName().equals(installer);
        } catch (Exception e) {
            return false;
        }
    }

    /** Automatic companion updates are on (by default exactly when Hearth installed HearthTube). */
    static boolean autoUpdate(Context context) {
        SharedPreferences prefs = FlutterPrefs.get(context);
        return prefs.contains(AUTO_UPDATE_KEY) ? prefs.getBoolean(AUTO_UPDATE_KEY, false)
                : installedByHearth(context, HEARTHTUBE);
    }

    /**
     * Hearth keeps HearthTube up to date: automatic updates are on and Hearth can update it without a prompt.
     * HearthTube's own updater then steps aside (provider column updates_hearthtube).
     */
    static boolean updatesHearthTube(Context context) {
        return autoUpdate(context) && installedByHearth(context, HEARTHTUBE);
    }
}
