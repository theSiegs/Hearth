package com.thesiegs.hearth;

import android.content.Context;
import android.content.SharedPreferences;
import android.os.SystemClock;
import android.util.Log;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.util.Iterator;

/**
 * Each profile's allowance as Home Assistant works it out (a YouTube time pool shared with the family's other
 * devices, Family Link schedules), for HearthTube to enforce: read from one entity, {@link #ENTITY}, whose attribute
 * "profiles" (or else its state, as JSON) maps a profile_id (the key Hearth sends Home Assistant, "user:11") to
 * {"youtube_minutes_left": int or null, "schedule_locked": bool, "message": optional text}. Read with the Home Assistant panel's address and token,
 * every minute or so and at once when the profile changes; the last good read is kept for the day (a new day forgets
 * it), and when it was read goes with it, so HearthTube can tell how fresh it is and decide what to do without one.
 *
 * A TV paired with the Hearth integration (see {@link HaIntegration}) doesn't read the entity: each status post's
 * answer carries every profile's groups and minutes left, and the YouTube minutes are the fewest left in any group
 * holding HearthTube ({@link #fromDocument}).
 */
final class HaAllowance {
    private static final String TAG = "HearthAllowance";
    static final String ENTITY = "sensor.hearth_allowance";
    private static final String PREFS = "ltv_ha_allowance";
    private static final String DAY_KEY = "day";
    private static final String PROFILES_KEY = "profiles";
    private static final String CHECKED_KEY = "checked_at";
    /** How often it's read. */
    static final long READ_EVERY_MS = 60_000;
    /** After a failed read (no entity yet, Home Assistant away), the next one waits this long. */
    private static final long RETRY_AFTER_FAILURE_MS = 10 * 60_000;

    private static long sNextReadAt;

    private HaAllowance() {
    }

    /** One profile's allowance: what Home Assistant last said today, and when (null: nothing today). */
    static final class Values {
        final Integer youtubeMinutesLeft;
        final boolean scheduleLocked;
        final String message;
        final Long checkedAt;

        Values(Integer youtubeMinutesLeft, boolean scheduleLocked, String message, Long checkedAt) {
            this.youtubeMinutesLeft = youtubeMinutesLeft;
            this.scheduleLocked = scheduleLocked;
            this.message = message;
            this.checkedAt = checkedAt;
        }
    }

    /** Whether a read is due (main thread). */
    static synchronized boolean due() {
        return SystemClock.elapsedRealtime() >= sNextReadAt;
    }

    /** The next read happens at the next chance (a profile change). */
    static synchronized void readSoon() {
        sNextReadAt = 0;
    }

    /** Reads the entity (blocking: off the main thread). Returns whether it was read. */
    static boolean read(Context context) {
        synchronized (HaAllowance.class) {
            sNextReadAt = SystemClock.elapsedRealtime() + RETRY_AFTER_FAILURE_MS;
        }
        if (!HaConfig.isConfigured(context) || HaIntegration.isPaired(context)) return false;
        JSONObject state = HaApi.state(context, ENTITY);
        JSONObject profiles = profilesOf(state);
        if (profiles == null) {
            // Unreadable, or not a profiles map (unknown, unavailable): what was read today still counts (fail-open)
            Log.i(TAG, "No allowance from Home Assistant (" + ENTITY + (state == null ? " unreadable)" : " has no profiles)"));
            return false;
        }
        synchronized (HaAllowance.class) {
            sNextReadAt = SystemClock.elapsedRealtime() + READ_EVERY_MS;
        }
        long now = System.currentTimeMillis();
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                .putString(DAY_KEY, UsageToday.day(now))
                .putString(PROFILES_KEY, profiles.toString())
                .putLong(CHECKED_KEY, now)
                .apply();
        // Even the same values: the read time changed, and HearthTube judges freshness by it
        return true;
    }

    /** Keeps the profiles from the integration's answer (its state document) as today's allowance. */
    static void fromDocument(Context context, JSONObject state) {
        JSONObject profiles = profilesFromDocument(state);
        if (profiles == null) return;
        long now = System.currentTimeMillis();
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                .putString(DAY_KEY, UsageToday.day(now))
                .putString(PROFILES_KEY, profiles.toString())
                .putLong(CHECKED_KEY, now)
                .apply();
    }

    /**
     * The allowance map from the integration's state document, {"profiles": {"user:10": {"groups": [{"id",
     * "minutes_left", "apps": [...]}]}}}: per profile, the fewest minutes left in a group holding HearthTube (none:
     * no limit). Null when it isn't such a document.
     */
    static JSONObject profilesFromDocument(JSONObject state) {
        JSONObject documents = state != null ? state.optJSONObject("profiles") : null;
        if (documents == null) return null;
        JSONObject profiles = new JSONObject();
        try {
            for (Iterator<String> keys = documents.keys(); keys.hasNext(); ) {
                String profileId = keys.next();
                JSONObject person = documents.optJSONObject(profileId);
                JSONArray groups = person != null ? person.optJSONArray("groups") : null;
                Integer least = null;
                for (int i = 0; groups != null && i < groups.length(); i++) {
                    JSONObject group = groups.optJSONObject(i);
                    if (group == null || group.isNull("minutes_left") || !holdsHearthTube(group.optJSONArray("apps"))) {
                        continue;
                    }
                    int left = Math.max(0, group.optInt("minutes_left", 0));
                    least = least == null ? left : Math.min(least, left);
                }
                JSONObject entry = new JSONObject();
                entry.put("youtube_minutes_left", least == null ? JSONObject.NULL : least);
                entry.put("schedule_locked", person != null && person.optBoolean("locked", false));
                profiles.put(profileId, entry);
            }
        } catch (JSONException e) {
            return null;
        }
        return profiles;
    }

    private static boolean holdsHearthTube(JSONArray apps) {
        for (int i = 0; apps != null && i < apps.length(); i++) {
            String app = apps.optString(i);
            if (CompanionApps.HEARTHTUBE.equals(app) || "com.thesiegs.hearthtube.mobile".equals(app)) return true;
        }
        return false;
    }

    /**
     * The profiles map from the entity: its "profiles" attribute, else its state as JSON (a template helper made in
     * Home Assistant's UI can't have attributes, and a state is at most 255 characters, enough for a few profiles).
     * "{}" is a map with no limits; anything else (unknown, unavailable, not JSON) is null.
     */
    static JSONObject profilesOf(JSONObject state) {
        if (state == null) return null;
        JSONObject attributes = state.optJSONObject("attributes");
        JSONObject profiles = attributes != null ? attributes.optJSONObject("profiles") : null;
        if (profiles != null) return profiles;
        String value = state.optString("state", "").trim();
        if (!value.startsWith("{")) return null;
        try {
            return new JSONObject(value);
        } catch (JSONException e) {
            return null;
        }
    }

    /** This profile's allowance as last read today; values null when Home Assistant has said nothing today. */
    static Values forProfile(Context context, String profileKey, long now) {
        SharedPreferences prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        if (profileKey == null || !UsageToday.day(now).equals(prefs.getString(DAY_KEY, null))) {
            return new Values(null, false, null, null);
        }
        Long checkedAt = prefs.contains(CHECKED_KEY) ? prefs.getLong(CHECKED_KEY, 0) : null;
        try {
            JSONObject profiles = new JSONObject(prefs.getString(PROFILES_KEY, "{}"));
            return valuesOf(profiles.optJSONObject(profileKey), checkedAt);
        } catch (JSONException e) {
            return new Values(null, false, null, checkedAt);
        }
    }

    /** A profile's entry in the entity's "profiles" (none: no limit, not locked). */
    static Values valuesOf(JSONObject entry, Long checkedAt) {
        if (entry == null) return new Values(null, false, null, checkedAt);
        Integer minutes = entry.isNull("youtube_minutes_left") ? null
                : Math.max(0, (int) Math.floor(entry.optDouble("youtube_minutes_left", 0)));
        String message = entry.isNull("message") ? null : entry.optString("message", null);
        return new Values(minutes, entry.optBoolean("schedule_locked", false),
                message != null && !message.trim().isEmpty() ? message.trim() : null, checkedAt);
    }
}
