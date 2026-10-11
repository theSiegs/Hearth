package com.thesiegs.hearth;

import android.content.Context;
import android.content.pm.PackageManager;
import android.util.Log;

import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * The grown-ups' profiles share one copy of each streaming app (they're accounts in the same Android user), and an
 * app that's still running opens straight into the app profile it last had, without its "Who's watching?" screen.
 * So when the grown-ups' profile changes, the paired apps another profile had are stopped (over Hearth's own adb, only
 * when the TV already trusts its key: never an "Allow debugging?" prompt), and the next opening shows the picker,
 * where Profile Pairing picks this profile's.
 */
final class GrownUpsApps {
    private static final String TAG = "HearthPairing";
    private static final int QUIET_TIMEOUT_MS = 5_000;
    private static final ExecutorService EXECUTOR = Executors.newSingleThreadExecutor();

    private GrownUpsApps() {
    }

    /** The paired apps to stop for {@code profileKey}: installed, and last opened by another profile of its user. */
    static List<String> toStop(Context context, String profileKey) {
        List<String> out = new ArrayList<>();
        long serial = ProfileUsers.serialOfKey(profileKey);
        PackageManager pm = context.getPackageManager();
        for (String pkg : ProfilePairing.APPS) {
            String holder = AppWatchers.holder(context, pkg);
            if (!stops(holder, profileKey, serial)) continue;
            if (!ProfilePairing.isAppEnabled(context, pkg)) continue;
            try {
                pm.getPackageInfo(pkg, 0);
                out.add(pkg);
            } catch (PackageManager.NameNotFoundException ignored) {
                // Not installed
            }
        }
        return out;
    }

    /** Whether an app another profile ({@code holder}) last opened is stopped for {@code profileKey}. */
    static boolean stops(String holder, String profileKey, long serial) {
        return holder != null && profileKey != null && !holder.equals(profileKey)
                && ProfileUsers.serialOfKey(holder) == serial;
    }

    /** The grown-ups' profile is now {@code profileKey}: stops the apps another one had, in the background. */
    static void onProfileChanged(Context context, String profileKey) {
        Context app = context.getApplicationContext();
        EXECUTOR.execute(() -> {
            List<String> apps = toStop(app, profileKey);
            if (apps.isEmpty()) return;
            if (!SetupFixes.isAdbEnabled(app) || !SelfAdb.isTrusted(app)) {
                Log.i(TAG, "Not stopping " + apps + " for " + profileKey + ": Hearth's adb isn't set up");
                return;
            }
            try (SelfAdb shell = SelfAdb.open(app, QUIET_TIMEOUT_MS)) {
                for (String pkg : apps) shell.run("am force-stop " + pkg);
                Log.i(TAG, "Stopped " + apps + " so they ask who's watching (" + profileKey + ")");
            } catch (Exception e) {
                Log.i(TAG, "Couldn't stop " + apps + ": " + e);
            }
        });
    }
}
