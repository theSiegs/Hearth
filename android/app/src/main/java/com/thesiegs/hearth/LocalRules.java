package com.thesiegs.hearth;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.time.DayOfWeek;
import java.time.LocalTime;
import java.time.ZonedDateTime;
import java.time.format.DateTimeFormatter;
import java.time.format.DateTimeParseException;
import java.util.ArrayList;
import java.util.Collection;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.function.Function;

/**
 * Hearth's own screen-time rules for a kid, for a TV without Home Assistant (docs/tv-remote-api.md, Version 2, the
 * {@code rules} object): All screen time and groups of apps, each with minutes on weekdays and on weekends, and a
 * bedtime. Pure: from the rules and what the kid used today it builds the same per-person document Home Assistant's
 * integration sends ({@code groups}, {@code locked}, {@code lock}, {@code next_lock}), so
 * {@link HaAllowance#profilesFromDocument} turns it into the entries everything else already reads (holds, the
 * time's-up card, HearthTube's allowance, the bedtime heads-up). With Home Assistant paired it isn't used at all:
 * Home Assistant's rules win outright.
 *
 * <p>Rules, as JSON: {@code {"all": {"weekday": 120, "weekend": 180}, "groups": [{"id", "name", "weekday", "weekend",
 * "apps": [...], "category": "game"}], "bedtime": {"from": "20:30", "to": "07:00", "days": "all" | "weekdays" |
 * "weekends"}, "notCounted": [...]}}. Minutes left out (or null) mean no limit. A group takes its listed apps and, with a
 * category, every app Android files under it.
 */
final class LocalRules {
    static final String ALL = "all";
    static final String ALL_NAME = "All screen time";
    static final String BEDTIME = "bedtime";
    /** Who set a lock, in the document's {@code by}: Hearth's own rules. */
    static final String BY = "hearth";
    private static final DateTimeFormatter ISO = DateTimeFormatter.ISO_OFFSET_DATE_TIME;

    private LocalRules() {
    }

    /**
     * The person's document part for today at {@code now}, in the household's zone.
     *
     * @param usageMs     what the kid used today, package -> milliseconds (every TV and phone of theirs, summed)
     * @param installed   the apps a category group can take (this TV's)
     * @param categoryOf  package -> Android's category name (game, video, social, audio, ...), or null
     */
    static JSONObject document(JSONObject rules, Map<String, Long> usageMs, Collection<String> installed,
            Function<String, String> categoryOf, ZonedDateTime now) throws JSONException {
        JSONObject out = new JSONObject();
        JSONArray groups = new JSONArray();
        boolean weekend = isWeekend(now.getDayOfWeek());
        Set<String> notCounted = strings(rules.optJSONArray("notCounted"));

        JSONObject all = rules.optJSONObject("all");
        Integer allLimit = all != null ? minutes(all, weekend) : null;
        if (allLimit != null) {
            long used = 0;
            for (Map.Entry<String, Long> app : usageMs.entrySet()) {
                if (!notCounted.contains(app.getKey()) && app.getValue() != null) used += app.getValue();
            }
            JSONObject group = new JSONObject().put("id", ALL).put("name", ALL_NAME)
                    .put("minutes_left", left(allLimit, used)).put("apps", new JSONArray());
            if (!notCounted.isEmpty()) group.put("except", new JSONArray(sorted(notCounted)));
            groups.put(group);
        }

        JSONArray rulesGroups = rules.optJSONArray("groups");
        for (int i = 0; rulesGroups != null && i < rulesGroups.length(); i++) {
            JSONObject rule = rulesGroups.optJSONObject(i);
            if (rule == null) continue;
            String id = rule.optString("id", "");
            if (id.isEmpty() || ALL.equals(id)) continue;
            Integer limit = minutes(rule, weekend);
            if (limit == null) continue;
            Set<String> apps = members(rule, usageMs.keySet(), installed, categoryOf);
            long used = 0;
            for (String app : apps) {
                Long ms = usageMs.get(app);
                if (ms != null) used += ms;
            }
            String name = rule.optString("name", "");
            groups.put(new JSONObject().put("id", id).put("name", name.trim().isEmpty() ? id : name)
                    .put("minutes_left", left(limit, used)).put("apps", new JSONArray(sorted(apps))));
        }
        out.put("groups", groups);

        JSONObject bedtime = rules.optJSONObject("bedtime");
        ZonedDateTime[] window = bedtime != null ? bedtimeAround(bedtime, now) : null;
        boolean inBedtime = window != null && !now.isBefore(window[0]) && now.isBefore(window[1]);
        out.put("locked", inBedtime);
        if (inBedtime) {
            out.put("lock", new JSONObject().put("by", new JSONArray().put(BY)).put("kind", BEDTIME)
                    .put("kinds", new JSONArray().put(BEDTIME)).put("until", ISO.format(window[1])));
        } else {
            ZonedDateTime next = bedtime != null ? nextBedtime(bedtime, now) : null;
            if (next != null) {
                out.put("next_lock", new JSONObject().put("at", ISO.format(next)).put("by", BY).put("kind", BEDTIME));
            }
        }
        return out;
    }

    /** Saturday and Sunday. */
    static boolean isWeekend(DayOfWeek day) {
        return day == DayOfWeek.SATURDAY || day == DayOfWeek.SUNDAY;
    }

    /** A rule's minutes for today (weekday or weekend); null: no limit. Negative counts as none left. */
    static Integer minutes(JSONObject rule, boolean weekend) {
        String key = weekend ? "weekend" : "weekday";
        if (!rule.has(key) || rule.isNull(key)) return null;
        return Math.max(0, rule.optInt(key, 0));
    }

    /** Whole minutes left of a limit after {@code usedMs}: used time is counted up to the minute it's in. */
    static int left(int limitMinutes, long usedMs) {
        long usedMinutes = (usedMs + 59_999) / 60_000;
        return (int) Math.max(0, limitMinutes - usedMinutes);
    }

    /** The apps a group holds: its list, and with a category every known app Android files under it. */
    static Set<String> members(JSONObject rule, Collection<String> used, Collection<String> installed,
            Function<String, String> categoryOf) {
        Set<String> apps = strings(rule.optJSONArray("apps"));
        String category = rule.optString("category", "");
        if (!category.isEmpty() && categoryOf != null) {
            for (Collection<String> known : List.of(used, installed)) {
                for (String app : known) {
                    if (category.equals(categoryOf.apply(app))) apps.add(app);
                }
            }
        }
        return apps;
    }

    /**
     * Tonight's (or the one still running from last night) bedtime as [start, end], or null when the rule has no
     * bedtime that applies around {@code now}. A window past midnight ends the next day, and its days name the morning it
     * ends on: "weekdays" are school nights (Sunday to Thursday evening), "weekends" Friday and Saturday evening.
     */
    static ZonedDateTime[] bedtimeAround(JSONObject bedtime, ZonedDateTime now) {
        LocalTime from = time(bedtime.optString("from", null));
        LocalTime to = time(bedtime.optString("to", null));
        if (from == null || to == null || from.equals(to)) return null;
        String days = bedtime.optString("days", "all");
        // The window that started yesterday may still run (20:30 to 07:00); then today's
        for (int back = 1; back >= 0; back--) {
            ZonedDateTime day = now.minusDays(back);
            ZonedDateTime start = day.with(from);
            ZonedDateTime end = to.isAfter(from) ? day.with(to) : day.plusDays(1).with(to);
            if (!applies(days, end.getDayOfWeek())) continue;
            if (!now.isBefore(end)) continue;
            // Yesterday's only while it still runs; today's whether it runs now or comes later
            if (back == 0 || !now.isBefore(start)) return new ZonedDateTime[]{start, end};
        }
        return null;
    }

    /** The next bedtime start after {@code now} within the coming day, or null. */
    static ZonedDateTime nextBedtime(JSONObject bedtime, ZonedDateTime now) {
        LocalTime from = time(bedtime.optString("from", null));
        LocalTime to = time(bedtime.optString("to", null));
        if (from == null || to == null || from.equals(to)) return null;
        String days = bedtime.optString("days", "all");
        for (int ahead = 0; ahead <= 1; ahead++) {
            ZonedDateTime day = now.plusDays(ahead);
            ZonedDateTime start = day.with(from);
            ZonedDateTime end = to.isAfter(from) ? day.with(to) : day.plusDays(1).with(to);
            if (applies(days, end.getDayOfWeek()) && start.isAfter(now)) return start;
        }
        return null;
    }

    static boolean applies(String days, DayOfWeek day) {
        switch (days) {
            case "weekdays":
                return !isWeekend(day);
            case "weekends":
                return isWeekend(day);
            default:
                return true;
        }
    }

    private static LocalTime time(String text) {
        if (text == null) return null;
        try {
            return LocalTime.parse(text);
        } catch (DateTimeParseException e) {
            return null;
        }
    }

    private static Set<String> strings(JSONArray array) {
        Set<String> out = new HashSet<>();
        for (int i = 0; array != null && i < array.length(); i++) {
            String value = array.optString(i, "");
            if (!value.isEmpty()) out.add(value);
        }
        return out;
    }

    private static List<String> sorted(Collection<String> values) {
        List<String> out = new ArrayList<>(values);
        java.util.Collections.sort(out);
        return out;
    }
}
