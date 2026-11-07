package com.thesiegs.hearth;

import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;

import java.util.Collections;
import java.util.List;
import java.util.Map;
import java.util.regex.Pattern;

/**
 * Another app (HearthTube's "Ask for more time") asks for Hearth's time's up card: {@link #ACTION} with the held app
 * ({@link #EXTRA_PACKAGE}) and, optionally, a Hearth group id ({@link #EXTRA_GROUP}). Hearth's home comes to the front
 * and, when the active kids profile really is out of time for it, shows the card it shows for an app held on the home
 * (with "ask for more"); otherwise only the home. In a kids profile's own user (where HearthTube runs) the agent there
 * passes it to Hearth in the owner's user. See docs/time-up-intent.md.
 */
final class TimeUpRequest {
    private static final String TAG = "HearthTimeUp";

    static final String ACTION = "com.thesiegs.hearth.action.TIME_UP";
    static final String EXTRA_PACKAGE = "package";
    static final String EXTRA_GROUP = "group";

    private static final Pattern PACKAGE = Pattern.compile("^[A-Za-z][A-Za-z0-9_]*(\\.[A-Za-z0-9_]+)+$");
    // As the Hearth integration's group ids (panel.py _ID)
    private static final Pattern GROUP = Pattern.compile("^[a-z0-9_]{1,64}$");

    private static final long CARD_RETRY_MS = 300;
    private static final int CARD_TRIES = 10;

    private TimeUpRequest() {
    }

    /** The package extra when it's a package name at all; null otherwise. */
    static String cleanPackage(String value) {
        if (value == null) return null;
        String trimmed = value.trim();
        return trimmed.length() <= 255 && PACKAGE.matcher(trimmed).matches() ? trimmed : null;
    }

    /** The group extra when it's a group id at all; null otherwise. */
    static String cleanGroup(String value) {
        if (value == null) return null;
        String trimmed = value.trim();
        return GROUP.matcher(trimmed).matches() ? trimmed : null;
    }

    /**
     * What the card names: the group out of time (by name), "" while a family pause or a lock holds everything, or
     * null when nothing holds the app (then only the home opens). A group id given and out of time today is named;
     * an unknown one, or one with time left, is ignored and the app's own hold decides.
     *
     * @param timeUp the profile's groups out of time today ({id, name}, HaLocks.timeUpGroups)
     * @param heldForPackage what holds the package ({@link Allowance#heldApps}: a group name, "" for all, null: nothing)
     */
    static String cardGroup(String groupId, List<Map<String, Object>> timeUp, String heldForPackage) {
        if (Allowance.HELD_ALL.equals(heldForPackage)) return Allowance.HELD_ALL;
        if (groupId != null && timeUp != null) {
            for (Map<String, Object> group : timeUp) {
                if (groupId.equals(group.get("id")) && group.get("name") instanceof String) return (String) group.get("name");
            }
        }
        return heldForPackage;
    }

    /** Whether the package is installed in this user. */
    static boolean installed(Context context, String packageName) {
        try {
            context.getPackageManager().getPackageInfo(packageName, 0);
            return true;
        } catch (PackageManager.NameNotFoundException e) {
            return false;
        }
    }

    /**
     * In the owner's user (main thread): Hearth's home to the front, and the card when the active profile is out of
     * time for the app. [packageName]: an installed app (null: just the home); [groupId]: a clean group id or null.
     */
    static void show(Context context, String packageName, String groupId) {
        Context app = context.getApplicationContext();
        String card = null;
        if (packageName != null) {
            String key = LauncherAccessibilityService.getActiveProfileKey(app);
            String held = Allowance.heldApps(app, Collections.singletonList(packageName)).get(packageName);
            card = cardGroup(groupId, HaLocks.timeUpGroups(HaAllowance.entryFor(app, key, System.currentTimeMillis())), held);
        }
        Log.i(TAG, "Asked for the time's up card for " + packageName + ": " + (card == null ? "nothing held, the home only"
                : card.isEmpty() ? "everything held" : "a group out of time"));
        Intent home = new Intent(app, MainActivity.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
        try {
            app.startActivity(home);
        } catch (RuntimeException e) {
            Log.w(TAG, "Couldn't bring the home to the front: " + e.getClass().getSimpleName());
        }
        if (card == null) return;
        String group = card.isEmpty() ? null : card;
        Handler handler = new Handler(Looper.getMainLooper());
        // The home may be starting (its Flutter side not listening yet): try again for a few seconds
        Runnable[] tell = new Runnable[1];
        int[] tries = {0};
        tell[0] = () -> {
            if (MainActivity.notifyTimeUp(group)) return;
            if (++tries[0] < CARD_TRIES) handler.postDelayed(tell[0], CARD_RETRY_MS);
        };
        handler.postDelayed(tell[0], CARD_RETRY_MS);
    }
}
