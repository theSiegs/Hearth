package com.thesiegs.hearth;

import org.json.JSONException;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.List;

/**
 * Continue Watching across the household (docs/household-sync.md, "Continue Watching"): what each person played and
 * the Watch Next entries kept for them (WatchHistory), as {@link HouseholdBridge#WATCH} entries. One entry per person,
 * app and show or film (the item is the WatchHistory kind, the app and WatchHistory's own item), so the newest play of a
 * title wins everywhere, and one played to its end is finished everywhere. Taking a title out of Continue Watching is a
 * delete, so it goes from every TV. The rules are here, pure; Household runs them.
 */
final class HouseholdWatch {
    /** At most this many of a person's newest entries go out (Continue Watching shows far fewer). */
    static final int SENT_PER_PERSON = 40;
    /** Longest title, subtitle, app name or item taken from another TV. */
    static final int MAX_TEXT = 500;
    /** Longest kept Watch Next entry taken (its JSON, the deep link included). */
    static final int MAX_ROW = 8 * 1024;
    /** A play claimed further ahead of this TV's clock than this isn't taken. */
    static final long MAX_AHEAD_MS = 24L * 60 * 60 * 1000;

    private HouseholdWatch() {
    }

    /** What another TV had for one of a person's titles. */
    static final class Card {
        final String kind;
        final String packageName;
        final String item;
        final String title;
        final String subtitle;
        final long duration;
        final long position;
        final long lastAt;
        /** A kept Watch Next entry as Flutter gets it (JSON, with its deep link); null for a played entry. */
        final String row;

        Card(String kind, String packageName, String item, String title, String subtitle, long duration, long position,
                long lastAt, String row) {
            this.kind = kind;
            this.packageName = packageName;
            this.item = item;
            this.title = title;
            this.subtitle = subtitle;
            this.duration = duration;
            this.position = position;
            this.lastAt = lastAt;
            this.row = row;
        }
    }

    /** The household item for one of WatchHistory's entries: {@code kind|package|item}. */
    static String itemOf(String kind, String packageName, String item) {
        return kind + "|" + packageName + "|" + item;
    }

    /** {kind, package, item} from a household item, or null if it isn't one. */
    static String[] partsOf(String householdItem) {
        if (householdItem == null) return null;
        int first = householdItem.indexOf('|');
        if (first <= 0) return null;
        int second = householdItem.indexOf('|', first + 1);
        if (second <= first + 1 || second == householdItem.length() - 1) return null;
        String kind = householdItem.substring(0, first);
        if (!WatchHistory.PLAYED.equals(kind) && !WatchHistory.KEPT.equals(kind)) return null;
        String pkg = householdItem.substring(first + 1, second);
        String item = householdItem.substring(second + 1);
        if (!validPackage(pkg) || item.length() > MAX_TEXT) return null;
        return new String[]{kind, pkg, item};
    }

    static boolean validPackage(String pkg) {
        return pkg != null && !pkg.isEmpty() && pkg.length() <= 255 && pkg.matches("[A-Za-z0-9_]+(\\.[A-Za-z0-9_]+)+");
    }

    /** The entry's value: what it says about the title, without the profile (that's the entry's person). */
    static String valueOf(WatchHistory.Entry e) {
        try {
            JSONObject o = new JSONObject().put("t", e.title == null ? "" : e.title).put("d", e.duration)
                    .put("p", e.position).put("at", e.lastAt);
            if (e.subtitle != null) o.put("s", e.subtitle);
            if (WatchHistory.KEPT.equals(e.kind) && e.row != null) o.put("row", e.row);
            return o.toString();
        } catch (JSONException ex) {
            throw new IllegalStateException(ex);
        }
    }

    /** The title another TV had, or null when the entry isn't a well-formed live one. */
    static Card cardOf(HouseholdEntry entry) {
        if (entry == null || entry.deleted || !HouseholdBridge.WATCH.equals(entry.kind)) return null;
        String[] parts = partsOf(entry.item);
        if (parts == null) return null;
        try {
            JSONObject o = new JSONObject(entry.value);
            String title = o.optString("t", "");
            String subtitle = o.has("s") ? o.optString("s", null) : null;
            long duration = o.optLong("d", 0), position = o.optLong("p", 0), at = o.optLong("at", 0);
            if (title.length() > MAX_TEXT || (subtitle != null && subtitle.length() > MAX_TEXT)) return null;
            if (duration < 0 || position < 0 || at <= 0) return null;
            String row = null;
            if (WatchHistory.KEPT.equals(parts[0])) {
                row = o.optString("row", "");
                if (row.isEmpty() || row.length() > MAX_ROW || !keptRowFor(row, parts[1])) return null;
            } else if (title.isEmpty()) {
                return null;
            }
            return new Card(parts[0], parts[1], parts[2], title, subtitle, duration, position, at, row);
        } catch (JSONException e) {
            return null;
        }
    }

    /** A kept row must be a Watch Next entry of the app it's filed under (a card can't open another app). */
    private static boolean keptRowFor(String row, String packageName) {
        try {
            JSONObject o = new JSONObject(row);
            return packageName.equals(o.optString("packageName", ""));
        } catch (JSONException e) {
            return false;
        }
    }

    /** Whether a card from another TV replaces what this TV has ({@code have}, null for nothing): it's newer, and recent. */
    static boolean takes(WatchHistory.Entry have, Card card, long now) {
        if (card.lastAt < now - WatchHistory.MAX_AGE_MS || card.lastAt > now + MAX_AHEAD_MS) return false;
        return have == null || card.lastAt > have.lastAt;
    }

    /** Of a person's own entries (newest first), those to send: recent, a kept one with its row, at most {@link #SENT_PER_PERSON}. */
    static List<WatchHistory.Entry> toSend(List<WatchHistory.Entry> own, long now) {
        List<WatchHistory.Entry> out = new ArrayList<>();
        for (WatchHistory.Entry e : own) {
            if (out.size() >= SENT_PER_PERSON) break;
            if (e.shared || e.lastAt < now - WatchHistory.MAX_AGE_MS) continue;
            if (WatchHistory.PLAYED.equals(e.kind)) {
                if (e.title == null || e.title.isEmpty()) continue;
            } else if (!WatchHistory.KEPT.equals(e.kind) || e.row == null) {
                continue;
            }
            if (!validPackage(e.packageName)) continue;
            out.add(e);
        }
        return out;
    }

    /**
     * Whether one of this TV's own entries goes out, given what the household holds for it ({@code logged}, a delete
     * included): when it differs, and isn't older than what the household has, nor than a removal there.
     */
    static boolean sends(WatchHistory.Entry e, HouseholdEntry logged) {
        if (logged == null) return true;
        if (logged.deleted) return e.lastAt > HouseholdLog.millisOf(logged);
        if (logged.value.equals(valueOf(e))) return false;
        Card theirs = cardOf(logged);
        return theirs == null || e.lastAt >= theirs.lastAt;
    }
}
