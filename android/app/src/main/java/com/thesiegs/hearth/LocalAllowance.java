package com.thesiegs.hearth;

import android.content.Context;
import android.content.SharedPreferences;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;

import org.json.JSONException;
import org.json.JSONObject;

import java.time.Instant;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * A kids profile's allowance from Hearth's own rules (LocalRules), on a TV without Home Assistant. It gives the same
 * entry {@link HaAllowance#entryFor} reads from Home Assistant's document, so holds, the time's-up card, HearthTube's
 * minutes and the bedtime heads-up work the same either way. With Home Assistant set up, Home Assistant decides and
 * nothing here is used (its rules win outright; the TV keeps Home Assistant's last word while it is away).
 *
 * <p>The rules are kept per profile here; the household shares them across its TVs (Household), with each TV's
 * minutes for the kid, so a kid's minutes are the same on every TV.
 */
final class LocalAllowance {
    private static final String PREFS = "ltv_local_rules";
    /** Entries are worked out again at most this often (the minutes move by the minute). */
    private static final long CACHE_MS = 15_000;

    private static final Map<String, JSONObject> sCache = new HashMap<>();
    private static final Map<String, Long> sCachedAt = new HashMap<>();
    private static List<String> sInstalled;
    private static Map<String, String> sCategories;

    private LocalAllowance() {
    }

    /** Home Assistant has the say on this TV (set up, paired or the older entity): Hearth's own rules aren't used. */
    static boolean homeAssistantDecides(Context context) {
        return HaIntegration.isPaired(context) || HaConfig.isConfigured(context);
    }

    /** The rules set on this TV for the profile (null: none, no limits). */
    static JSONObject rules(Context context, String profileKey) {
        if (profileKey == null) return null;
        String json = prefs(context).getString(profileKey, null);
        if (json == null) return null;
        try {
            return new JSONObject(json);
        } catch (JSONException e) {
            return null;
        }
    }

    /** Sets (null: clears) the profile's rules; true when that changed them. */
    static synchronized boolean setRules(Context context, String profileKey, JSONObject rules) {
        if (profileKey == null) return false;
        String had = prefs(context).getString(profileKey, null);
        String value = rules != null && rules.length() > 0 ? rules.toString() : null;
        if (value == null ? had == null : value.equals(had)) return false;
        SharedPreferences.Editor editor = prefs(context).edit();
        if (value == null) {
            editor.remove(profileKey);
        } else {
            editor.putString(profileKey, value);
        }
        editor.apply();
        forget();
        return true;
    }

    /** Every profile with rules: profile key -> rules. */
    static Map<String, JSONObject> all(Context context) {
        Map<String, JSONObject> out = new HashMap<>();
        for (String key : prefs(context).getAll().keySet()) {
            JSONObject rules = rules(context, key);
            if (rules != null) out.put(key, rules);
        }
        return out;
    }

    /**
     * The profile's entry now, as HaAllowance's from Home Assistant's document; null when Home Assistant decides, the
     * profile is an adult's, or it has no rules.
     */
    static synchronized JSONObject entryFor(Context context, String profileKey, long now) {
        if (profileKey == null || homeAssistantDecides(context)
                || ProfileUsers.isAdults(context, ProfileUsers.serialOfKey(profileKey))) {
            return null;
        }
        Long at = sCachedAt.get(profileKey);
        if (at != null && now >= at && now - at < CACHE_MS) return sCache.get(profileKey);
        JSONObject entry = compute(context, profileKey, now);
        sCache.put(profileKey, entry);
        sCachedAt.put(profileKey, now);
        return entry;
    }

    /** Rules or usage changed: work the entries out again on the next read. */
    static synchronized void forget() {
        sCache.clear();
        sCachedAt.clear();
    }

    private static JSONObject compute(Context context, String profileKey, long now) {
        JSONObject rules = rules(context, profileKey);
        if (rules == null) return null;
        try {
            ZoneId zone = zoneOf(rules);
            Map<String, Long> usage = usageToday(context, profileKey, now);
            JSONObject person = LocalRules.document(rules, usage, installed(context), app -> categoryOf(context, app),
                    Instant.ofEpochMilli(now).atZone(zone));
            JSONObject profiles = HaAllowance.profilesFromDocument(
                    new JSONObject().put("profiles", new JSONObject().put(profileKey, person)));
            return profiles != null ? profiles.optJSONObject(profileKey) : null;
        } catch (JSONException e) {
            return null;
        }
    }

    /** What the kid used today: this TV's time in front (Hearth's own home left out) and the household's other TVs'. */
    static Map<String, Long> usageToday(Context context, String profileKey, long now) {
        Map<String, Long> usage = UsageToday.frontMs(context, profileKey, now);
        usage.remove(context.getPackageName());
        for (Map.Entry<String, Long> other : Household.otherUsage(context, profileKey, now).entrySet()) {
            usage.merge(other.getKey(), other.getValue(), Long::sum);
        }
        return usage;
    }

    private static ZoneId zoneOf(JSONObject rules) {
        String tz = rules.optString("tz", "");
        if (!tz.isEmpty()) {
            try {
                return ZoneId.of(tz);
            } catch (RuntimeException ignored) {
                // An unknown zone: the TV's own
            }
        }
        return ZoneId.systemDefault();
    }

    /** The apps a category group can take: this TV's (read once; a new app joins on the next start). */
    private static synchronized List<String> installed(Context context) {
        if (sInstalled == null) {
            List<String> out = new ArrayList<>();
            Map<String, String> categories = new HashMap<>();
            try {
                for (ApplicationInfo info : context.getPackageManager().getInstalledApplications(0)) {
                    out.add(info.packageName);
                    String category = categoryName(info.category);
                    if (category != null) categories.put(info.packageName, category);
                }
            } catch (RuntimeException ignored) {
                // Nothing listed: groups keep their own apps
            }
            sInstalled = out;
            sCategories = categories;
        }
        return sInstalled;
    }

    private static String categoryOf(Context context, String app) {
        installed(context);
        String known = sCategories.get(app);
        if (known != null || sInstalled.contains(app)) return known;
        try {
            return categoryName(context.getPackageManager().getApplicationInfo(app, 0).category);
        } catch (PackageManager.NameNotFoundException | RuntimeException e) {
            return null;
        }
    }

    /** Android's category as the rules name it (ApplicationInfo.category), null for none. */
    static String categoryName(int category) {
        switch (category) {
            case ApplicationInfo.CATEGORY_GAME:
                return "game";
            case ApplicationInfo.CATEGORY_AUDIO:
                return "audio";
            case ApplicationInfo.CATEGORY_VIDEO:
                return "video";
            case ApplicationInfo.CATEGORY_IMAGE:
                return "image";
            case ApplicationInfo.CATEGORY_SOCIAL:
                return "social";
            case ApplicationInfo.CATEGORY_NEWS:
                return "news";
            case ApplicationInfo.CATEGORY_MAPS:
                return "maps";
            case ApplicationInfo.CATEGORY_PRODUCTIVITY:
                return "productivity";
            default:
                return null;
        }
    }

    private static SharedPreferences prefs(Context context) {
        return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }
}
