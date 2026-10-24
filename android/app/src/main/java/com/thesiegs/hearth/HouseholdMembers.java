package com.thesiegs.hearth;

import org.json.JSONException;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.Collection;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Which TVs are in the household, for the Household page (docs/household-sync.md). Each TV writes an entry about itself
 * ({@link #KIND}, item: its TV id, value: its name), so every TV learns of the others through sync, even ones it has
 * never been on with at the same time; a TV that leaves deletes its entry. A TV this one has synced with is a member too
 * (one too old to write its entry), and one heard on the network right now is shown as on. Nothing here knows about
 * Android, so it can be tested alone.
 */
final class HouseholdMembers {
    /** The entry kind a TV writes about itself. Older TVs keep it and pass it on, unapplied, like any unknown kind. */
    static final String KIND = "tv";
    /** A TV's own entry is written again after this long, so its time shows when it was last on. */
    static final long REFRESH_MS = 24L * 60 * 60 * 1000;
    private static final int CLOCK_COUNTER_BITS = 16;

    /** One TV of the household. */
    static final class Member {
        final String tvId;
        /** What the TV is called; null when it never said. */
        final String name;
        final boolean self;
        /** Heard on the network now. */
        final boolean online;
        /** When it was last known to be on (ms), 0 when never. */
        final long lastSeen;

        Member(String tvId, String name, boolean self, boolean online, long lastSeen) {
            this.tvId = tvId;
            this.name = name;
            this.self = self;
            this.online = online;
            this.lastSeen = lastSeen;
        }
    }

    /** A TV this one synced with: what it was called and when. */
    static final class Seen {
        final String name;
        final long at;

        Seen(String name, long at) {
            this.name = name;
            this.at = at;
        }
    }

    private HouseholdMembers() {
    }

    /** An entry's value for a TV called {@code name}. */
    static String value(String name) {
        try {
            return new JSONObject().put("name", name == null ? "" : name).toString();
        } catch (JSONException e) {
            throw new IllegalStateException(e);
        }
    }

    /** The name an entry's value carries, or null. */
    static String nameOf(String value) {
        try {
            String name = new JSONObject(value).optString("name", "").trim();
            return name.isEmpty() ? null : name;
        } catch (JSONException e) {
            return null;
        }
    }

    /** Whether this TV's own entry needs writing: missing, another name, or older than {@link #REFRESH_MS}. */
    static boolean selfNeedsWrite(HouseholdLog log, String tvId, String name, long nowMs) {
        HouseholdEntry have = log.get(KIND, HouseholdBridge.SHARED, tvId);
        if (have == null) return true;
        String had = nameOf(have.value);
        if (had == null ? name != null : !had.equals(name)) return true;
        return nowMs - wallClock(have) >= REFRESH_MS;
    }

    /**
     * The household's TVs, this one first, then those on now, then by name. {@code online} is the TVs heard on the
     * network now (id to the name they announce, which may be null).
     */
    static List<Member> list(Collection<HouseholdEntry> entries, Map<String, Seen> seen, Map<String, String> online,
            String selfId, String selfName, long nowMs) {
        Map<String, String> names = new LinkedHashMap<>();
        Map<String, Long> times = new LinkedHashMap<>();
        for (HouseholdEntry entry : entries) {
            if (!KIND.equals(entry.kind) || entry.deleted || entry.item.isEmpty()) continue;
            names.put(entry.item, nameOf(entry.value));
            times.put(entry.item, wallClock(entry));
        }
        for (Map.Entry<String, Seen> s : seen.entrySet()) {
            if (!names.containsKey(s.getKey()) || names.get(s.getKey()) == null) names.put(s.getKey(), s.getValue().name);
            times.merge(s.getKey(), s.getValue().at, Math::max);
        }
        names.remove(selfId);
        times.remove(selfId);
        List<Member> out = new ArrayList<>();
        out.add(new Member(selfId, selfName, true, true, nowMs));
        List<Member> others = new ArrayList<>();
        for (Map.Entry<String, String> n : names.entrySet()) {
            String id = n.getKey();
            boolean on = online.containsKey(id);
            String name = n.getValue() != null ? n.getValue() : online.get(id);
            others.add(new Member(id, name, false, on, on ? nowMs : times.getOrDefault(id, 0L)));
        }
        others.sort(Comparator.<Member, Boolean>comparing(m -> !m.online)
                .thenComparing(m -> m.name == null ? "￿" : m.name.toLowerCase(java.util.Locale.ROOT))
                .thenComparing(m -> m.tvId));
        out.addAll(others);
        return out;
    }

    /**
     * The households heard on the network, each as the names of its TVs heard (a TV that gave no name counts, as null),
     * the largest first. {@code ownHousehold} (null when none) is left out: it isn't one to join.
     */
    static List<List<String>> nearby(Collection<HouseholdNet.Heard> heard, String ownHousehold) {
        Map<String, List<String>> byHousehold = new LinkedHashMap<>();
        for (HouseholdNet.Heard h : heard) {
            if (h.householdId == null || h.householdId.equals(ownHousehold)) continue;
            byHousehold.computeIfAbsent(h.householdId, k -> new ArrayList<>()).add(h.name);
        }
        List<List<String>> out = new ArrayList<>(byHousehold.values());
        out.sort((a, b) -> b.size() - a.size());
        return out;
    }

    private static long wallClock(HouseholdEntry entry) {
        return entry.clock >> CLOCK_COUNTER_BITS;
    }
}
