package com.thesiegs.hearth;

import android.content.Context;
import android.content.SharedPreferences;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

/**
 * Grown-ups' profiles share the owner's user (each is a Google account in it), and with it the apps and their
 * Continue Watching. Whose an entry is comes from who had its app open: each app keeps a short record of the
 * profiles that opened it (a line each time it changes hands), and an entry is the profile's that had its app when
 * the entry was last watched.
 */
final class AppWatchers {
    private static final String PREFS = "ltv_app_watchers";
    /** Hand-overs kept per app: enough to reach back past Continue Watching's oldest entries. */
    static final int MAX_RECORDS = 16;

    private AppWatchers() {
    }

    /** The active profile (its key) has this app open. */
    static void opened(Context context, String packageName, String profileKey) {
        if (packageName == null || profileKey == null) return;
        SharedPreferences prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        String before = prefs.getString(packageName, null);
        String after = record(before, System.currentTimeMillis(), profileKey);
        if (!after.equals(before)) prefs.edit().putString(packageName, after).apply();
    }

    /**
     * Which of this user's profiles (a key) had the app open at that time; null when none had yet, as far as Hearth
     * knows (then it's the user's first profile's, as before Hearth kept these).
     */
    static String watcherAt(Context context, String packageName, long time, long serial) {
        return watcherAt(history(context, packageName), time, serial);
    }

    /** The record with this profile opening the app at that time: a new line only when the app changes hands. */
    static String record(String history, long time, String profileKey) {
        List<String> lines = new ArrayList<>();
        if (history != null && !history.isEmpty()) lines.addAll(Arrays.asList(history.split("\n")));
        if (!lines.isEmpty() && profileKey.equals(keyOf(lines.get(lines.size() - 1)))) return history;
        lines.add(time + " " + profileKey);
        while (lines.size() > MAX_RECORDS) lines.remove(0);
        return String.join("\n", lines);
    }

    /** The latest of this user's profiles to open the app at or before that time, from a record; or null. */
    static String watcherAt(String history, long time, long serial) {
        if (history == null || history.isEmpty() || time <= 0) return null;
        String watcher = null;
        long latest = Long.MIN_VALUE;
        for (String line : history.split("\n")) {
            int space = line.indexOf(' ');
            if (space <= 0) continue;
            long at;
            try {
                at = Long.parseLong(line.substring(0, space));
            } catch (NumberFormatException e) {
                continue;
            }
            String key = line.substring(space + 1);
            // Not another user's profile (a kid's apps have lists of their own)
            if (at <= time && at >= latest && ProfileUsers.serialOfKey(key) == serial) {
                latest = at;
                watcher = key;
            }
        }
        return watcher;
    }

    /** The profile (key) that has the app now: the last one that opened it; null when none has, as far as Hearth knows. */
    static String holder(Context context, String packageName) {
        String history = history(context, packageName);
        if (history == null || history.isEmpty()) return null;
        String[] lines = history.split("\n");
        return keyOf(lines[lines.length - 1]);
    }

    /** Whether this profile opened the app after that time. */
    static boolean openedSince(Context context, String packageName, String profileKey, long since) {
        return openedSince(history(context, packageName), profileKey, since);
    }

    static boolean openedSince(String history, String profileKey, long since) {
        if (history == null || history.isEmpty()) return false;
        for (String line : history.split("\n")) {
            int space = line.indexOf(' ');
            if (space <= 0 || !line.substring(space + 1).equals(profileKey)) continue;
            try {
                if (Long.parseLong(line.substring(0, space)) > since) return true;
            } catch (NumberFormatException ignored) {
            }
        }
        return false;
    }

    /** Whether one of this user's profiles opened the app (it changed hands) after one time and up to another. */
    static boolean changedHands(String history, long after, long until, long serial) {
        if (history == null || history.isEmpty() || until <= after) return false;
        for (String line : history.split("\n")) {
            int space = line.indexOf(' ');
            if (space <= 0 || ProfileUsers.serialOfKey(line.substring(space + 1)) != serial) continue;
            try {
                long at = Long.parseLong(line.substring(0, space));
                if (at > after && at <= until) return true;
            } catch (NumberFormatException ignored) {
            }
        }
        return false;
    }

    /** The app's record (see record), or null when no profile has opened it as far as Hearth knows. */
    static String history(Context context, String packageName) {
        if (packageName == null) return null;
        return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(packageName, null);
    }

    private static String keyOf(String line) {
        int space = line.indexOf(' ');
        return space < 0 ? null : line.substring(space + 1);
    }
}
