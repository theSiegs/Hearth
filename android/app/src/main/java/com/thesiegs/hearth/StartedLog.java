package com.thesiegs.hearth;

import android.content.Context;
import android.content.SharedPreferences;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.List;

/**
 * The videos a kids profile started in HearthTube (provider contract 8, {@code report_started}), kept per profile for
 * a parent to read: in Hearth's own settings, and in Home Assistant when it's set up. Hearth keeps it whether or not
 * Home Assistant is there. One entry per video started (HearthTube already folds a resume into the first start); the
 * newest {@link #MAX} per profile are kept, a repeat of the same time and video is ignored, so a resend is harmless.
 */
final class StartedLog {
    private static final String PREFS = "ltv_started_log";
    static final int MAX = 2000;
    private static final int FIELD_MAX = 300;

    private StartedLog() {
    }

    static final class Entry {
        final long timeMs;
        final String videoId;
        final String title;
        final String channel;
        final String channelId;

        Entry(long timeMs, String videoId, String title, String channel, String channelId) {
            this.timeMs = timeMs;
            this.videoId = videoId;
            this.title = clean(title);
            this.channel = clean(channel);
            this.channelId = clean(channelId);
        }

        JSONObject toJson() throws JSONException {
            return new JSONObject().put("t", timeMs).put("v", videoId).put("title", title).put("ch", channel)
                    .put("cid", channelId);
        }

        static Entry of(JSONObject json) {
            if (json == null) return null;
            return valid(json.optLong("t", -1), json.optString("v", null))
                    ? new Entry(json.optLong("t"), json.optString("v"), json.optString("title", ""),
                            json.optString("ch", ""), json.optString("cid", "")) : null;
        }
    }

    /** What a caller may hand in: a real time and a video id (letters, digits, - and _, as YouTube's are). */
    static boolean valid(long timeMs, String videoId) {
        return timeMs > 0 && videoId != null && videoId.matches("[A-Za-z0-9_-]{5,32}");
    }

    /** Text from another app: control characters out, cut short. */
    static String clean(String text) {
        if (text == null) return "";
        String cleaned = text.replaceAll("\\p{Cntrl}", " ").trim();
        return cleaned.length() > FIELD_MAX ? cleaned.substring(0, FIELD_MAX) : cleaned;
    }

    /** Adds an entry to an oldest-first list: false when it is already there; keeps the newest {@link #MAX}. */
    static boolean add(List<Entry> entries, Entry entry) {
        for (int i = entries.size() - 1; i >= 0; i--) {
            Entry have = entries.get(i);
            if (have.timeMs < entry.timeMs) break;
            if (have.timeMs == entry.timeMs && have.videoId.equals(entry.videoId)) return false;
        }
        int at = entries.size();
        while (at > 0 && entries.get(at - 1).timeMs > entry.timeMs) at--;
        entries.add(at, entry);
        while (entries.size() > MAX) entries.remove(0);
        return true;
    }

    /** Records a start for a profile. False when it was refused (not valid) or already known. */
    static synchronized boolean record(Context context, String profile, long timeMs, String videoId, String title,
            String channel, String channelId) {
        profile = ParentBlocks.userKey(profile);
        if (profile == null || !valid(timeMs, videoId)) return false;
        List<Entry> entries = read(context, profile);
        if (!add(entries, new Entry(timeMs, videoId, title, channel, channelId))) return true;
        write(context, profile, entries);
        return true;
    }

    /** The profile's entries, oldest first. */
    static synchronized List<Entry> read(Context context, String profile) {
        List<Entry> entries = new ArrayList<>();
        profile = ParentBlocks.userKey(profile);
        if (profile == null) return entries;
        try {
            JSONArray array = new JSONArray(prefs(context).getString(profile, "[]"));
            for (int i = 0; i < array.length(); i++) {
                Entry entry = Entry.of(array.optJSONObject(i));
                if (entry != null) entries.add(entry);
            }
        } catch (JSONException e) {
            // Unreadable: start again rather than fail every start
        }
        return entries;
    }

    private static void write(Context context, String profile, List<Entry> entries) {
        JSONArray array = new JSONArray();
        try {
            for (Entry entry : entries) array.put(entry.toJson());
        } catch (JSONException e) {
            return;
        }
        prefs(context).edit().putString(profile, array.toString()).apply();
    }

    private static SharedPreferences prefs(Context context) {
        return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }
}
