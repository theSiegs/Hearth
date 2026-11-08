package com.thesiegs.hearth;

import org.json.JSONArray;
import org.json.JSONObject;

import java.time.OffsetDateTime;
import java.time.format.DateTimeParseException;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.Iterator;
import java.util.List;
import java.util.Map;
import java.util.TreeSet;

/**
 * What the Hearth integration says about a kids profile's locks (docs/home-assistant-integration.md, Pause and locks,
 * Ask for more): a family pause {until, reason}, the lock on now {kind, until}, the next bedtime or school time
 * {at, kind}, and the latest request for more time. They come in each profile's state document and are kept with its
 * allowance (HaAllowance, under {@link HaAllowance#LOCKS_KEY}); this reads them for Flutter's time's up card and for
 * the bedtime heads-up. Times come as ISO 8601 with an offset and go on as epoch ms.
 */
final class HaLocks {
    /** Minutes before a bedtime or school time that a heads-up shows, the first one first. */
    static final int[] HEADS_UP_MINUTES = {15, 5};

    private HaLocks() {
    }

    /** An ISO 8601 date-time with an offset ("2026-10-26T19:00:00-05:00") as epoch ms; null when it isn't one. */
    static Long parseTime(String iso) {
        if (iso == null || iso.trim().isEmpty() || "null".equals(iso)) return null;
        try {
            return OffsetDateTime.parse(iso.trim()).toInstant().toEpochMilli();
        } catch (DateTimeParseException e) {
            return null;
        }
    }

    /** The profile entry's kept lock fields (none: an empty object). */
    static JSONObject locksOf(JSONObject entry) {
        JSONObject locks = entry != null ? entry.optJSONObject(HaAllowance.LOCKS_KEY) : null;
        return locks != null ? locks : new JSONObject();
    }

    /**
     * What Flutter's time's up card shows for the profile at [now]: {paired, kids, pause: {reason, until}, lock:
     * {kind, until}, nextLock: {kind, at}, request: {id, status, minutes, askedMinutes, group, expires, answered},
     * timeUp: [{id, name} of the groups out of time today]}; times are epoch ms (null: not known). A pause or next lock that's
     * over is left out.
     */
    static Map<String, Object> forFlutter(JSONObject entry, boolean paired, boolean kids, long now) {
        Map<String, Object> out = new HashMap<>();
        out.put("paired", paired);
        out.put("kids", kids);
        JSONObject locks = locksOf(entry);
        JSONObject pause = locks.optJSONObject("pause");
        if (pause != null) {
            Long until = parseTime(pause.optString("until", null));
            if (until == null || until > now) {
                Map<String, Object> map = new HashMap<>();
                map.put("reason", text(pause, "reason"));
                map.put("until", until);
                out.put("pause", map);
            }
        }
        JSONObject lock = locks.optJSONObject("lock");
        if (lock != null) {
            Map<String, Object> map = new HashMap<>();
            map.put("kind", kindOf(lock.optString("kind", "other")));
            map.put("until", parseTime(lock.optString("until", null)));
            out.put("lock", map);
        }
        JSONObject next = locks.optJSONObject("next_lock");
        Long at = next != null ? parseTime(next.optString("at", null)) : null;
        if (at != null && at > now) {
            Map<String, Object> map = new HashMap<>();
            map.put("kind", kindOf(next.optString("kind", "bedtime")));
            map.put("at", at);
            out.put("nextLock", map);
        }
        JSONObject request = locks.optJSONObject("request");
        if (request != null) out.put("request", requestForFlutter(request));
        out.put("timeUp", timeUpGroups(entry));
        out.put("groups", groupsLeft(entry));
        return out;
    }

    /**
     * Every group with a limit and its minutes left today, [{id, name, minutesLeft, apps, except}] (All screen time's
     * apps are empty: every app but its exceptions), as the last state document said. Empty from an older Hearth's
     * store or without the integration.
     */
    static List<Map<String, Object>> groupsLeft(JSONObject entry) {
        List<Map<String, Object>> groups = new ArrayList<>();
        JSONArray kept = entry != null ? entry.optJSONArray(HaAllowance.GROUPS_LEFT_KEY) : null;
        for (int i = 0; kept != null && i < kept.length(); i++) {
            JSONObject group = kept.optJSONObject(i);
            if (group == null) continue;
            Map<String, Object> map = new HashMap<>();
            map.put("id", text(group, "id"));
            map.put("name", text(group, "name"));
            map.put("minutesLeft", Math.max(0, group.optInt("minutes_left", 0)));
            map.put("apps", strings(group.optJSONArray("apps")));
            map.put("except", strings(group.optJSONArray("except")));
            groups.add(map);
        }
        return groups;
    }

    private static List<String> strings(JSONArray array) {
        List<String> out = new ArrayList<>();
        for (int i = 0; array != null && i < array.length(); i++) {
            String value = array.optString(i, "");
            if (!value.isEmpty()) out.add(value);
        }
        return out;
    }

    /** An ask's answer or a state document's request, for Flutter (times as epoch ms). */
    static Map<String, Object> requestForFlutter(JSONObject request) {
        Map<String, Object> map = new HashMap<>();
        map.put("id", text(request, "id"));
        map.put("status", text(request, "status"));
        map.put("minutes", request.isNull("minutes") ? null : request.optInt("minutes"));
        map.put("askedMinutes", request.isNull("asked_minutes") ? null : request.optInt("asked_minutes"));
        map.put("group", text(request, "group"));
        map.put("expires", parseTime(request.optString("expires", null)));
        map.put("answered", parseTime(request.optString("answered", null)));
        return map;
    }

    /**
     * The profile's groups out of time today, [{id, name}] (All screen time's included), as the document listed them;
     * from what an older Hearth kept, the names alone (id null).
     */
    static List<Map<String, Object>> timeUpGroups(JSONObject entry) {
        List<Map<String, Object>> groups = new ArrayList<>();
        JSONArray kept = entry != null ? entry.optJSONArray(HaAllowance.TIME_UP_GROUPS_KEY) : null;
        if (kept != null) {
            for (int i = 0; i < kept.length(); i++) {
                JSONObject group = kept.optJSONObject(i);
                String name = group != null ? text(group, "name") : null;
                if (name == null) continue;
                Map<String, Object> map = new HashMap<>();
                map.put("id", text(group, "id"));
                map.put("name", name);
                JSONObject paused = group.optJSONObject("paused");
                if (paused != null) {
                    // An adult paused it: the card says so, until when, and offers no ask
                    Map<String, Object> pause = new HashMap<>();
                    pause.put("name", text(paused, "name"));
                    pause.put("reason", text(paused, "reason"));
                    pause.put("until", parseTime(paused.optString("until", null)));
                    map.put("paused", pause);
                }
                groups.add(map);
            }
            return groups;
        }
        TreeSet<String> names = new TreeSet<>();
        JSONObject held = entry != null ? entry.optJSONObject("out_of_time") : null;
        for (Iterator<String> keys = held != null ? held.keys() : Collections.emptyIterator(); keys.hasNext(); ) {
            String name = held.optString(keys.next(), "");
            if (!name.trim().isEmpty()) names.add(name.trim());
        }
        String all = entry != null && !entry.isNull("all_out_of_time") ? entry.optString("all_out_of_time", "") : "";
        if (!all.trim().isEmpty()) names.add(all.trim());
        for (String name : names) {
            Map<String, Object> map = new HashMap<>();
            map.put("id", null);
            map.put("name", name);
            groups.add(map);
        }
        return groups;
    }

    /** The next bedtime or school time's start (epoch ms), or null when none is coming. */
    static Long nextLockAt(JSONObject entry, long now) {
        JSONObject next = locksOf(entry).optJSONObject("next_lock");
        Long at = next != null ? parseTime(next.optString("at", null)) : null;
        return at != null && at > now ? at : null;
    }

    /** The next lock's kind: bedtime or school_time. */
    static String nextLockKind(JSONObject entry) {
        JSONObject next = locksOf(entry).optJSONObject("next_lock");
        return kindOf(next != null ? next.optString("kind", "bedtime") : "bedtime");
    }

    /**
     * Which heads-up is due at [now] for a lock at [at]: 15 from 15 minutes before until 5 minutes before, 5 from then
     * until it starts, 0 otherwise. A heads-up missed at its moment (the TV was asleep, the answer came late) still
     * shows while its stretch lasts, with the minutes actually left.
     */
    static int headsUpMark(long at, long now) {
        for (int i = 0; i < HEADS_UP_MINUTES.length; i++) {
            long from = at - HEADS_UP_MINUTES[i] * 60_000L;
            long to = i + 1 < HEADS_UP_MINUTES.length ? at - HEADS_UP_MINUTES[i + 1] * 60_000L : at;
            if (now >= from && now < to) return HEADS_UP_MINUTES[i];
        }
        return 0;
    }

    /** When the next heads-up after [now] is due for a lock at [at] (epoch ms), or -1 when there's none to come. */
    static long nextHeadsUpAt(long at, long now) {
        for (int minutes : HEADS_UP_MINUTES) {
            long due = at - minutes * 60_000L;
            if (due > now) return due;
        }
        return -1;
    }

    /** Whole minutes until [at], rounded up (a heads-up at 14:10 left says 15). */
    static int minutesUntil(long at, long now) {
        return (int) Math.max(1, (at - now + 59_999) / 60_000);
    }

    private static String kindOf(String kind) {
        switch (kind == null ? "" : kind) {
            case "bedtime":
            case "school_time":
            case "pause":
                return kind;
            default:
                return "other";
        }
    }

    private static String text(JSONObject object, String key) {
        if (object.isNull(key)) return null;
        String value = object.optString(key, "").trim();
        return value.isEmpty() ? null : value;
    }
}
