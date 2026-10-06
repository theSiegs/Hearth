package com.leanbitlab.ltvL;

import android.content.Context;
import android.content.SharedPreferences;

import org.json.JSONArray;

import java.util.ArrayList;
import java.util.Collection;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;

/**
 * Which profile to pick in a streaming app's "Who's watching?" screen for the active Hearth (Google TV) profile.
 * For each app and Hearth profile the choice (set in Settings → Profile Pairing) is one of: match by name (the
 * default: "Alex" matches "Alex" and "Alex Morgan"), a specific app profile, or always show the app's picker.
 * Also remembers the names each app's picker showed and the Hearth profiles seen, for that menu.
 */
final class ProfilePairing {
    static final String NETFLIX = "com.netflix.ninja";
    static final String DISNEY = "com.disney.disneyplus";
    static final String APPLE_TV = "com.apple.atve.androidtv.appletv";
    static final String MAX = "com.wbd.stream";
    static final String PARAMOUNT = "com.cbs.ott";
    static final String[] APPS = {NETFLIX, DISNEY, APPLE_TV, MAX, PARAMOUNT};

    static final String MODE_AUTO = "auto";
    static final String MODE_PROFILE = "profile";
    static final String MODE_PICKER = "picker";

    private static final String PREFS = "profile_pairing";
    private static final String CHOICE_PREFIX = "override|";
    private static final String SEEN_PREFIX = "seen|";
    private static final String ANNOUNCED_PREFIX = "announced|";
    private static final String HEARTH_PROFILES = "hearth_profiles";
    private static final String KIDS_PREFIX = "kids|";
    /** Stored for "always show the picker"; any other stored value is an app profile name. */
    private static final String PICKER_VALUE = "\u0000picker";

    private ProfilePairing() {}

    /** The app's usual name, for apps that aren't installed. */
    static String displayName(String packageName) {
        switch (packageName) {
            case NETFLIX: return "Netflix";
            case DISNEY: return "Disney+";
            case APPLE_TV: return "Apple TV";
            case MAX: return "HBO Max";
            case PARAMOUNT: return "Paramount+";
            default: return packageName;
        }
    }

    static boolean supports(String packageName) {
        for (String app : APPS) {
            if (app.equals(packageName)) return true;
        }
        return false;
    }

    private static SharedPreferences prefs(Context context) {
        return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    private static String choiceKey(String packageName, String hearthProfile) {
        return CHOICE_PREFIX + packageName + "|" + hearthProfile;
    }

    private static final String DISABLED_PREFIX = "disabled|";

    /** Whether Profile Pairing handles this app at all (on unless turned off in Settings → Profile Pairing). */
    static boolean isAppEnabled(Context context, String packageName) {
        return !prefs(context).getBoolean(DISABLED_PREFIX + packageName, false);
    }

    static void setAppEnabled(Context context, String packageName, boolean enabled) {
        prefs(context).edit().putBoolean(DISABLED_PREFIX + packageName, !enabled).apply();
    }

    /** MODE_AUTO, MODE_PROFILE or MODE_PICKER. */
    static String getMode(Context context, String packageName, String hearthProfile) {
        String saved = prefs(context).getString(choiceKey(packageName, hearthProfile), null);
        if (saved == null || saved.isEmpty()) return MODE_AUTO;
        return PICKER_VALUE.equals(saved) ? MODE_PICKER : MODE_PROFILE;
    }

    /** The app profile chosen for this Hearth profile, or null unless the mode is MODE_PROFILE. */
    static String getChosenProfile(Context context, String packageName, String hearthProfile) {
        return MODE_PROFILE.equals(getMode(context, packageName, hearthProfile))
                ? prefs(context).getString(choiceKey(packageName, hearthProfile), null) : null;
    }

    static void setChoice(Context context, String packageName, String hearthProfile, String mode, String appProfile) {
        SharedPreferences.Editor editor = prefs(context).edit();
        String key = choiceKey(packageName, hearthProfile);
        if (MODE_PICKER.equals(mode)) {
            editor.putString(key, PICKER_VALUE);
        } else if (MODE_PROFILE.equals(mode) && appProfile != null && !appProfile.isEmpty()) {
            editor.putString(key, appProfile);
        } else {
            editor.remove(key);
        }
        // A choice made in the menu needs no "Hearth matched…" notice.
        editor.putBoolean(ANNOUNCED_PREFIX + packageName + "|" + hearthProfile, true);
        editor.apply();
    }

    /** Whether Hearth already told the user about its name match for this app and profile; marks it told. */
    static boolean announceOnce(Context context, String packageName, String hearthProfile) {
        String key = ANNOUNCED_PREFIX + packageName + "|" + hearthProfile;
        if (prefs(context).getBoolean(key, false)) return false;
        prefs(context).edit().putBoolean(key, true).apply();
        return true;
    }

    /** Profile names this app's picker has shown, in picker order. */
    static List<String> getSeenNames(Context context, String packageName) {
        return readList(prefs(context).getString(SEEN_PREFIX + packageName, "[]"));
    }

    /** Remembers the picker's names (the full list when it is known, so removed profiles drop out). */
    static void rememberNames(Context context, String packageName, Collection<String> names, boolean complete) {
        Set<String> merged = new LinkedHashSet<>(names);
        if (!complete) merged.addAll(getSeenNames(context, packageName));
        prefs(context).edit().putString(SEEN_PREFIX + packageName, new JSONArray(merged).toString()).apply();
    }

    /** Remembers a Google TV profile Hearth has seen, and whether it is a kids profile. */
    static void rememberHearthProfile(Context context, String name, Boolean kids) {
        if (name == null || name.isEmpty()) return;
        List<String> known = getHearthProfiles(context);
        SharedPreferences.Editor editor = prefs(context).edit();
        if (!known.contains(name)) {
            known.add(name);
            editor.putString(HEARTH_PROFILES, new JSONArray(known).toString());
        }
        if (kids != null) editor.putBoolean(KIDS_PREFIX + name, kids);
        editor.apply();
    }

    static List<String> getHearthProfiles(Context context) {
        return readList(prefs(context).getString(HEARTH_PROFILES, "[]"));
    }

    static boolean isKids(Context context, String hearthProfile) {
        return prefs(context).getBoolean(KIDS_PREFIX + hearthProfile, false);
    }

    private static List<String> readList(String json) {
        List<String> names = new ArrayList<>();
        try {
            JSONArray array = new JSONArray(json);
            for (int i = 0; i < array.length(); i++) names.add(array.getString(i));
        } catch (Exception ignored) {
        }
        return names;
    }

    /**
     * The picker name to choose among {@code names} for {@code hearthProfile}: the chosen profile when the picker has
     * it, otherwise (match by name) the single best match. Null when the picker should be left to the user.
     */
    static String choose(Context context, String packageName, String hearthProfile, Collection<String> names) {
        String mode = getMode(context, packageName, hearthProfile);
        if (MODE_PICKER.equals(mode)) return null;
        if (MODE_PROFILE.equals(mode)) {
            String chosen = getChosenProfile(context, packageName, hearthProfile);
            for (String name : names) {
                if (normalize(name).equals(normalize(chosen))) return name;
            }
            return null;
        }
        return bestMatch(hearthProfile, names);
    }

    /** The single best name match, or null when nothing matches or two names match equally well. */
    static String bestMatch(String hearthProfile, Collection<String> names) {
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

    /**
     * How well two profile names match: 5 same name; 4 same first name ("Alex" / "Alex Morgan"); 3 one name
     * contains the other; 2 one first name starts with the other, a nickname ("Sam" / "Samantha", "Jo" /
     * "Josephine"); 1 same first three letters ("Tony" / "Riley"); 0 no match.
     */
    static int matchScore(String a, String b) {
        String x = normalize(a);
        String y = normalize(b);
        if (x.isEmpty() || y.isEmpty()) return 0;
        if (x.equals(y)) return 5;
        String xFirst = x.split(" ")[0];
        String yFirst = y.split(" ")[0];
        if (xFirst.equals(yFirst)) return 4;
        if ((" " + x + " ").contains(" " + y + " ") || (" " + y + " ").contains(" " + x + " ")) return 3;
        String shorter = xFirst.length() <= yFirst.length() ? xFirst : yFirst;
        String longer = shorter == xFirst ? yFirst : xFirst;
        if (shorter.length() >= 3 && longer.startsWith(shorter)) return 2;
        if (shorter.length() >= 3 && longer.startsWith(shorter.substring(0, 3))) return 1;
        return 0;
    }

    static String normalize(String name) {
        if (name == null) return "";
        return name.toLowerCase(Locale.ROOT).replaceAll("[^\\p{L}\\p{N} ]", " ").trim().replaceAll("\\s+", " ");
    }
}
