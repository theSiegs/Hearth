package com.thesiegs.hearth;

import org.json.JSONException;
import org.json.JSONObject;

import java.util.HashMap;
import java.util.Iterator;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;

/**
 * A kid's minutes on each of the household's TVs ({@link HouseholdBridge#USAGE} entries), so Hearth's own rules count a
 * kid's time on every TV, not just this one. Pure.
 */
final class HouseholdUsage {
    private HouseholdUsage() {
    }

    /** The entry's item for one TV's minutes on one day. */
    static String item(String tvId, String day) {
        return "tv:" + tvId + ":" + day;
    }

    /** The entry's value: package -> milliseconds, in a steady order so an unchanged count isn't written again. */
    static String valueOf(Map<String, Long> ms) {
        return new JSONObject(new TreeMap<>(ms)).toString();
    }

    /**
     * The other TVs' minutes on {@code day}, summed per profile of this TV: profile key -> package -> milliseconds.
     * {@code profiles} is this TV's person id -> profile key; this TV's own entries and other days are left out.
     */
    static Map<String, Map<String, Long>> others(List<HouseholdEntry> entries, String selfTvId, String day,
            Map<String, String> profiles) {
        Map<String, Map<String, Long>> out = new HashMap<>();
        String own = item(selfTvId, day);
        String suffix = ":" + day;
        for (HouseholdEntry entry : entries) {
            if (!HouseholdBridge.USAGE.equals(entry.kind) || entry.deleted) continue;
            if (!entry.item.startsWith("tv:") || !entry.item.endsWith(suffix) || entry.item.equals(own)) continue;
            String key = profiles.get(entry.profile);
            if (key == null) continue;
            JSONObject value;
            try {
                value = new JSONObject(entry.value);
            } catch (JSONException e) {
                continue;
            }
            Map<String, Long> sum = out.computeIfAbsent(key, k -> new HashMap<>());
            for (Iterator<String> apps = value.keys(); apps.hasNext(); ) {
                String app = apps.next();
                long ms = value.optLong(app, 0);
                if (ms > 0) sum.merge(app, ms, Long::sum);
            }
        }
        return out;
    }
}
