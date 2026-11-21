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
    /**
     * Every group with a limit, [{id, name, minutes_left, apps, except, minutes_used}] as the document listed them, for
     * the remote API's minutes (RemoteTime).
     */
    static final String GROUPS_KEY = "groups";
    private static final String[] LOCK_FIELDS = {"pause", "lock", "next_lock", "request"};

    /** The integration's group of every app: its time up holds every app (but these). */
    static final String ALL_GROUP = "all";
    /** The entry's minutes left of today's time (All screen time's), when the document had it. */
    static final String DAY_LEFT_KEY = "day_left";
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
        long now = TvClock.now(context);
        // Each profile's time in front as of this word: counted down from, should Home Assistant go quiet
        for (Iterator<String> keys = profiles.keys(); keys.hasNext(); ) {
            String key = keys.next();
            JSONObject entry = profiles.optJSONObject(key);
            if (entry == null) continue;
            try {
                entry.put(FRONT_AT_KEY, new JSONObject(UsageToday.frontMs(context, key, now)));
                entry.put(WORD_AT_KEY, now);
            } catch (JSONException e) {
                Log.w(TAG, "Couldn't keep the time in front for " + key);
            }
        }
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
     * All screen time's name when it has none left; "day_left": All screen time's minutes left, today's time, when the
     * document has it). Null when it isn't such a document.
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
                JSONObject time = person != null ? person.optJSONObject("time") : null;
                Integer least = null;
                JSONObject outOfTime = new JSONObject();
                // The groups with none left, {id, name}, for asking for more of them (HaLocks)
                JSONArray timeUpGroups = new JSONArray();
                String allOutOfTime = null;
                JSONArray allExcept = null;
                Integer dayLeft = null;
                JSONArray limits = new JSONArray();
                for (int i = 0; groups != null && i < groups.length(); i++) {
                    JSONObject group = groups.optJSONObject(i);
                    if (group == null || group.isNull("minutes_left")) continue;
                    int left = Math.max(0, group.optInt("minutes_left", 0));
                    JSONArray apps = group.optJSONArray("apps");
                    limits.put(limit(group, left, time));
                    if (ALL_GROUP.equals(group.optString("id"))) dayLeft = left;
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
                    // All screen time holds HearthTube's minutes too (its apps list is empty: every app), unless
                    // HearthTube is one of its exceptions (YouTube allowed, or its own bonus running past daily time)
                    if (ALL_GROUP.equals(group.optString("id")) ? holdsHearthTube(group.optJSONArray("except"))
                            : !holdsHearthTube(apps)) {
                        continue;
                    }
                    least = least == null ? left : Math.min(least, left);
                }
                JSONObject entry = new JSONObject();
                entry.put("youtube_minutes_left", least == null ? JSONObject.NULL : least);
                entry.put("out_of_time", outOfTime);
                if (timeUpGroups.length() > 0) entry.put(TIME_UP_GROUPS_KEY, timeUpGroups);
                if (limits.length() > 0) entry.put(GROUPS_KEY, limits);
                if (allOutOfTime != null) entry.put("all_out_of_time", allOutOfTime);
                // Today's time left (All screen time's): "Games are done for today · 40 min left for other things"
                if (dayLeft != null) entry.put(DAY_LEFT_KEY, dayLeft);
                if (allOutOfTime != null && allExcept != null) entry.put("all_except", allExcept);
                entry.put("schedule_locked", person != null && person.optBoolean("locked", false));
                JSONObject locks = new JSONObject();
                for (String field : LOCK_FIELDS) {
                    JSONObject value = person != null ? person.optJSONObject(field) : null;
                    if (value != null) locks.put(field, value);
                }
                if (person != null) nextLockFromDocument(person, locks);
                if (locks.length() > 0) entry.put(LOCKS_KEY, locks);
                // For a stretch without Home Assistant: each lift's end (liftsEnded), tomorrow's minutes and first lock
                // (carriedOver), else today's base minutes from an older Home Assistant's time
                JSONArray lifts = person != null ? person.optJSONArray(LIFTS_KEY) : null;
                if (lifts != null && lifts.length() > 0) entry.put(LIFTS_KEY, lifts);
                JSONObject tomorrow = person != null ? person.optJSONObject(TOMORROW_KEY) : null;
                if (tomorrow != null) entry.put(TOMORROW_KEY, tomorrow);
                JSONObject base = tomorrow == null ? baseMinutes(time) : null;
                if (base != null) entry.put(BASE_KEY, base);
                profiles.put(profileId, entry);
            }
        } catch (JSONException e) {
            return null;
        }
        return profiles;
    }

    /**
     * What the document says of the next lock beyond its own "next_lock". Extra time at bedtime ("bedtime_lifted"
     * {since, until}) ends with bedtime back, so its end is the next lock unless an earlier one is named (a newer
     * Home Assistant names the lift's end itself). And the weekly schedule's wake time ("schedule" {"bedtime": {at,
     * wake}}) is when a bedtime the TV has to start itself ends ("until", unless the next lock says its own).
     */
    private static void nextLockFromDocument(JSONObject person, JSONObject locks) throws JSONException {
        JSONObject lifted = person.optJSONObject("bedtime_lifted");
        Long liftEnd = lifted != null ? HaLocks.parseTime(lifted.optString("until", null)) : null;
        JSONObject next = locks.optJSONObject("next_lock");
        Long at = next != null ? HaLocks.parseTime(next.optString("at", null)) : null;
        if (liftEnd != null && (at == null || at > liftEnd)) {
            next = new JSONObject().put("at", lifted.optString("until")).put("by", "bedtime_lifted")
                    .put("kind", "bedtime");
            at = liftEnd;
            locks.put("next_lock", next);
        }
        JSONObject schedule = person.optJSONObject("schedule");
        JSONObject bedtime = schedule != null ? schedule.optJSONObject("bedtime") : null;
        if (next == null || at == null || bedtime == null || !"bedtime".equals(next.optString("kind"))
                || HaLocks.parseTime(next.optString("until", null)) != null) {
            return;
        }
        Long bedtimeAt = HaLocks.parseTime(bedtime.optString("at", null));
        Long wake = HaLocks.parseTime(bedtime.optString("wake", null));
        if (bedtimeAt != null && wake != null && bedtimeAt <= at && at < wake) {
            // A copy: the document's own object is left as it came
            locks.put("next_lock", new JSONObject(next.toString()).put("until", bedtime.optString("wake")));
        }
    }

    /**
     * A group of the document as an entry keeps it: what the remote API reads, nothing else. Home Assistant sends no
     * "minutes_used" with a group: its "time" says them ("used" for All screen time, each category's "used").
     */
    private static JSONObject limit(JSONObject group, int left, JSONObject time) throws JSONException {
        JSONObject limit = new JSONObject().put("id", group.optString("id", "")).put("name", group.optString("name", ""))
                .put("minutes_left", left);
        for (String list : new String[]{"apps", "except"}) {
            JSONArray value = group.optJSONArray(list);
            if (value != null) limit.put(list, value);
        }
        if (group.has("minutes_used") && !group.isNull("minutes_used")) {
            limit.put("minutes_used", Math.max(0, group.optInt("minutes_used", 0)));
        } else if (time != null) {
            String id = group.optString("id", "");
            JSONObject from = ALL_GROUP.equals(id) ? time : null;
            JSONArray categories = time.optJSONArray("categories");
            for (int i = 0; from == null && categories != null && i < categories.length(); i++) {
                JSONObject category = categories.optJSONObject(i);
                if (category != null && !id.isEmpty() && id.equals(category.optString("id"))) from = category;
            }
            if (from != null && from.has("used") && !from.isNull("used")) {
                limit.put("minutes_used", Math.max(0, from.optInt("used", 0)));
            }
        }
        return limit;
    }

    /**
     * Today's base minutes per group from the document's time, without bonus time: daily time's "base_minutes" and
     * each category's "limit". Null when it says none.
     */
    private static JSONObject baseMinutes(JSONObject time) throws JSONException {
        if (time == null) return null;
        JSONObject out = new JSONObject();
        if (time.has("base_minutes") && !time.isNull("base_minutes")) {
            out.put(ALL_GROUP, Math.max(0, time.optInt("base_minutes", 0)));
        }
        JSONArray categories = time.optJSONArray("categories");
        for (int i = 0; categories != null && i < categories.length(); i++) {
            JSONObject category = categories.optJSONObject(i);
            String id = category != null ? category.optString("id", "") : "";
            if (!id.isEmpty() && category.has("limit") && !category.isNull("limit")) {
                out.put(id, Math.max(0, category.optInt("limit", 0)));
            }
        }
        return out.length() > 0 ? out : null;
    }

    private static boolean holdsHearthTube(JSONArray apps) {
        for (int i = 0; apps != null && i < apps.length(); i++) {
            if (isHearthTube(apps.optString(i))) return true;
        }
        return false;
    }

    private static boolean isHearthTube(String app) {
        return CompanionApps.HEARTHTUBE.equals(app) || "com.thesiegs.hearthtube.mobile".equals(app);
    }

    /** This profile's allowance as last read today; values null when Home Assistant has said nothing today. */
    static Values forProfile(Context context, String profileKey, long now) {
        // Without Home Assistant, Hearth's own rules say the same things
        if (!LocalAllowance.homeAssistantDecides(context)) {
            return valuesOf(LocalAllowance.entryFor(context, profileKey, now), null, now);
        }
        SharedPreferences prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        if (profileKey == null) return new Values(null, false, null, null);
        // A new day before Home Assistant has answered: its lock or pause still running holds, the minutes don't
        if (!UsageToday.day(now).equals(prefs.getString(DAY_KEY, null))) {
            return valuesOf(entryFor(context, profileKey, now), null, now);
        }
        Long checkedAt = prefs.contains(CHECKED_KEY) ? prefs.getLong(CHECKED_KEY, 0) : null;
        return valuesOf(entryFor(context, profileKey, now), checkedAt, now);
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
        if (UsageToday.day(now).equals(prefs.getString(DAY_KEY, null))) {
            long checkedAt = prefs.getLong(CHECKED_KEY, now);
            // Read only when a lift may have ended (Home Assistant quiet past the grace)
            Map<String, Long> front = entry != null && entry.has(LIFTS_KEY)
                    && now - entry.optLong(WORD_AT_KEY, now) >= Allowance.NEXT_LOCK_GRACE_MS
                    ? UsageToday.frontMs(context, profileKey, now) : null;
            // Extra time ended with Home Assistant away: its group is held again, counted down from here
            JSONObject lifted = liftsEnded(entry, now, front);
            if (lifted != null) return staleCountdown(lifted, front);
            // Home Assistant quiet for a while (the router unplugged, say): its minutes are counted down here
            if (now - checkedAt > STALE_AFTER_MS) {
                return staleCountdown(entry, front != null ? front : UsageToday.frontMs(context, profileKey, now));
            }
            return entry;
        }
        // Home Assistant hasn't answered since the day changed (it may be away): its last word still counts for what
        // runs past midnight, and the new day's minutes are tomorrow's as it last said them, counted down here
        JSONObject carried = carriedOver(entry, now);
        if (carried == null || !carried.has(GROUPS_KEY)) return carried;
        return staleCountdown(carried, UsageToday.frontMs(context, profileKey, now));
    }

    /** Home Assistant's word this old: the TV counts its minutes down itself (staleCountdown). */
    static final long STALE_AFTER_MS = 10 * 60_000L;
    /** In an entry: the profile's time in front per app (ms) when Home Assistant's word came. */
    static final String FRONT_AT_KEY = "front_ms_at";
    /** In an entry: when Home Assistant's word came (ms). */
    static final String WORD_AT_KEY = "word_at";

    /**
     * [entry] with each group's minutes left less the time in front since Home Assistant's word ([frontNow]: each
     * app's ms today, against the entry's FRONT_AT_KEY): a group that runs out is held as Home Assistant would hold
     * it (its apps out of time; All screen time: every app but its exceptions). HearthTube's time counts like any
     * app's, and its minutes ("youtube_minutes_left") come down with what the other apps took of a group holding it,
     * to 0 when the group runs out (HearthTube takes off what it played itself). Unchanged without a snapshot.
     */
    static JSONObject staleCountdown(JSONObject entry, Map<String, Long> frontNow) {
        JSONObject at = entry != null ? entry.optJSONObject(FRONT_AT_KEY) : null;
        JSONArray groups = entry != null ? entry.optJSONArray(GROUPS_KEY) : null;
        if (at == null || groups == null || frontNow == null) return entry;
        try {
            JSONObject out = new JSONObject(entry.toString());
            JSONObject outOfTime = out.optJSONObject("out_of_time");
            if (outOfTime == null) {
                outOfTime = new JSONObject();
                out.put("out_of_time", outOfTime);
            }
            Map<String, Long> since = new HashMap<>();
            for (Map.Entry<String, Long> e : frontNow.entrySet()) {
                long used = e.getValue() - at.optLong(e.getKey(), 0);
                // HearthTube is never held here (it holds itself), but its time is screen time like any app's
                if (used > 0 && (!NEVER_HELD.contains(e.getKey()) || isHearthTube(e.getKey()))) {
                    since.put(e.getKey(), used);
                }
            }
            Long tubeLeft = null;
            for (int i = 0; i < groups.length(); i++) {
                JSONObject group = groups.optJSONObject(i);
                if (group == null || group.isNull("minutes_left")) continue;
                long left = group.optLong("minutes_left", 0) * 60_000L;
                boolean all = ALL_GROUP.equals(group.optString("id"));
                JSONArray apps = group.optJSONArray("apps");
                Set<String> members = new HashSet<>();
                for (int j = 0; apps != null && j < apps.length(); j++) members.add(apps.optString(j, ""));
                // All screen time's exceptions (music outside it, an allowed app) never count against it
                Set<String> notCounted = new HashSet<>();
                JSONArray spared = all ? group.optJSONArray("except") : null;
                for (int j = 0; spared != null && j < spared.length(); j++) notCounted.add(spared.optString(j, ""));
                long spent = 0;
                long others = 0;
                for (Map.Entry<String, Long> e : since.entrySet()) {
                    if (all ? !notCounted.contains(e.getKey()) : members.contains(e.getKey())) {
                        spent += e.getValue();
                        if (!isHearthTube(e.getKey())) others += e.getValue();
                    }
                }
                if (left > 0 && (all ? !holdsHearthTube(spared) : holdsHearthTube(apps))) {
                    // Whole minutes, rounded up: a few seconds of another app don't take a minute off
                    long minutes = spent >= left ? 0 : (left - others + 59_999) / 60_000L;
                    tubeLeft = tubeLeft == null ? minutes : Math.min(tubeLeft, minutes);
                }
                if (left <= 0 || spent < left) continue;
                hold(out, group);
            }
            // Only ever down, and only where Home Assistant gave HearthTube minutes at all
            if (tubeLeft != null && !out.isNull("youtube_minutes_left")
                    && tubeLeft < out.optDouble("youtube_minutes_left", 0)) {
                out.put("youtube_minutes_left", tubeLeft.intValue());
            }
            return out;
        } catch (JSONException e) {
            return entry;
        }
    }

    /**
     * Holds [group] (an entry's group, as GROUPS_KEY keeps it) in [out] as Home Assistant would hold it once its time
     * is up: its apps out of time, or for All screen time every app but its exceptions.
     */
    private static void hold(JSONObject out, JSONObject group) throws JSONException {
        String name = group.optString("name", "");
        if (name.trim().isEmpty()) name = group.optString("id", "");
        if (ALL_GROUP.equals(group.optString("id"))) {
            if (out.isNull("all_out_of_time") || !out.has("all_out_of_time")) out.put("all_out_of_time", name);
            JSONArray except = group.optJSONArray("except");
            if (except != null && !out.has("all_except")) out.put("all_except", except);
            return;
        }
        JSONObject outOfTime = out.optJSONObject("out_of_time");
        if (outOfTime == null) {
            outOfTime = new JSONObject();
            out.put("out_of_time", outOfTime);
        }
        JSONArray apps = group.optJSONArray("apps");
        for (int j = 0; apps != null && j < apps.length(); j++) {
            String app = apps.optString(j, "");
            if (!app.isEmpty() && !NEVER_HELD.contains(app) && !outOfTime.has(app)) outOfTime.put(app, name);
        }
    }

    /** In an entry: the document's lifts, [{group, until, minutes, minutes_after, apps, except, in_daily}]. */
    static final String LIFTS_KEY = "lifts";
    /** In an entry: the document's "tomorrow" {date, groups [{id, minutes, name, apps, except}], next_lock}. */
    static final String TOMORROW_KEY = "tomorrow";
    /** In an entry: today's base minutes per group ({id: minutes}) from the document's time, for an older Home Assistant. */
    static final String BASE_KEY = "base_minutes";

    /**
     * [entry] with the lifts that have ended with no word from Home Assistant since (Allowance.NEXT_LOCK_GRACE_MS, as
     * for a next lock): an allow's or Unlimited's end ("until") once that's past, a category's own bonus ("minutes")
     * once its apps have been in front that long since the word ([frontNow]: each app's ms today, against the entry's
     * FRONT_AT_KEY). Each such group is held again as a group of the entry, with its "minutes_after" left once the
     * lift is over: its bonus (spent first) and the time from the word to the lift's end (not counted by Home
     * Assistant, though staleCountdown counts the time in front from the word) are added, so staleCountdown holds it
     * no sooner than Home Assistant would. Its apps count in daily time again ("in_daily"). Null when no lift has ended.
     */
    static JSONObject liftsEnded(JSONObject entry, long now, Map<String, Long> frontNow) {
        JSONArray lifts = entry != null ? entry.optJSONArray(LIFTS_KEY) : null;
        if (lifts == null || lifts.length() == 0) return null;
        long wordAt = entry.optLong(WORD_AT_KEY, 0);
        if (now - wordAt < Allowance.NEXT_LOCK_GRACE_MS) return null;
        JSONObject frontAt = entry.optJSONObject(FRONT_AT_KEY);
        try {
            JSONObject out = null;
            // The time All screen time didn't count of what's been in front since the word (a lift's own time, its
            // bonus): added to its minutes when its apps count in it again, as staleCountdown counts all of it
            long allFree = 0;
            boolean allLifted = false;
            // All screen time first, so the others' apps come out of its exceptions
            for (int pass = 0; pass < 2; pass++) {
                for (int i = 0; i < lifts.length(); i++) {
                    JSONObject lift = lifts.optJSONObject(i);
                    String id = lift != null ? lift.optString("group", "") : "";
                    if (id.isEmpty() || ALL_GROUP.equals(id) != (pass == 0)) continue;
                    Long until = HaLocks.parseTime(lift.optString("until", null));
                    int bonus = Math.max(0, lift.optInt("minutes", 0));
                    if (until == null && bonus <= 0) continue;
                    if (until != null && (now < until + Allowance.NEXT_LOCK_GRACE_MS || wordAt >= until)) continue;
                    if (bonus > 0 && spentSince(lift.optJSONArray("apps"), frontAt, frontNow) < bonus * 60_000L) continue;
                    if (out == null) out = new JSONObject(entry.toString());
                    long free = until != null ? Math.max(0, until - wordAt) / 60_000L : 0;
                    int left = (int) Math.min(24 * 60, Math.max(0, lift.optInt("minutes_after", 0)) + bonus + free);
                    JSONObject group = new JSONObject().put("id", id).put("name", lift.optString("name", id))
                            .put("minutes_left", left);
                    for (String list : new String[]{"apps", "except"}) {
                        JSONArray value = lift.optJSONArray(list);
                        if (value != null) group.put(list, value);
                    }
                    if (!ALL_GROUP.equals(id) && !group.has("apps")) group.put("apps", new JSONArray());
                    putGroup(out, group);
                    if (ALL_GROUP.equals(id)) {
                        allLifted = true;
                    } else if (lift.optBoolean("in_daily", true)) {
                        countInDaily(out, group.optJSONArray("apps"));
                        allFree = Math.max(allFree, free + bonus);
                    }
                    if (left <= 0) hold(out, group);
                }
            }
            JSONArray groups = out != null && !allLifted && allFree > 0 ? out.optJSONArray(GROUPS_KEY) : null;
            for (int i = 0; groups != null && i < groups.length(); i++) {
                JSONObject group = groups.optJSONObject(i);
                if (group == null || !ALL_GROUP.equals(group.optString("id"))) continue;
                int left = group.optInt("minutes_left", 0);
                if (left > 0) group.put("minutes_left", (int) Math.min(24 * 60, left + allFree));
            }
            if (out != null) out.put("youtube_minutes_left", tubeMinutes(out, out.opt("youtube_minutes_left")));
            return out;
        } catch (JSONException e) {
            return null;
        }
    }

    /** The ms [apps] were in front since the word ([at], as FRONT_AT_KEY keeps it) until [frontNow]. */
    private static long spentSince(JSONArray apps, JSONObject at, Map<String, Long> frontNow) {
        if (apps == null || at == null || frontNow == null) return 0;
        long spent = 0;
        for (int i = 0; i < apps.length(); i++) {
            Long front = frontNow.get(apps.optString(i, ""));
            if (front != null) spent += Math.max(0, front - at.optLong(apps.optString(i, ""), 0));
        }
        return spent;
    }

    /** [group] in the entry's groups, in place of one with its id. */
    private static void putGroup(JSONObject out, JSONObject group) throws JSONException {
        JSONArray groups = out.optJSONArray(GROUPS_KEY);
        JSONArray kept = new JSONArray();
        for (int i = 0; groups != null && i < groups.length(); i++) {
            JSONObject other = groups.optJSONObject(i);
            if (other != null && !group.optString("id").equals(other.optString("id"))) kept.put(other);
        }
        kept.put(group);
        out.put(GROUPS_KEY, kept);
    }

    /** [apps] are no longer exceptions of All screen time (in its group and, while it's out, the entry's all_except). */
    private static void countInDaily(JSONObject out, JSONArray apps) throws JSONException {
        Set<String> back = new HashSet<>();
        for (int i = 0; apps != null && i < apps.length(); i++) back.add(apps.optString(i, ""));
        if (back.isEmpty()) return;
        JSONArray groups = out.optJSONArray(GROUPS_KEY);
        for (int i = 0; groups != null && i < groups.length(); i++) {
            JSONObject group = groups.optJSONObject(i);
            if (group != null && ALL_GROUP.equals(group.optString("id")) && group.has("except")) {
                group.put("except", without(group.optJSONArray("except"), back));
            }
        }
        if (out.has("all_except")) out.put("all_except", without(out.optJSONArray("all_except"), back));
    }

    private static JSONArray without(JSONArray list, Set<String> leave) {
        JSONArray out = new JSONArray();
        for (int i = 0; list != null && i < list.length(); i++) {
            if (!leave.contains(list.optString(i, ""))) out.put(list.opt(i));
        }
        return out;
    }

    /**
     * HearthTube's minutes from the entry's groups: the fewest left in a group holding it (All screen time holds it
     * unless it's one of its exceptions), and never more than [before] (a number) says. JSON null when none holds it.
     */
    private static Object tubeMinutes(JSONObject out, Object before) {
        JSONArray groups = out.optJSONArray(GROUPS_KEY);
        Integer least = before instanceof Number ? ((Number) before).intValue() : null;
        for (int i = 0; groups != null && i < groups.length(); i++) {
            JSONObject group = groups.optJSONObject(i);
            if (group == null || group.isNull("minutes_left")) continue;
            boolean holds = ALL_GROUP.equals(group.optString("id")) ? !holdsHearthTube(group.optJSONArray("except"))
                    : holdsHearthTube(group.optJSONArray("apps"));
            if (!holds) continue;
            int left = Math.max(0, group.optInt("minutes_left", 0));
            least = least == null ? left : Math.min(least, left);
        }
        return least == null ? JSONObject.NULL : least;
    }

    /**
     * Today's groups for a new day Home Assistant hasn't spoken of yet: yesterday's groups (their apps and exceptions)
     * with the minutes "tomorrow" gave for them, and those of tomorrow's groups that came with their own apps; without
     * "tomorrow" (an older Home Assistant), yesterday's base minutes (BASE_KEY). Null when neither says.
     */
    static JSONArray newDayGroups(JSONObject entry) throws JSONException {
        JSONObject tomorrow = entry.optJSONObject(TOMORROW_KEY);
        JSONArray ahead = tomorrow != null ? tomorrow.optJSONArray("groups") : null;
        JSONObject minutes = new JSONObject();
        JSONObject own = new JSONObject();
        if (ahead != null) {
            for (int i = 0; i < ahead.length(); i++) {
                JSONObject group = ahead.optJSONObject(i);
                if (group == null || group.isNull("minutes") || !group.has("minutes")) continue;
                String id = group.optString("id", "");
                if (id.isEmpty()) continue;
                minutes.put(id, Math.max(0, group.optInt("minutes", 0)));
                if (group.has("apps") || group.has("except")) own.put(id, group);
            }
        } else {
            JSONObject base = entry.optJSONObject(BASE_KEY);
            if (base == null) return null;
            minutes = base;
        }
        JSONArray out = new JSONArray();
        Set<String> done = new HashSet<>();
        JSONArray yesterday = entry.optJSONArray(GROUPS_KEY);
        for (int i = 0; yesterday != null && i < yesterday.length(); i++) {
            JSONObject group = yesterday.optJSONObject(i);
            String id = group != null ? group.optString("id", "") : "";
            if (id.isEmpty() || !minutes.has(id) || own.has(id) || !done.add(id)) continue;
            JSONObject today = new JSONObject().put("id", id).put("name", group.optString("name", id))
                    .put("minutes_left", Math.max(0, minutes.optInt(id, 0)));
            for (String list : new String[]{"apps", "except"}) {
                JSONArray value = group.optJSONArray(list);
                if (value != null) today.put(list, value);
            }
            out.put(today);
        }
        for (Iterator<String> keys = own.keys(); keys.hasNext(); ) {
            String id = keys.next();
            if (!done.add(id)) continue;
            JSONObject group = own.getJSONObject(id);
            JSONObject today = new JSONObject().put("id", id).put("name", group.optString("name", id))
                    .put("minutes_left", Math.max(0, minutes.optInt(id, 0)));
            for (String list : new String[]{"apps", "except"}) {
                JSONArray value = group.optJSONArray(list);
                if (value != null) today.put(list, value);
            }
            if (!ALL_GROUP.equals(id) && !today.has("apps")) today.put("apps", new JSONArray());
            out.put(today);
        }
        return out.length() > 0 ? out : null;
    }

    /**
     * What of yesterday's entry still holds today: a lock (bedtime) or a pause that hasn't ended, a lock that names no
     * end (it holds until Home Assistant says otherwise), and the next lock it named, with when the word came, so a
     * bedtime the TV started itself goes on past midnight (Allowance.lockedNow); once that one's over, the first lock
     * of the new day "tomorrow" named (School time), while it hasn't ended. And the new day's minutes (newDayGroups),
     * from the start of the day (an empty FRONT_AT_KEY: entryFor counts them down with staleCountdown), a group with
     * none held at once. No group yesterday's time held. Null when nothing does.
     */
    static JSONObject carriedOver(JSONObject entry, long now) {
        if (entry == null) return null;
        JSONObject locks = entry.optJSONObject(LOCKS_KEY);
        if (locks == null) locks = new JSONObject();
        JSONObject kept = new JSONObject();
        try {
            for (String field : new String[]{"lock", "pause"}) {
                JSONObject value = locks.optJSONObject(field);
                Long until = value != null ? HaLocks.parseTime(value.optString("until", null)) : null;
                if (until != null && until > now) kept.put(field, value);
            }
            JSONObject lock = locks.optJSONObject("lock");
            if (lock != null && !kept.has("lock") && HaLocks.parseTime(lock.optString("until", null)) == null) {
                kept.put("lock", lock);
            }
            JSONObject next = locks.optJSONObject("next_lock");
            Long nextUntil = next != null ? HaLocks.parseTime(next.optString("until", null)) : null;
            if (next != null && HaLocks.parseTime(next.optString("at", null)) != null
                    && (nextUntil == null || nextUntil > now)) {
                kept.put("next_lock", next);
            }
            JSONObject tomorrow = entry.optJSONObject(TOMORROW_KEY);
            JSONObject first = tomorrow != null ? tomorrow.optJSONObject("next_lock") : null;
            // Only one that says when it ends: an old one with no end would hold for good
            Long firstAt = first != null ? HaLocks.parseTime(first.optString("at", null)) : null;
            Long firstUntil = first != null ? HaLocks.parseTime(first.optString("until", null)) : null;
            if (!kept.has("next_lock") && firstAt != null && firstUntil != null && firstUntil > now) {
                kept.put("next_lock", first);
            }
            JSONArray groups = newDayGroups(entry);
            if (kept.length() == 0 && groups == null) return null;
            JSONObject out = new JSONObject();
            out.put("youtube_minutes_left", JSONObject.NULL);
            out.put("out_of_time", new JSONObject());
            out.put("schedule_locked", kept.has("lock"));
            if (kept.length() > 0) out.put(LOCKS_KEY, kept);
            if (entry.has(WORD_AT_KEY)) out.put(WORD_AT_KEY, entry.optLong(WORD_AT_KEY));
            if (groups != null) {
                out.put(GROUPS_KEY, groups);
                out.put(FRONT_AT_KEY, new JSONObject());
                for (int i = 0; i < groups.length(); i++) {
                    JSONObject group = groups.getJSONObject(i);
                    if (group.optInt("minutes_left", 0) <= 0) hold(out, group);
                    if (ALL_GROUP.equals(group.optString("id"))) out.put(DAY_LEFT_KEY, group.optInt("minutes_left"));
                }
                out.put("youtube_minutes_left", tubeMinutes(out, null));
            }
            return out;
        } catch (JSONException e) {
            return null;
        }
    }

    /** A profile's entry in the entity's "profiles" (none: no limit, not locked), as of now. */
    static Values valuesOf(JSONObject entry, Long checkedAt) {
        return valuesOf(entry, checkedAt, System.currentTimeMillis());
    }

    /**
     * As {@link #valuesOf(JSONObject, Long)} at [now]: locked is what holds the other apps then (Allowance.lockedNow),
     * so a lock whose end has passed no longer locks HearthTube, and a bedtime the TV started itself does.
     */
    static Values valuesOf(JSONObject entry, Long checkedAt, long now) {
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
        JSONObject lock = locks != null ? locks.optJSONObject("lock") : null;
        // Without the lock's own fields (an entry from an older Hearth) the document's "locked" is all there is
        boolean locked = lock == null && entry.optBoolean("schedule_locked", false) || Allowance.lockedNow(entry, now);
        return new Values(minutes, locked,
                message != null && !message.trim().isEmpty() ? message.trim() : null, checkedAt,
                Collections.unmodifiableMap(outOfTime), all, Collections.unmodifiableSet(except), pausedUntil);
    }
}
