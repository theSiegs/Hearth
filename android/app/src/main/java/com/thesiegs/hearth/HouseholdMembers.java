package com.thesiegs.hearth;

import org.json.JSONException;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Base64;
import java.util.Collection;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Who is in the household (docs/household-sync.md, "Members"). The member list is entries of {@link #KIND}, one per TV
 * (item: its TV id; value: its name, its public key, and the member that added it). A TV syncs only with TVs whose key
 * is on its list. Removing a TV deletes its entry, and that delete is final: it beats any write for the same TV and is
 * never purged (HouseholdLog), so a removed TV comes back only by joining again with a new key. Nothing here knows about
 * Android, so it can be tested alone.
 */
final class HouseholdMembers {
    static final String KIND = "member";
    /** A TV's own entry is written again after this long, so its time shows when it was last on. */
    static final long REFRESH_MS = 24L * 60 * 60 * 1000;
    private static final int CLOCK_COUNTER_BITS = 16;

    /** Where a TV stands on this TV's list. */
    enum Standing { MEMBER, REMOVED, UNKNOWN }

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

    /** A member entry's value: the TV's name, its public key, and the TV that added it. */
    static String value(String name, byte[] publicKey, String addedBy) {
        try {
            return new JSONObject().put("name", name == null ? "" : name)
                    .put("key", Base64.getEncoder().encodeToString(publicKey))
                    .put("by", addedBy == null ? "" : addedBy).toString();
        } catch (JSONException e) {
            throw new IllegalStateException(e);
        }
    }

    /** The name a member entry carries, or null. */
    static String nameOf(String value) {
        try {
            String name = new JSONObject(value).optString("name", "").trim();
            return name.isEmpty() ? null : name;
        } catch (JSONException e) {
            return null;
        }
    }

    /** The TV that added the member, or {@code otherwise} when the entry doesn't say. */
    static String byOf(String value, String otherwise) {
        try {
            String by = new JSONObject(value).optString("by", "");
            return by.isEmpty() ? otherwise : by;
        } catch (JSONException e) {
            return otherwise;
        }
    }

    /** The public key a member entry carries, or null when it has none or it isn't valid base64. */
    static byte[] keyOf(String value) {
        try {
            String key = new JSONObject(value).optString("key", "");
            return key.isEmpty() ? null : Base64.getDecoder().decode(key);
        } catch (JSONException | IllegalArgumentException e) {
            return null;
        }
    }

    /**
     * Where {@code tvId} stands on {@code log}'s list. A member entry only counts when its key is the one the id was
     * made from, so an entry can't give an id to another key.
     */
    static Standing standing(HouseholdLog log, String tvId) {
        if (log.isRemoved(KIND, HouseholdBridge.SHARED, tvId)) return Standing.REMOVED;
        return keyFor(log, tvId) != null ? Standing.MEMBER : Standing.UNKNOWN;
    }

    /** The listed public key of {@code tvId}, or null when it isn't a member. */
    static byte[] keyFor(HouseholdLog log, String tvId) {
        HouseholdEntry entry = log.get(KIND, HouseholdBridge.SHARED, tvId);
        if (entry == null) return null;
        byte[] key = keyOf(entry.value);
        return key != null && HouseholdIdentity.tvIdOf(key).equals(tvId) ? key : null;
    }

    /** Whether this TV's own entry needs writing: missing, another name or key, or older than {@link #REFRESH_MS}. */
    static boolean selfNeedsWrite(HouseholdLog log, String tvId, String name, byte[] publicKey, long nowMs) {
        if (log.isRemoved(KIND, HouseholdBridge.SHARED, tvId)) return false;
        HouseholdEntry have = log.get(KIND, HouseholdBridge.SHARED, tvId);
        if (have == null) return true;
        String had = nameOf(have.value);
        if (had == null ? name != null : !had.equals(name)) return true;
        if (!Arrays.equals(keyOf(have.value), publicKey)) return true;
        return nowMs - wallClock(have) >= REFRESH_MS;
    }

    /**
     * The household's TVs, this one first, then those on now, then by name. {@code online} is the TVs heard on the
     * network now (id to the name they announce, which may be null); {@code seen} adds when this TV last synced with
     * each. A removed TV isn't listed.
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
            if (!names.containsKey(s.getKey())) continue;
            if (names.get(s.getKey()) == null) names.put(s.getKey(), s.getValue().name);
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
