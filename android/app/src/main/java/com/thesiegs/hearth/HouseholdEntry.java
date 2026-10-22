package com.thesiegs.hearth;

import org.json.JSONException;
import org.json.JSONObject;

import java.util.Locale;

/**
 * One value that follows a person from TV to TV (docs/household-sync.md): what it is ({@code kind}, the person's
 * {@code profile} name and an {@code item} within the kind, such as a streaming app), its {@code value}, and what
 * decides which write wins: the hybrid {@code clock}, then the writing TV's id. A delete is an entry with
 * {@code deleted} set, so a TV that was off can't bring the value back. Immutable.
 */
final class HouseholdEntry {
    final String kind;
    final String profile;
    final String item;
    final String value;
    final long clock;
    final String tv;
    /** The writing TV's own counter: what a peer's version vector counts. */
    final long seq;
    final boolean deleted;

    HouseholdEntry(String kind, String profile, String item, String value, long clock, String tv, long seq,
            boolean deleted) {
        this.kind = kind;
        this.profile = normalize(profile);
        this.item = item == null ? "" : item;
        this.value = value == null ? "" : value;
        this.clock = clock;
        this.tv = tv;
        this.seq = seq;
        this.deleted = deleted;
    }

    /** A profile name as sync compares it: trimmed, lower case (names are unique household-wide that way). */
    static String normalize(String name) {
        return name == null ? "" : name.trim().toLowerCase(Locale.ROOT);
    }

    /** What the entry is about; a newer entry with the same id replaces this one. */
    String id() {
        return kind + "|" + profile + "|" + item;
    }

    /** Whether this write beats {@code other}'s for the same id: the later clock, and on a tie the lower TV id. */
    boolean beats(HouseholdEntry other) {
        if (clock != other.clock) return clock > other.clock;
        return tv.compareTo(other.tv) < 0;
    }

    String toJson() {
        try {
            return new JSONObject().put("k", kind).put("p", profile).put("i", item).put("v", value).put("c", clock)
                    .put("t", tv).put("s", seq).put("d", deleted).toString();
        } catch (JSONException e) {
            throw new IllegalStateException(e);
        }
    }

    /** The entry in {@code json}, or null if it isn't one (a missing field, the wrong type, an empty kind or TV). */
    static HouseholdEntry fromJson(String json) {
        try {
            JSONObject o = new JSONObject(json);
            String kind = o.getString("k");
            String tv = o.getString("t");
            if (kind.isEmpty() || tv.isEmpty()) return null;
            return new HouseholdEntry(kind, o.getString("p"), o.getString("i"), o.getString("v"), o.getLong("c"), tv,
                    o.getLong("s"), o.getBoolean("d"));
        } catch (JSONException | RuntimeException e) {
            return null;
        }
    }
}
