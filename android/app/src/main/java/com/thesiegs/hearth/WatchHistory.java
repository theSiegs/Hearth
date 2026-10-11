package com.thesiegs.hearth;

import android.content.ContentValues;
import android.content.Context;
import android.database.Cursor;
import android.database.sqlite.SQLiteDatabase;
import android.database.sqlite.SQLiteOpenHelper;
import android.util.Log;

import org.json.JSONException;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.Iterator;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.TreeMap;

/**
 * What each grown-up profile watched on this TV, kept by Hearth itself. Android's Watch Next list is per Android
 * user, so the grown-ups (Google accounts in the owner's user) share one, and apps rewrite it as they please.
 * Hearth keeps two things, each under the profile (key) it belongs to:
 * <ul>
 * <li>played: what an app said was playing (its media session's title and episode), recorded while it played under
 * the profile that was on (PlaybackRecorder). Exact, and it covers apps that put nothing in Watch Next.</li>
 * <li>kept: Watch Next entries, so that one an app takes out while another profile uses it (Netflix lists only its
 * current profile's) stays for its own profile until that profile uses the app again.</li>
 * </ul>
 * Continue Watching then shows each profile its own Watch Next entries (whose: what it played, else who had the
 * app, see AppWatchers), its kept entries, and what it played that Watch Next doesn't have.
 */
final class WatchHistory extends SQLiteOpenHelper {
    private static final String TAG = "HearthWatchNext";
    private static final String DB = "watch_history.db";
    private static final int VERSION = 1;
    private static final String TABLE = "history";
    static final String PLAYED = "played";
    static final String KEPT = "kept";

    /** Older than this, an entry is forgotten (Continue Watching stops showing it sooner). */
    static final long MAX_AGE_MS = 90L * 24 * 60 * 60_000;
    /** At most this many played entries per profile. */
    static final int MAX_PLAYED_PER_PROFILE = 300;
    /** A played entry shows on its own (no Watch Next entry for it) once it's this long and this far in. */
    static final long MIN_SHOWN_DURATION_MS = 4 * 60_000;
    static final long MIN_SHOWN_POSITION_MS = 60_000;
    static final double FINISHED_FRACTION = 0.95;
    /** A played entry names a Watch Next entry's profile only if it was played this close to the entry's time. */
    static final long OWNER_MATCH_WINDOW_MS = 12L * 60 * 60_000;

    private static WatchHistory sInstance;

    private WatchHistory(Context context) {
        super(context.getApplicationContext(), DB, null, VERSION);
    }

    static synchronized WatchHistory get(Context context) {
        if (sInstance == null) sInstance = new WatchHistory(context);
        return sInstance;
    }

    @Override
    public void onCreate(SQLiteDatabase db) {
        db.execSQL("CREATE TABLE " + TABLE + " ("
                // AUTOINCREMENT: ids are never reused, so a hidden card's id never hides another
                + "id INTEGER PRIMARY KEY AUTOINCREMENT,"
                + "kind TEXT NOT NULL,"
                + "profile TEXT NOT NULL,"
                + "package TEXT NOT NULL,"
                // played: its title and episode; kept: the app's own id for the entry, else its title
                + "item TEXT NOT NULL,"
                + "title TEXT,"
                + "subtitle TEXT,"
                + "duration INTEGER NOT NULL DEFAULT 0,"
                + "position INTEGER NOT NULL DEFAULT 0,"
                // played: when it last played; kept: the entry's engagement time
                + "last_at INTEGER NOT NULL DEFAULT 0,"
                // kept: the Watch Next entry as Flutter gets it (JSON)
                + "row TEXT,"
                // kept: when the app took the entry out of Watch Next (0: still in it)
                + "gone_at INTEGER NOT NULL DEFAULT 0,"
                + "UNIQUE(kind, profile, package, item))");
    }

    @Override
    public void onUpgrade(SQLiteDatabase db, int oldVersion, int newVersion) {
        db.execSQL("DROP TABLE IF EXISTS " + TABLE);
        onCreate(db);
    }

    // --- played ---

    /** The profile (key) is playing this; called while it plays, with where it's got to. */
    synchronized void recordPlay(String profile, String packageName, String title, String subtitle, long durationMs,
            long positionMs, long now) {
        if (profile == null || packageName == null || title == null || title.isEmpty()) return;
        String item = playedItem(title, subtitle);
        ContentValues values = new ContentValues();
        values.put("title", title);
        values.put("subtitle", subtitle);
        values.put("duration", Math.max(0, durationMs));
        values.put("position", Math.max(0, positionMs));
        values.put("last_at", now);
        try {
            SQLiteDatabase db = getWritableDatabase();
            int updated = db.update(TABLE, values, "kind=? AND profile=? AND package=? AND item=?",
                    new String[]{PLAYED, profile, packageName, item});
            if (updated == 0) {
                values.put("kind", PLAYED);
                values.put("profile", profile);
                values.put("package", packageName);
                values.put("item", item);
                db.insert(TABLE, null, values);
                prunePlayed(db, profile, now);
            }
        } catch (RuntimeException e) {
            Log.w(TAG, "Couldn't record what's playing", e);
        }
    }

    private static void prunePlayed(SQLiteDatabase db, String profile, long now) {
        db.delete(TABLE, "last_at < ?", new String[]{String.valueOf(now - MAX_AGE_MS)});
        db.execSQL("DELETE FROM " + TABLE + " WHERE kind=? AND profile=? AND id NOT IN (SELECT id FROM " + TABLE
                + " WHERE kind=? AND profile=? ORDER BY last_at DESC LIMIT " + MAX_PLAYED_PER_PROFILE + ")",
                new Object[]{PLAYED, profile, PLAYED, profile});
    }

    /** A played entry: one per title and episode. */
    static String playedItem(String title, String subtitle) {
        return norm(title) + "|" + norm(subtitle);
    }

    // --- Continue Watching ---

    /** A played or kept entry as read back. */
    static final class Entry {
        final long id;
        final String kind;
        final String profile;
        final String packageName;
        final String item;
        final String title;
        final String subtitle;
        final long duration;
        final long position;
        final long lastAt;
        final String row;
        final long goneAt;

        Entry(long id, String kind, String profile, String packageName, String item, String title, String subtitle,
                long duration, long position, long lastAt, String row, long goneAt) {
            this.id = id;
            this.kind = kind;
            this.profile = profile;
            this.packageName = packageName;
            this.item = item;
            this.title = title;
            this.subtitle = subtitle;
            this.duration = duration;
            this.position = position;
            this.lastAt = lastAt;
            this.row = row;
            this.goneAt = goneAt;
        }
    }

    private List<Entry> entries(SQLiteDatabase db) {
        List<Entry> entries = new ArrayList<>();
        try (Cursor c = db.query(TABLE, new String[]{"id", "kind", "profile", "package", "item", "title", "subtitle",
                "duration", "position", "last_at", "row", "gone_at"}, null, null, null, null, "last_at DESC")) {
            while (c.moveToNext()) {
                entries.add(new Entry(c.getLong(0), c.getString(1), c.getString(2), c.getString(3), c.getString(4),
                        c.getString(5), c.getString(6), c.getLong(7), c.getLong(8), c.getLong(9), c.getString(10),
                        c.getLong(11)));
            }
        }
        return entries;
    }

    /**
     * This user's Watch Next entries for Continue Watching: each marked with whose it is ("watchedBy", a profile key
     * of this user), plus the entries kept for profiles the app no longer lists, and what profiles played that
     * Watch Next doesn't list ("kept" / "played" entries have negative ids: -their id here). Keeps the kept entries
     * up to date as it goes.
     */
    synchronized List<Map<String, Object>> continueWatching(Context context, List<Map<String, Object>> rows,
            long serial, long now) {
        List<Map<String, Object>> out = new ArrayList<>(rows);
        try {
            SQLiteDatabase db = getWritableDatabase();
            List<Entry> entries = entries(db);
            List<Entry> played = new ArrayList<>();
            for (Entry e : entries) {
                if (PLAYED.equals(e.kind) && ProfileUsers.serialOfKey(e.profile) == serial) played.add(e);
            }
            // Whose each listed entry is: the profile that played it, else the one that had the app then
            Map<String, Map<String, Integer>> owners = new TreeMap<>();
            for (Map<String, Object> row : out) {
                String pkg = (String) row.get("packageName");
                String owner = ownerOf(played, AppWatchers.history(context, pkg), pkg, (String) row.get("title"),
                        longOf(row.get("lastEngagementTime")), serial);
                if (owner != null) row.put("watchedBy", owner);
                Map<String, Integer> counts = owners.get(String.valueOf(pkg));
                if (counts == null) owners.put(String.valueOf(pkg), counts = new TreeMap<>());
                String who = owner != null ? owner : "none";
                Integer count = counts.get(who);
                counts.put(who, count != null ? count + 1 : 1);
            }
            // Counts only, no titles: whose each app's entries are
            Log.i(TAG, "Owners of the listed entries: " + owners);
            db.beginTransaction();
            try {
                keep(context, db, entries, out, serial, now);
                db.setTransactionSuccessful();
            } finally {
                db.endTransaction();
            }
            // Kept entries the app no longer lists, for their own profile
            for (Entry e : entries(db)) {
                if (!KEPT.equals(e.kind) || e.goneAt == 0 || e.row == null) continue;
                Map<String, Object> row = rowOf(e.row);
                if (row == null) continue;
                row.put("id", -e.id);
                row.put("watchedBy", e.profile);
                row.put("kept", true);
                out.add(row);
            }
            // Played but not in Watch Next (listed or kept): shown from what was played
            for (Entry e : played) {
                if (!showsOnItsOwn(e, now) || inWatchNext(out, e)) continue;
                Map<String, Object> row = new HashMap<>();
                row.put("id", -e.id);
                row.put("packageName", e.packageName);
                row.put("title", e.title);
                row.put("description", e.subtitle != null ? e.subtitle : "");
                row.put("watchNextType", 0);
                row.put("lastEngagementTime", e.lastAt);
                row.put("playbackPosition", e.position);
                row.put("duration", e.duration);
                row.put("intentUri", "");
                row.put("posterArtUri", "");
                row.put("watchedBy", e.profile);
                row.put("played", true);
                out.add(row);
            }
        } catch (RuntimeException e) {
            Log.w(TAG, "Couldn't read Hearth's watch history", e);
        }
        return out;
    }

    /**
     * Keeps a copy of each listed entry under its profile. One the app took out is let go if its own profile had
     * the app then (finished or removed), or has opened the app since (it would be listed again if it were still
     * there); otherwise it stays, as another profile's use of the app took it out.
     */
    private static void keep(Context context, SQLiteDatabase db, List<Entry> entries, List<Map<String, Object>> rows,
            long serial, long now) {
        Map<String, Map<String, Object>> byItem = new HashMap<>();
        for (Map<String, Object> row : rows) byItem.put(row.get("packageName") + "\n" + keptItem(row), row);
        for (Entry e : entries) {
            if (!KEPT.equals(e.kind) || ProfileUsers.serialOfKey(e.profile) != serial) continue;
            String where = "id=" + e.id;
            Map<String, Object> row = byItem.get(e.packageName + "\n" + e.item);
            if (row != null) {
                // Listed: it's the listed entry's profile's now (written below)
                if (!e.profile.equals(row.get("watchedBy"))) db.delete(TABLE, where, null);
                continue;
            }
            if (e.lastAt < now - MAX_AGE_MS) {
                db.delete(TABLE, where, null);
                continue;
            }
            String holder = AppWatchers.holder(context, e.packageName);
            if (e.goneAt == 0) {
                if (e.profile.equals(holder)) {
                    db.delete(TABLE, where, null);
                } else {
                    ContentValues gone = new ContentValues();
                    gone.put("gone_at", now);
                    db.update(TABLE, gone, where, null);
                }
            } else if (AppWatchers.openedSince(context, e.packageName, e.profile, e.goneAt)) {
                db.delete(TABLE, where, null);
            }
        }
        for (Map<String, Object> row : rows) {
            String owner = (String) row.get("watchedBy");
            if (owner == null) continue;
            ContentValues values = new ContentValues();
            values.put("title", (String) row.get("title"));
            values.put("subtitle", (String) row.get("description"));
            values.put("duration", longOf(row.get("duration")));
            values.put("position", longOf(row.get("playbackPosition")));
            values.put("last_at", longOf(row.get("lastEngagementTime")));
            values.put("row", new JSONObject(withoutOwner(row)).toString());
            values.put("gone_at", 0);
            String[] key = {KEPT, owner, (String) row.get("packageName"), keptItem(row)};
            if (db.update(TABLE, values, "kind=? AND profile=? AND package=? AND item=?", key) == 0) {
                values.put("kind", key[0]);
                values.put("profile", key[1]);
                values.put("package", key[2]);
                values.put("item", key[3]);
                db.insert(TABLE, null, values);
            }
        }
    }

    /** Forgets the kept copies of a Watch Next entry that was removed from Continue Watching. */
    synchronized void forgetListed(String packageName, Map<String, Object> row) {
        try {
            getWritableDatabase().delete(TABLE, "kind=? AND package=? AND item=?",
                    new String[]{KEPT, packageName, keptItem(row)});
        } catch (RuntimeException e) {
            Log.w(TAG, "Couldn't forget a kept entry", e);
        }
    }

    /** Forgets a kept or played entry (its id is the negative one Continue Watching had). */
    synchronized boolean forget(long id) {
        try {
            return getWritableDatabase().delete(TABLE, "id=?", new String[]{String.valueOf(-id)}) > 0;
        } catch (RuntimeException e) {
            Log.w(TAG, "Couldn't forget a watch history entry", e);
            return false;
        }
    }

    // --- rules (pure, tested) ---

    /** A title for matching: letters and digits only, in lower case. */
    static String norm(String s) {
        if (s == null) return "";
        StringBuilder out = new StringBuilder();
        for (int i = 0; i < s.length(); ) {
            int c = s.codePointAt(i);
            i += Character.charCount(c);
            if (Character.isLetterOrDigit(c)) out.appendCodePoint(Character.toLowerCase(c));
        }
        return out.toString().toLowerCase(Locale.ROOT);
    }

    /** The key a Watch Next entry is kept under: the app's own id for it, else its title. */
    static String keptItem(Map<String, Object> row) {
        Object internal = row.get("internalId");
        if (internal instanceof String && !((String) internal).isEmpty()) return "id:" + internal;
        return "title:" + norm((String) row.get("title"));
    }

    /** Whether a played entry and a Watch Next entry (by its title) are the same show or film. */
    static boolean sameTitle(String playedTitle, String playedSubtitle, String rowTitle) {
        String row = norm(rowTitle);
        if (row.isEmpty()) return false;
        String title = norm(playedTitle), subtitle = norm(playedSubtitle);
        if (row.equals(title) || row.equals(subtitle)) return true;
        // An app's own list often names the show and the episode together ("South Park - Pilot", while it plays
        // "Pilot" with "South Park" under it): a row holding all of what played, if that's not too short to tell
        return title.length() >= MIN_CONTAINED_TITLE && row.contains(title)
                && (subtitle.isEmpty() || row.contains(subtitle));
    }

    /** Letters and digits a played title needs before a row containing it counts as the same (see sameTitle). */
    private static final int MIN_CONTAINED_TITLE = 6;

    /**
     * Whose a Watch Next entry is (a profile key of this user), or null when Hearth can't tell: the profile that played
     * it, unless another profile opened its app after that play and before the entry's time (it watched it since, too
     * briefly for Hearth to count, or picked it up where the other left off; the app's entry is one per show or video,
     * moved to the newest watch); else the profile that had the app at the entry's time.
     *
     * @param watchers the app's AppWatchers record
     */
    static String ownerOf(List<Entry> played, String watchers, String packageName, String title, long time,
            long serial) {
        Entry play = playedBy(played, packageName, title, time);
        String watcher = AppWatchers.watcherAt(watchers, time, serial);
        if (play == null) return watcher;
        if (watcher != null && !watcher.equals(play.profile)
                && AppWatchers.changedHands(watchers, play.lastAt, time, serial)) {
            return watcher;
        }
        return play.profile;
    }

    /** The profile that played this entry closest to its time, or null when none did. */
    static String playedOwner(List<Entry> played, String packageName, String title, long time) {
        Entry play = playedBy(played, packageName, title, time);
        return play != null ? play.profile : null;
    }

    /** The play of this entry closest to its time, or null when none was near it. */
    private static Entry playedBy(List<Entry> played, String packageName, String title, long time) {
        Entry best = null;
        long bestGap = Long.MAX_VALUE;
        for (Entry e : played) {
            if (!e.packageName.equals(packageName) || !sameTitle(e.title, e.subtitle, title)) continue;
            long gap = time > 0 ? Math.abs(e.lastAt - time) : 0;
            if (time > 0 && gap > OWNER_MATCH_WINDOW_MS) continue;
            if (best == null || gap < bestGap) {
                best = e;
                bestGap = gap;
            }
        }
        return best;
    }

    /**
     * Whether a played entry shows in Continue Watching when Watch Next has nothing for it: long enough to be a show
     * or film (not a trailer or clip), started, not finished, and not old.
     */
    static boolean showsOnItsOwn(Entry e, long now) {
        return e.duration >= MIN_SHOWN_DURATION_MS && e.position >= MIN_SHOWN_POSITION_MS
                && e.position < e.duration * FINISHED_FRACTION && now - e.lastAt < MAX_AGE_MS;
    }

    /** Whether Continue Watching already has this played show or film from Watch Next (listed or kept). */
    private static boolean inWatchNext(List<Map<String, Object>> rows, Entry e) {
        for (Map<String, Object> row : rows) {
            if (e.packageName.equals(row.get("packageName")) && Boolean.TRUE != row.get("played")
                    && sameTitle(e.title, e.subtitle, (String) row.get("title"))) {
                return true;
            }
        }
        return false;
    }

    private static Map<String, Object> withoutOwner(Map<String, Object> row) {
        Map<String, Object> copy = new HashMap<>(row);
        copy.remove("watchedBy");
        return copy;
    }

    private static Map<String, Object> rowOf(String json) {
        try {
            JSONObject o = new JSONObject(json);
            Map<String, Object> row = new HashMap<>();
            for (Iterator<String> keys = o.keys(); keys.hasNext(); ) {
                String key = keys.next();
                Object value = o.get(key);
                // Flutter reads the numbers as ints of any size
                row.put(key, value instanceof Integer ? Long.valueOf((Integer) value) : value);
            }
            return row;
        } catch (JSONException e) {
            return null;
        }
    }

    private static long longOf(Object value) {
        return value instanceof Number ? ((Number) value).longValue() : 0;
    }
}
