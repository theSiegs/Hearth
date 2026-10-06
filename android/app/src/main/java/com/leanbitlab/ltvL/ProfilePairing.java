package com.leanbitlab.ltvL;

import android.content.Context;
import android.content.SharedPreferences;

import org.json.JSONArray;

import java.util.ArrayList;
import java.util.Collection;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;

/**
 * Which profile to pick in a streaming app's "Who's watching?" screen for the active Hearth (Google TV) profile.
 * An override set by the user wins; otherwise the app profile whose name matches the Hearth profile's ("Alex"
 * matches "Alex" and "Alex Morgan"). Also remembers the names each app's picker showed, for the matching menu.
 */
final class ProfilePairing {
    static final String NETFLIX = "com.netflix.ninja";
    static final String DISNEY = "com.disney.disneyplus";
    static final String APPLE_TV = "com.apple.atve.androidtv.appletv";
    static final String MAX = "com.wbd.stream";
    static final String PARAMOUNT = "com.cbs.ott";

    private static final String PREFS = "profile_pairing";
    private static final String OVERRIDE_PREFIX = "override|";
    private static final String SEEN_PREFIX = "seen|";

    /** Placeholder pairs for testing on the test TV until the matching menu exists: {app, Hearth, app profile}. */
    private static final String[][] DEV_OVERRIDES = {
            {DISNEY, "Alex", "Grown Ups"},
            {MAX, "Jordan", "Josephine"},
    };

    private ProfilePairing() {}

    static boolean supports(String packageName) {
        return NETFLIX.equals(packageName) || DISNEY.equals(packageName) || APPLE_TV.equals(packageName)
                || MAX.equals(packageName) || PARAMOUNT.equals(packageName);
    }

    private static SharedPreferences prefs(Context context) {
        return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    /** The app profile the user paired with this Hearth profile, or null to match by name. */
    static String getOverride(Context context, String packageName, String hearthProfile) {
        String saved = prefs(context).getString(OVERRIDE_PREFIX + packageName + "|" + hearthProfile, null);
        if (saved != null) return saved.isEmpty() ? null : saved;
        for (String[] pair : DEV_OVERRIDES) {
            if (pair[0].equals(packageName) && pair[1].equalsIgnoreCase(hearthProfile)) return pair[2];
        }
        return null;
    }

    /** Pairs a Hearth profile with an app profile; null goes back to matching by name. */
    static void setOverride(Context context, String packageName, String hearthProfile, String appProfile) {
        SharedPreferences.Editor editor = prefs(context).edit();
        String key = OVERRIDE_PREFIX + packageName + "|" + hearthProfile;
        if (appProfile == null) editor.putString(key, ""); else editor.putString(key, appProfile);
        editor.apply();
    }

    /** Profile names this app's picker has shown, in picker order. */
    static List<String> getSeenNames(Context context, String packageName) {
        List<String> names = new ArrayList<>();
        try {
            JSONArray array = new JSONArray(prefs(context).getString(SEEN_PREFIX + packageName, "[]"));
            for (int i = 0; i < array.length(); i++) names.add(array.getString(i));
        } catch (Exception ignored) {
        }
        return names;
    }

    /** Remembers the picker's names (the full list when it is known, so removed profiles drop out). */
    static void rememberNames(Context context, String packageName, Collection<String> names, boolean complete) {
        Set<String> merged = new LinkedHashSet<>(names);
        if (!complete) merged.addAll(getSeenNames(context, packageName));
        prefs(context).edit().putString(SEEN_PREFIX + packageName, new JSONArray(merged).toString()).apply();
    }

    static Map<String, ?> dump(Context context) {
        return prefs(context).getAll();
    }

    /**
     * The picker name to choose among {@code names} for {@code hearthProfile}: the override when the picker has it,
     * otherwise the single best name match. Null when nothing matches or two names match equally well.
     */
    static String choose(Context context, String packageName, String hearthProfile, Collection<String> names) {
        String override = getOverride(context, packageName, hearthProfile);
        if (override != null) {
            for (String name : names) {
                if (normalize(name).equals(normalize(override))) return name;
            }
            return null;
        }
        String best = null;
        int bestScore = 0;
        boolean tie = false;
        for (String name : names) {
            int score = matchScore(hearthProfile, name);
            if (score > bestScore) {
                best = name;
                bestScore = score;
                tie = false;
            } else if (score == bestScore && score > 0) {
                tie = true;
            }
        }
        return tie ? null : best;
    }

    /** 3: same name; 2: same first name ("Alex" / "Alex Morgan"); 1: one name contains the other; 0: no match. */
    static int matchScore(String a, String b) {
        String x = normalize(a);
        String y = normalize(b);
        if (x.isEmpty() || y.isEmpty()) return 0;
        if (x.equals(y)) return 3;
        String xFirst = x.split(" ")[0];
        String yFirst = y.split(" ")[0];
        if (xFirst.equals(yFirst)) return 2;
        if ((" " + x + " ").contains(" " + y + " ") || (" " + y + " ").contains(" " + x + " ")) return 1;
        return 0;
    }

    static String normalize(String name) {
        if (name == null) return "";
        return name.toLowerCase(Locale.ROOT).replaceAll("[^\\p{L}\\p{N} ]", " ").trim().replaceAll("\\s+", " ");
    }
}
