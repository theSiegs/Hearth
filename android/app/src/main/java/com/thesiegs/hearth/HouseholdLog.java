package com.thesiegs.hearth;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.Iterator;
import java.util.List;
import java.util.Map;

/**
 * This TV's copy of the household's entries (docs/household-sync.md): one entry per id, the newest write winning
 * (HouseholdEntry.beats), plus a version vector of the highest {@code seq} seen from each TV, which is how two TVs find
 * what the other lacks. In memory; the caller saves and restores it with {@link #all} and {@link #merge}. Not thread safe.
 * One exception to newest-wins: removing a TV from the member list (a delete of a {@link HouseholdMembers#KIND} entry)
 * is final. It beats any write for that TV, later ones included, nothing written after it replaces it, and it is never
 * purged.
 */
final class HouseholdLog {
    /** Deletes are remembered this long, so a TV that was off for less than this can't bring a value back. */
    static final long TOMBSTONE_MS = 90L * 24 * 60 * 60 * 1000;
    /** The clock is milliseconds in the high bits and a counter for same-millisecond writes in the low 16. */
    private static final int COUNTER_BITS = 16;
    /** A clock further ahead of this TV's than this is refused (a TV with a broken clock can't pin an entry forever). */
    static final long MAX_AHEAD_MS = 24L * 60 * 60 * 1000;

    private final String tv;
    private final Map<String, HouseholdEntry> entries = new HashMap<>();
    private final Map<String, Long> vector = new HashMap<>();
    private long lastClock;

    HouseholdLog(String tv) {
        if (tv == null || tv.isEmpty()) throw new IllegalArgumentException("tv");
        this.tv = tv;
    }

    /** Writes a value on this TV; returns the entry to send to the others. */
    HouseholdEntry put(String kind, String profile, String item, String value, long nowMs) {
        return write(kind, profile, item, value, nowMs, false);
    }

    /** Deletes a value on this TV (a tombstone); returns the entry to send. */
    HouseholdEntry delete(String kind, String profile, String item, long nowMs) {
        return write(kind, profile, item, "", nowMs, true);
    }

    private static String id(String kind, String profile, String item) {
        return kind + "|" + HouseholdEntry.normalize(profile) + "|" + (item == null ? "" : item);
    }

    /** Null when the write would undo a final delete (see the class comment): nothing is written. */
    private HouseholdEntry write(String kind, String profile, String item, String value, long nowMs, boolean deleted) {
        HouseholdEntry had = entries.get(id(kind, profile, item));
        if (had != null && isFinal(had)) return null;
        long clock = Math.max(lastClock + 1, nowMs << COUNTER_BITS);
        HouseholdEntry existing = entries.get(id(kind, profile, item));
        if (existing != null && existing.clock >= clock) clock = existing.clock + 1;
        lastClock = clock;
        long seq = vector.getOrDefault(tv, 0L) + 1;
        HouseholdEntry entry = new HouseholdEntry(kind, profile, item, value, clock, tv, seq, deleted);
        entries.put(entry.id(), entry);
        vector.put(tv, seq);
        return entry;
    }

    /**
     * Takes an entry from another TV. Returns true if it changed what this TV holds (it beat the entry here, or there
     * was none). Counts it in the version vector, so it isn't asked for again. Refused (false, not counted) when it
     * claims to come from this TV with a sequence this TV never made, or its clock is too far ahead.
     */
    boolean merge(HouseholdEntry incoming, long nowMs) {
        if (incoming == null) return false;
        if (incoming.tv.equals(tv) && incoming.seq > vector.getOrDefault(tv, 0L)) return false;
        if ((incoming.clock >> COUNTER_BITS) > nowMs + MAX_AHEAD_MS) return false;
        if (incoming.seq > vector.getOrDefault(incoming.tv, 0L)) vector.put(incoming.tv, incoming.seq);
        lastClock = Math.max(lastClock, incoming.clock);
        HouseholdEntry existing = entries.get(incoming.id());
        if (existing != null && isFinal(existing)) return false;
        if (existing != null && !isFinal(incoming) && !incoming.beats(existing)) return false;
        entries.put(incoming.id(), incoming);
        return true;
    }

    /**
     * Puts back what {@link #all} and {@link #vector} gave earlier (saved and loaded by the caller). Replaces what is
     * held. An entry that isn't well formed is skipped.
     */
    void restore(List<HouseholdEntry> saved, Map<String, Long> savedVector) {
        entries.clear();
        vector.clear();
        lastClock = 0;
        for (HouseholdEntry entry : saved) {
            if (entry == null) continue;
            entries.put(entry.id(), entry);
            lastClock = Math.max(lastClock, entry.clock);
        }
        for (Map.Entry<String, Long> seen : savedVector.entrySet()) vector.put(seen.getKey(), seen.getValue());
    }

    /** The live value, or null if there is none or it was deleted. */
    HouseholdEntry get(String kind, String profile, String item) {
        HouseholdEntry entry = entries.get(id(kind, profile, item));
        return entry == null || entry.deleted ? null : entry;
    }

    /** Whether this id holds a final delete: a TV removed from the member list. */
    boolean isRemoved(String kind, String profile, String item) {
        HouseholdEntry entry = entries.get(id(kind, profile, item));
        return entry != null && isFinal(entry);
    }

    private static boolean isFinal(HouseholdEntry entry) {
        return entry.deleted && HouseholdMembers.KIND.equals(entry.kind);
    }

    /** Whether any entry for this id is held, a delete included. */
    boolean hasEntry(String kind, String profile, String item) {
        return entries.containsKey(id(kind, profile, item));
    }

    /** Every entry held, deletes included. */
    List<HouseholdEntry> all() {
        return new ArrayList<>(entries.values());
    }

    /** What this TV has seen from each TV: the highest sequence. */
    Map<String, Long> vector() {
        return new HashMap<>(vector);
    }

    /** The entries a TV with version vector {@code theirs} may lack: those written after what it has seen of their TV. */
    List<HouseholdEntry> missingFrom(Map<String, Long> theirs) {
        List<HouseholdEntry> out = new ArrayList<>();
        for (HouseholdEntry entry : entries.values()) {
            Long seen = theirs.get(entry.tv);
            if (seen == null || entry.seq > seen) out.add(entry);
        }
        return out;
    }

    /** Forgets deletes older than {@link #TOMBSTONE_MS}; returns how many. */
    int purge(long nowMs) {
        int removed = 0;
        for (Iterator<HouseholdEntry> it = entries.values().iterator(); it.hasNext();) {
            HouseholdEntry entry = it.next();
            if (entry.deleted && !isFinal(entry) && (entry.clock >> COUNTER_BITS) < nowMs - TOMBSTONE_MS) {
                it.remove();
                removed++;
            }
        }
        return removed;
    }
}
