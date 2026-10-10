package com.thesiegs.hearth;

import android.content.Context;
import android.content.SharedPreferences;

import org.json.JSONException;
import org.json.JSONObject;

import java.text.SimpleDateFormat;
import java.util.Calendar;
import java.util.Date;
import java.util.Iterator;
import java.util.Locale;

/**
 * How long each profile has used each app today, for Home Assistant (a shared allowance across the family's
 * devices, Family Link schedules): seconds an app was in front with the screen on, and seconds an app's media
 * session was playing. Counted for the TV's local day, kept across restarts, and started again at local midnight
 * (an interval running over midnight counts only its part since midnight). Cumulative, so a lost post loses nothing.
 */
final class UsageToday {
    private static final String PREFS = "ltv_usage_today";
    private static final String DAY_KEY = "day";
    private static final String DATA_KEY = "data";
    static final String FRONT = "apps";
    static final String PLAYING = "playing";

    private UsageToday() {
    }

    /** This profile had the app in front for ms, ending now. */
    static void addFront(Context context, String profile, String packageName, long ms, long now) {
        add(context, FRONT, profile, packageName, ms, now);
    }

    /** The app played for this profile for ms, ending now. */
    static void addPlaying(Context context, String profile, String packageName, long ms, long now) {
        add(context, PLAYING, profile, packageName, ms, now);
    }

    private static synchronized void add(Context context, String kind, String profile, String packageName, long ms,
            long now) {
        if (profile == null || packageName == null || ms <= 0) return;
        SharedPreferences prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        String today = day(now);
        JSONObject data = today.equals(prefs.getString(DAY_KEY, null)) ? parse(prefs.getString(DATA_KEY, null))
                : new JSONObject();
        try {
            add(data, kind, profile, packageName, sinceMidnight(ms, now));
        } catch (JSONException e) {
            return;
        }
        prefs.edit().putString(DAY_KEY, today).putString(DATA_KEY, data.toString()).apply();
    }

    /** Adds ms to the profile's count for the app (milliseconds, kept exact; reported in seconds). */
    static void add(JSONObject data, String kind, String profile, String packageName, long ms) throws JSONException {
        JSONObject counts = data.optJSONObject(profile);
        if (counts == null) data.put(profile, counts = new JSONObject());
        JSONObject apps = counts.optJSONObject(kind);
        if (apps == null) counts.put(kind, apps = new JSONObject());
        apps.put(packageName, apps.optLong(packageName) + ms);
    }

    /** The part of an interval of ms ending at now that falls on now's day. */
    static long sinceMidnight(long ms, long now) {
        Calendar midnight = Calendar.getInstance();
        midnight.setTimeInMillis(now);
        midnight.set(Calendar.HOUR_OF_DAY, 0);
        midnight.set(Calendar.MINUTE, 0);
        midnight.set(Calendar.SECOND, 0);
        midnight.set(Calendar.MILLISECOND, 0);
        return Math.max(0, Math.min(ms, now - midnight.getTimeInMillis()));
    }

    /** How long the app has played for this profile today, in milliseconds. */
    static synchronized long playingMs(Context context, String profile, String packageName, long now) {
        if (profile == null) return 0;
        SharedPreferences prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        if (!day(now).equals(prefs.getString(DAY_KEY, null))) return 0;
        JSONObject counts = parse(prefs.getString(DATA_KEY, null)).optJSONObject(profile);
        JSONObject playing = counts != null ? counts.optJSONObject(PLAYING) : null;
        return playing != null ? playing.optLong(packageName) : 0;
    }

    /** The TV's local date, "YYYY-MM-DD". */
    static String day(long time) {
        return new SimpleDateFormat("yyyy-MM-dd", Locale.ROOT).format(new Date(time));
    }

    /**
     * Today's counts, in seconds: {"<profile_id>": {"seconds": total in front, "apps": {pkg: s}, "playing": {pkg: s}}}.
     * Empty on a new day before anything counted.
     */
    static synchronized JSONObject today(Context context, long now) {
        SharedPreferences prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        if (!day(now).equals(prefs.getString(DAY_KEY, null))) return new JSONObject();
        return inSeconds(parse(prefs.getString(DATA_KEY, null)));
    }

    /** The stored milliseconds as whole seconds, with each profile's total time in front. */
    static JSONObject inSeconds(JSONObject data) {
        JSONObject out = new JSONObject();
        try {
            for (Iterator<String> profiles = data.keys(); profiles.hasNext(); ) {
                String profile = profiles.next();
                JSONObject counts = data.optJSONObject(profile);
                if (counts == null) continue;
                JSONObject entry = new JSONObject();
                long total = 0;
                for (String kind : new String[]{FRONT, PLAYING}) {
                    JSONObject apps = counts.optJSONObject(kind);
                    JSONObject seconds = new JSONObject();
                    if (apps != null) {
                        for (Iterator<String> pkgs = apps.keys(); pkgs.hasNext(); ) {
                            String pkg = pkgs.next();
                            long s = apps.optLong(pkg) / 1000;
                            seconds.put(pkg, s);
                            if (FRONT.equals(kind)) total += apps.optLong(pkg);
                        }
                    }
                    entry.put(kind, seconds);
                }
                entry.put("seconds", total / 1000);
                out.put(profile, entry);
            }
        } catch (JSONException ignored) {
        }
        return out;
    }

    private static JSONObject parse(String json) {
        if (json == null) return new JSONObject();
        try {
            return new JSONObject(json);
        } catch (JSONException e) {
            return new JSONObject();
        }
    }
}
