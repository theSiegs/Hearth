package com.thesiegs.hearth;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

/**
 * A kid's minutes and locks for the remote API's version 2 (docs/tv-remote-api.md, V2.3 {@code state.time}, V2.6
 * {@code synced.time}, V2.7 {@code kids}), worked out from a profile's allowance entry: the one {@link HaAllowance}
 * keeps from Home Assistant's document, or {@link LocalAllowance} builds from Hearth's own rules. So the phone sees
 * what the TV enforces, in either mode. Pure.
 */
final class RemoteTime {
    static final String WHY_TIME_UP = "time_up";
    static final String WHY_BEDTIME = "bedtime";
    static final String WHY_SCHOOL = "school";
    static final String WHY_PAUSED = "paused";

    private RemoteTime() {
    }

    /**
     * {@code state.time} for the profile in front with {@code app} in front: the minutes left of the group that binds
     * the app (the smaller of that group and All), its group, the lock and until when. Null for no limit and no lock
     * (an adult's profile has no entry).
     */
    static JSONObject front(JSONObject entry, String app, long now) throws JSONException {
        if (entry == null) return null;
        JSONObject binding = binding(entry, app);
        Lock lock = lock(entry, binding != null ? binding.optInt("minutes_left", -1) : -1, now);
        if (binding == null && lock.why == null && lock.until == null) return null;
        JSONObject time = new JSONObject();
        time.put("minutesLeft", binding != null ? Math.max(0, binding.optInt("minutes_left", 0)) : JSONObject.NULL);
        time.put("group", binding != null ? group(binding) : JSONObject.NULL);
        time.put("until", lock.until != null ? lock.until : JSONObject.NULL);
        time.put("locked", lock.locked);
        time.put("why", lock.why != null ? lock.why : JSONObject.NULL);
        return time;
    }

    /**
     * {@code synced.time} for a kid: every limit's minutes left today ({@code all} and {@code groups}), the lock, and
     * until when; {@code hold} is null (holds over the remote API aren't built). Null when the profile has no entry.
     */
    static JSONObject day(JSONObject entry, long now, String day) throws JSONException {
        if (entry == null) return null;
        JSONObject time = new JSONObject().put("asOf", now).put("day", day);
        putLimits(time, entry);
        JSONObject all = time.optJSONObject("all");
        Lock lock = lock(entry, all != null ? all.optInt("left", -1) : -1, now);
        time.put("locked", lock.locked);
        time.put("why", lock.why != null ? lock.why : JSONObject.NULL);
        time.put("until", lock.until != null ? lock.until : JSONObject.NULL);
        time.put("hold", JSONObject.NULL);
        return time;
    }

    /** A kid's line in {@code kids}: {@code all}, {@code groups}, {@code locked}, {@code why}. */
    static JSONObject kid(JSONObject entry, long now) throws JSONException {
        JSONObject time = new JSONObject();
        if (entry == null) {
            return time.put("all", JSONObject.NULL).put("groups", new JSONObject()).put("locked", false)
                    .put("why", JSONObject.NULL);
        }
        putLimits(time, entry);
        JSONObject all = time.optJSONObject("all");
        Lock lock = lock(entry, all != null ? all.optInt("left", -1) : -1, now);
        return time.put("locked", lock.locked).put("why", lock.why != null ? lock.why : JSONObject.NULL);
    }

    /** {"all": {left[, used]} or null, "groups": {id: {left[, used]}}} from the entry's groups. */
    private static void putLimits(JSONObject time, JSONObject entry) throws JSONException {
        JSONObject groups = new JSONObject();
        Object all = JSONObject.NULL;
        JSONArray listed = entry.optJSONArray(HaAllowance.GROUPS_KEY);
        for (int i = 0; listed != null && i < listed.length(); i++) {
            JSONObject group = listed.optJSONObject(i);
            if (group == null || group.isNull("minutes_left")) continue;
            JSONObject limit = new JSONObject().put("left", Math.max(0, group.optInt("minutes_left", 0)));
            if (group.has("minutes_used") && !group.isNull("minutes_used")) {
                limit.put("used", Math.max(0, group.optInt("minutes_used", 0)));
            }
            String id = group.optString("id", "");
            if (HaAllowance.ALL_GROUP.equals(id)) {
                all = limit;
            } else if (!id.isEmpty()) {
                groups.put(id, limit);
            }
        }
        time.put("all", all);
        time.put("groups", groups);
    }

    /**
     * The group with a limit that binds {@code app}: the one with the fewest minutes left of All (unless the app is
     * outside it) and the groups listing the app; a tie goes to the app's own group. Null when none does. With no app
     * (or Hearth's home) only All binds.
     */
    static JSONObject binding(JSONObject entry, String app) {
        JSONArray groups = entry.optJSONArray(HaAllowance.GROUPS_KEY);
        JSONObject best = null;
        boolean neverHeld = app != null && HaAllowance.NEVER_HELD.contains(app);
        for (int i = 0; groups != null && i < groups.length(); i++) {
            JSONObject group = groups.optJSONObject(i);
            if (group == null || group.isNull("minutes_left")) continue;
            boolean all = HaAllowance.ALL_GROUP.equals(group.optString("id"));
            boolean binds = all ? !neverHeld && !contains(group.optJSONArray("except"), app)
                    : app != null && contains(group.optJSONArray("apps"), app);
            if (!binds) continue;
            int left = group.optInt("minutes_left", 0);
            if (best == null) {
                best = group;
                continue;
            }
            int bestLeft = best.optInt("minutes_left", 0);
            boolean bestAll = HaAllowance.ALL_GROUP.equals(best.optString("id"));
            if (left < bestLeft || (left == bestLeft && bestAll && !all)) best = group;
        }
        return best;
    }

    private static JSONObject group(JSONObject binding) throws JSONException {
        String id = binding.optString("id", "");
        String name = binding.optString("name", "");
        return new JSONObject().put("id", id).put("name", name.trim().isEmpty() ? id : name);
    }

    static final class Lock {
        final boolean locked;
        final String why;
        /** ISO 8601: when the lock ends while locked, else when the next one starts; null when not known or none. */
        final String until;

        Lock(boolean locked, String why, String until) {
            this.locked = locked;
            this.why = why;
            this.until = until;
        }
    }

    /**
     * What holds the profile now, in order: a family pause, a lock (bedtime, School time) that hasn't ended, its time
     * used up ({@code minutesLeft} 0; -1: no limit). Not locked: the next lock's start as {@code until}.
     */
    static Lock lock(JSONObject entry, int minutesLeft, long now) {
        JSONObject locks = HaLocks.locksOf(entry);
        JSONObject pause = locks.optJSONObject("pause");
        if (pause != null) {
            String until = text(pause, "until");
            Long end = HaLocks.parseTime(until);
            if (end == null || end > now) return new Lock(true, WHY_PAUSED, end != null ? until : null);
        }
        JSONObject held = locks.optJSONObject("lock");
        String heldUntil = held != null ? text(held, "until") : null;
        Long heldEnd = HaLocks.parseTime(heldUntil);
        if (held != null && (heldEnd == null || heldEnd > now)) {
            String kind = held.optString("kind", "");
            return new Lock(true, "school_time".equals(kind) || "school".equals(kind) ? WHY_SCHOOL : WHY_BEDTIME,
                    heldEnd != null ? heldUntil : null);
        }
        if (minutesLeft == 0) return new Lock(true, WHY_TIME_UP, null);
        JSONObject next = locks.optJSONObject("next_lock");
        String at = next != null ? text(next, "at") : null;
        Long start = HaLocks.parseTime(at);
        return new Lock(false, null, start != null && start > now ? at : null);
    }

    /** Whether the kid's own rules let them open {@code app} now (their profile's entry; none: no rules). */
    static boolean allowed(JSONObject entry, String app, long now) {
        if (entry == null || app == null) return true;
        HaAllowance.Values values = HaAllowance.valuesOf(entry, null);
        return Allowance.heldApps(java.util.Collections.singletonList(app), entry, values.youtubeMinutesLeft,
                "YouTube", now).isEmpty();
    }

    private static boolean contains(JSONArray array, String value) {
        if (value == null) return false;
        for (int i = 0; array != null && i < array.length(); i++) {
            if (value.equals(array.optString(i))) return true;
        }
        return false;
    }

    private static String text(JSONObject object, String key) {
        if (object.isNull(key)) return null;
        String value = object.optString(key, "").trim();
        return value.isEmpty() ? null : value;
    }
}
