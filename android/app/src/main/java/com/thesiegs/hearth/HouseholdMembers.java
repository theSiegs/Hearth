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
        return value(name, publicKey, addedBy, false);
    }

    /**
     * As {@link #value(String, byte[], String)}; {@code signing}: the TV signs its member, removal and Parent PIN
     * entries (it runs a build that does), so an unsigned one in its name is refused.
     */
    static String value(String name, byte[] publicKey, String addedBy, boolean signing) {
        try {
            JSONObject o = new JSONObject().put("name", name == null ? "" : name)
                    .put("key", Base64.getEncoder().encodeToString(publicKey))
                    .put("by", addedBy == null ? "" : addedBy);
            if (signing) o.put("s", true);
            return o.toString();
        } catch (JSONException e) {
            throw new IllegalStateException(e);
        }
    }

    /** Whether a member entry says its TV signs its entries. */
    static boolean signingOf(String value) {
        try {
            return new JSONObject(value).optBoolean("s", false);
        } catch (JSONException e) {
            return false;
        }
    }

    /** The kinds whose entries carry their writer's signature: the member list (removals too) and the Parent PIN. */
    static boolean signs(String kind) {
        return KIND.equals(kind) || HouseholdBridge.PARENT_PIN.equals(kind);
    }

    /**
     * Whether an entry from another TV may be taken (docs/household-sync.md, "What's checked"). Only the kinds that
     * carry a signature ({@link #signs}) are checked: their writer must be on this TV's member list now (a TV not
     * listed, or removed, writes nothing for the household), and the entry signed with that writer's listed key. An
     * entry without a signature is taken only from a TV whose entry doesn't say it signs (one on a build from before
     * signing), and never says so itself. A member entry must also hold a key its id was made from; one for another TV
     * (an admission) must name its writer as the TV that added it; and one can't take back that a TV signs.
     */
    static boolean accepts(HouseholdLog log, HouseholdEntry e) {
        return accepts(log, e, false);
    }

    /**
     * As {@link #accepts(HouseholdLog, HouseholdEntry)}; {@code fromInviter}: the entry came from the TV that let this
     * one join, in their first exchange, which also takes a TV's own entry for a TV this one doesn't know yet
     * ({@link #introduces}). A TV writes its own entry again when renamed and once a day, and that replaces the entry of
     * the member that added it, so a TV that joins later would otherwise never list it (nor sync with it). It also
     * takes the inviter's own entry for a TV the inviter didn't add (the one that let the inviter in).
     */
    static boolean accepts(HouseholdLog log, HouseholdEntry e, boolean fromInviter) {
        return refusal(log, e, fromInviter) == null;
    }

    /** Why {@link #accepts(HouseholdLog, HouseholdEntry, boolean)} refuses {@code e}, for the log; null when it takes it. */
    static String refusal(HouseholdLog log, HouseholdEntry e, boolean fromInviter) {
        if (!signs(e.kind)) return null;
        byte[] writerKey = keyFor(log, e.tv);
        boolean writerSigns;
        if (writerKey != null) {
            writerSigns = signingOf(log.get(KIND, HouseholdBridge.SHARED, e.tv).value);
        } else if (fromInviter && introduces(log, e)) {
            writerKey = keyOf(e.value);
            writerSigns = true;
        } else {
            if (!fromInviter) return "writer not listed";
            boolean own = KIND.equals(e.kind) && e.item.equals(e.tv);
            byte[] carried = own ? keyOf(e.value) : null;
            return "writer not listed (own " + own + ", signed " + !e.sig.isEmpty() + ", says it signs "
                    + (own && signingOf(e.value)) + ", held " + log.hasEntry(KIND, HouseholdBridge.SHARED, e.item)
                    + ", key " + (carried != null && HouseholdIdentity.tvIdOf(carried).equals(e.item)) + ")";
        }
        if (e.sig.isEmpty()) {
            if (writerSigns) return "unsigned, writer signs";
            if (KIND.equals(e.kind) && !e.deleted && signingOf(e.value)) return "unsigned, says it signs";
        } else {
            byte[] sig;
            try {
                sig = Base64.getDecoder().decode(e.sig);
            } catch (IllegalArgumentException bad) {
                return "bad signature";
            }
            if (!HouseholdIdentity.verify(writerKey, e.signedBytes(), sig)) return "bad signature";
        }
        if (!KIND.equals(e.kind) || e.deleted) return null;
        if (!HouseholdBridge.SHARED.equals(e.profile)) return "not shared";
        byte[] key = keyOf(e.value);
        if (key == null || !HouseholdIdentity.tvIdOf(key).equals(e.item)) return "key not the TV's";
        // From the TV that let this one in, also its copy of a TV it didn't add: the one it was let in by, which it
        // listed when it joined, newer than that TV's own entry until the day's refresh
        if (!fromInviter && !e.item.equals(e.tv) && !e.tv.equals(byOf(e.value, ""))) return "writer didn't add it";
        HouseholdEntry had = log.get(KIND, HouseholdBridge.SHARED, e.item);
        return had == null || !signingOf(had.value) || signingOf(e.value) ? null : "takes back signing";
    }

    /**
     * Whether {@code e} is a TV's own member entry for a TV {@code log} holds nothing of (not listed, not removed):
     * written by that TV, saying it signs, and holding the key its id was made from, which the caller checks its
     * signature with. Taken only from the TV that let this one join, which this TV trusts with the whole household.
     */
    static boolean introduces(HouseholdLog log, HouseholdEntry e) {
        if (!KIND.equals(e.kind) || e.deleted || !HouseholdBridge.SHARED.equals(e.profile)) return false;
        if (!e.item.equals(e.tv) || e.sig.isEmpty() || !signingOf(e.value)) return false;
        if (log.hasEntry(KIND, HouseholdBridge.SHARED, e.item)) return false;
        byte[] key = keyOf(e.value);
        return key != null && HouseholdIdentity.tvIdOf(key).equals(e.item);
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

    /**
     * Whether this TV's own entry needs writing: missing, another name or key, not yet saying this TV signs, or older
     * than {@link #REFRESH_MS}.
     */
    static boolean selfNeedsWrite(HouseholdLog log, String tvId, String name, byte[] publicKey, long nowMs) {
        if (log.isRemoved(KIND, HouseholdBridge.SHARED, tvId)) return false;
        HouseholdEntry have = log.get(KIND, HouseholdBridge.SHARED, tvId);
        if (have == null || !signingOf(have.value)) return true;
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
