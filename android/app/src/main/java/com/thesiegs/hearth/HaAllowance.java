package com.thesiegs.hearth;

import android.content.Context;
import android.content.SharedPreferences;
import android.util.Log;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.util.Arrays;
import java.util.Collections;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Iterator;
import java.util.Map;
import java.util.Set;

/**
 * Each profile's allowance as the Hearth integration works it out, for HearthTube and Hearth's holds to enforce. A TV
 * paired with the integration (see {@link HaIntegration}) gets it in each status post's answer: every profile's groups
 * and minutes left, and the YouTube minutes are the fewest left in any group holding HearthTube ({@link #fromDocument}).
 * Its other groups whose time is up today name the apps Hearth holds for the profile (Allowance.timeUpGroup): every
 * app when it's All screen time. The last answer is kept for the day (a new day forgets it), with when it came, so
 * HearthTube can tell how fresh it is. Without the integration, Hearth's own rules give the same (LocalAllowance).
 */
final class HaAllowance {
    private static final String TAG = "HearthAllowance";
    private static final String PREFS = "ltv_ha_allowance";
    private static final String DAY_KEY = "day";
    private static final String PROFILES_KEY = "profiles";
    private static final String CHECKED_KEY = "checked_at";
    /** This TV's profile keys and the Home Assistant person each is mapped to, from the integration's last answer. */
    private static final String PEOPLE_KEY = "people";

    /**
     * What {@link Values#timeUpGroup} says while a family pause holds every app: not a group's name (no name has a
     * NUL in it), so the kid is told about the pause instead.
     */
    static final String PAUSE_HOLD = "\u0000pause";
    /** The state document's fields about locks, a pause and a request for more time, kept as they came (HaLocks). */
    static final String LOCKS_KEY = "locks";
    /** The groups with no time left today, [{id, name}], kept for asking for more (HaLocks). */
    static final String TIME_UP_GROUPS_KEY = "time_up_groups";
    private static final String[] LOCK_FIELDS = {"pause", "lock", "next_lock", "request"};

    /** The integration's group of every app: its time up holds every app (but these). */
    static final String ALL_GROUP = "all";
    /**
     * Never held for a group's time: Hearth, HearthTube (it holds YouTube time itself), Settings, the store, the
     * assistant and Google TV's own homes and screens.
     */
    static final Set<String> NEVER_HELD = Collections.unmodifiableSet(new HashSet<>(Arrays.asList(
            "com.thesiegs.hearth", CompanionApps.HEARTHTUBE, "com.thesiegs.hearthtube.mobile",
            "com.android.tv.settings", "com.android.settings", "com.android.vending", "com.google.android.katniss",
            "com.google.android.apps.tv.launcherx", "com.google.android.tvlauncher",
            "com.google.android.leanbacklauncher", "com.google.android.tvrecommendations", "com.android.systemui",
            "android")));

    private HaAllowance() {
    }

    /** One profile's allowance: what Home Assistant last said today, and when (null: nothing today). */
    static final class Values {
        final Integer youtubeMinutesLeft;
        final boolean scheduleLocked;
        final String message;
        final Long checkedAt;
        /** Apps whose group's time is up today, each with that group's name (never null). */
        final Map<String, String> outOfTime;
        /** All screen time's name when its time is up today (every app is held), else null. */
        final String allOutOfTime;
        /** The apps All screen time never holds: a group outside it (music, say). */
        final Set<String> allExcept;
        /**
         * Until when a family pause (hearth.pause) holds every app, in epoch ms (Long.MAX_VALUE: until Home Assistant
         * says it's over); null when there's none.
         */
        final Long pausedUntil;

        Values(Integer youtubeMinutesLeft, boolean scheduleLocked, String message, Long checkedAt) {
            this(youtubeMinutesLeft, scheduleLocked, message, checkedAt, Collections.emptyMap(), null,
                    Collections.emptySet());
        }

        Values(Integer youtubeMinutesLeft, boolean scheduleLocked, String message, Long checkedAt,
                Map<String, String> outOfTime, String allOutOfTime) {
            this(youtubeMinutesLeft, scheduleLocked, message, checkedAt, outOfTime, allOutOfTime,
                    Collections.emptySet());
        }

        Values(Integer youtubeMinutesLeft, boolean scheduleLocked, String message, Long checkedAt,
                Map<String, String> outOfTime, String allOutOfTime, Set<String> allExcept) {
            this(youtubeMinutesLeft, scheduleLocked, message, checkedAt, outOfTime, allOutOfTime, allExcept, null);
        }

        Values(Integer youtubeMinutesLeft, boolean scheduleLocked, String message, Long checkedAt,
                Map<String, String> outOfTime, String allOutOfTime, Set<String> allExcept, Long pausedUntil) {
            this.youtubeMinutesLeft = youtubeMinutesLeft;
            this.scheduleLocked = scheduleLocked;
            this.message = message;
            this.checkedAt = checkedAt;
            this.outOfTime = outOfTime;
            this.allOutOfTime = allOutOfTime;
            this.allExcept = allExcept;
            this.pausedUntil = pausedUntil;
        }

        /** The group whose time is up today for this app (null: none, it may open). */
        String timeUpGroup(String packageName) {
            return timeUpGroup(packageName, System.currentTimeMillis());
        }

        /**
         * The group whose time is up for this app at [now] (null: none, it may open), or {@link #PAUSE_HOLD} while a
         * family pause holds every app.
         */
        String timeUpGroup(String packageName, long now) {
            if (packageName == null || NEVER_HELD.contains(packageName)) return null;
            if (pausedUntil != null && now < pausedUntil) return PAUSE_HOLD;
            String group = outOfTime.get(packageName);
            if (group != null) return group;
            return allExcept.contains(packageName) ? null : allOutOfTime;
        }
    }

    /**
     * Who each of this TV's profiles is in Home Assistant, from its state document: its "people" map (every mapped
     * profile, {"user:10": "person.alex"}), and each of "profiles" with its "person". Null when it has neither.
     */
    static JSONObject peopleFromDocument(JSONObject state) {
        if (state == null) return null;
        JSONObject documents = state.optJSONObject("profiles");
        JSONObject people = state.optJSONObject("people");
        if (documents == null && people == null) return null;
        JSONObject out = new JSONObject();
        try {
            if (documents != null) {
                for (Iterator<String> keys = documents.keys(); keys.hasNext(); ) {
                    String key = keys.next();
                    JSONObject document = documents.optJSONObject(key);
                    String id = document != null ? document.optString("person", "") : "";
                    if (id.startsWith("person.")) out.put(key, id);
                }
            }
            if (people != null) {
                for (Iterator<String> keys = people.keys(); keys.hasNext(); ) {
                    String key = keys.next();
                    String id = people.optString(key, "");
                    if (id.startsWith("person.")) out.put(key, id);
                }
            }
        } catch (JSONException e) {
            return null;
        }
        return out;
    }

    /** This TV's profile keys and the Home Assistant person each is mapped to, as the integration last said. */
    static Map<String, String> people(Context context) {
        Map<String, String> out = new HashMap<>();
        String saved = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(PEOPLE_KEY, null);
        if (saved == null) return out;
        try {
            JSONObject people = new JSONObject(saved);
            for (Iterator<String> keys = people.keys(); keys.hasNext(); ) {
                String key = keys.next();
                out.put(key, people.optString(key));
            }
        } catch (JSONException e) {
            Log.w(TAG, "The saved Home Assistant people aren't readable");
        }
        return out;
    }

    /** Keeps the profiles from the integration's answer (its state document) as today's allowance. */
    static void fromDocument(Context context, JSONObject state) {
        JSONObject people = peopleFromDocument(state);
        if (people != null) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                    .putString(PEOPLE_KEY, people.toString()).apply();
        }
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
     * no limit), and the apps of the groups with none left ("out_of_time": package -> group name; "all_out_of_time":
     * All screen time's name when it has none left). Null when it isn't such a document.
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
                JSONObject outOfTime = new JSONObject();
                // The groups with none left, {id, name}, for asking for more of them (HaLocks)
                JSONArray timeUpGroups = new JSONArray();
                String allOutOfTime = null;
                JSONArray allExcept = null;
                for (int i = 0; groups != null && i < groups.length(); i++) {
                    JSONObject group = groups.optJSONObject(i);
                    if (group == null || group.isNull("minutes_left")) continue;
                    int left = Math.max(0, group.optInt("minutes_left", 0));
                    JSONArray apps = group.optJSONArray("apps");
                    if (left == 0) {
                        String name = group.optString("name", "");
                        if (name.trim().isEmpty()) name = group.optString("id", "");
                        JSONObject timeUp = new JSONObject().put("id", group.optString("id", "")).put("name", name);
                        // An adult's pause of this group or app (hearth.pause with a group or app): no asking for more
                        JSONObject paused = group.optJSONObject("paused");
                        if (paused != null) timeUp.put("paused", paused);
                        timeUpGroups.put(timeUp);
                        if (ALL_GROUP.equals(group.optString("id"))) {
                            allOutOfTime = name;
                            allExcept = group.optJSONArray("except");
                        }
                        for (int j = 0; apps != null && j < apps.length(); j++) {
                            String app = apps.optString(j, "");
                            if (!app.isEmpty() && !NEVER_HELD.contains(app) && !outOfTime.has(app)) {
                                outOfTime.put(app, name);
                            }
                        }
                    }
                    // All screen time holds HearthTube's minutes too (its apps list is empty: every app)
                    if (!holdsHearthTube(apps) && !ALL_GROUP.equals(group.optString("id"))) continue;
                    least = least == null ? left : Math.min(least, left);
                }
                JSONObject entry = new JSONObject();
                entry.put("youtube_minutes_left", least == null ? JSONObject.NULL : least);
                entry.put("out_of_time", outOfTime);
                if (timeUpGroups.length() > 0) entry.put(TIME_UP_GROUPS_KEY, timeUpGroups);
                if (allOutOfTime != null) entry.put("all_out_of_time", allOutOfTime);
                if (allOutOfTime != null && allExcept != null) entry.put("all_except", allExcept);
                entry.put("schedule_locked", person != null && person.optBoolean("locked", false));
                JSONObject locks = new JSONObject();
                for (String field : LOCK_FIELDS) {
                    JSONObject value = person != null ? person.optJSONObject(field) : null;
                    if (value != null) locks.put(field, value);
                }
                if (locks.length() > 0) entry.put(LOCKS_KEY, locks);
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

    /** This profile's allowance as last read today; values null when Home Assistant has said nothing today. */
    static Values forProfile(Context context, String profileKey, long now) {
        // Without Home Assistant, Hearth's own rules say the same things
        if (!LocalAllowance.homeAssistantDecides(context)) {
            return valuesOf(LocalAllowance.entryFor(context, profileKey, now), null);
        }
        SharedPreferences prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        if (profileKey == null) return new Values(null, false, null, null);
        // A new day before Home Assistant has answered: its lock or pause still running holds, the minutes don't
        if (!UsageToday.day(now).equals(prefs.getString(DAY_KEY, null))) {
            return valuesOf(entryFor(context, profileKey, now), null);
        }
        Long checkedAt = prefs.contains(CHECKED_KEY) ? prefs.getLong(CHECKED_KEY, 0) : null;
        return valuesOf(entryFor(context, profileKey, now), checkedAt);
    }

    /**
     * This profile's entry as Home Assistant last said today (null: none, or nothing today); without Home Assistant,
     * from Hearth's own rules (LocalAllowance).
     */
    static JSONObject entryFor(Context context, String profileKey, long now) {
        if (!LocalAllowance.homeAssistantDecides(context)) return LocalAllowance.entryFor(context, profileKey, now);
        SharedPreferences prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        if (profileKey == null) return null;
        JSONObject entry;
        try {
            entry = new JSONObject(prefs.getString(PROFILES_KEY, "{}")).optJSONObject(profileKey);
        } catch (JSONException e) {
            return null;
        }
        if (UsageToday.day(now).equals(prefs.getString(DAY_KEY, null))) return entry;
        // Home Assistant hasn't answered since the day changed (it may be away): its last word still counts for what
        // runs past midnight, never for yesterday's minutes
        return carriedOver(entry, now);
    }

    /**
     * What of yesterday's entry still holds today: a lock (bedtime) or a pause that hasn't ended, and nothing else (no
     * minutes, no group out of time). Null when nothing does.
     */
    static JSONObject carriedOver(JSONObject entry, long now) {
        JSONObject locks = entry != null ? entry.optJSONObject(LOCKS_KEY) : null;
        if (locks == null) return null;
        JSONObject kept = new JSONObject();
        try {
            for (String field : new String[]{"lock", "pause"}) {
                JSONObject value = locks.optJSONObject(field);
                Long until = value != null ? HaLocks.parseTime(value.optString("until", null)) : null;
                if (until != null && until > now) kept.put(field, value);
            }
            if (kept.length() == 0) return null;
            JSONObject out = new JSONObject();
            out.put("youtube_minutes_left", JSONObject.NULL);
            out.put("out_of_time", new JSONObject());
            out.put("schedule_locked", kept.has("lock"));
            out.put(LOCKS_KEY, kept);
            return out;
        } catch (JSONException e) {
            return null;
        }
    }

    /** A profile's entry in the entity's "profiles" (none: no limit, not locked). */
    static Values valuesOf(JSONObject entry, Long checkedAt) {
        if (entry == null) return new Values(null, false, null, checkedAt);
        Integer minutes = entry.isNull("youtube_minutes_left") ? null
                : Math.max(0, (int) Math.floor(entry.optDouble("youtube_minutes_left", 0)));
        String message = entry.isNull("message") ? null : entry.optString("message", null);
        Map<String, String> outOfTime = new HashMap<>();
        JSONObject held = entry.optJSONObject("out_of_time");
        for (Iterator<String> keys = held != null ? held.keys() : Collections.emptyIterator(); keys.hasNext(); ) {
            String app = keys.next();
            outOfTime.put(app, held.optString(app, ""));
        }
        String all = entry.isNull("all_out_of_time") ? null : entry.optString("all_out_of_time", null);
        Set<String> except = new HashSet<>();
        JSONArray spared = entry.optJSONArray("all_except");
        for (int i = 0; spared != null && i < spared.length(); i++) except.add(spared.optString(i, ""));
        JSONObject locks = entry.optJSONObject(LOCKS_KEY);
        JSONObject pause = locks != null ? locks.optJSONObject("pause") : null;
        Long pausedUntil = null;
        if (pause != null) {
            Long until = HaLocks.parseTime(pause.optString("until", null));
            pausedUntil = until != null ? until : Long.MAX_VALUE;
        }
        return new Values(minutes, entry.optBoolean("schedule_locked", false),
                message != null && !message.trim().isEmpty() ? message.trim() : null, checkedAt,
                Collections.unmodifiableMap(outOfTime), all, Collections.unmodifiableSet(except), pausedUntil);
    }
}
