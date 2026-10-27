package com.thesiegs.hearth;

import android.content.Context;
import android.content.SharedPreferences;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;

/**
 * What a parent has blocked in HearthTube for a kids profile (provider contract 8, the {@code parent_blocks}
 * column): video ids, channel ids and words. Two sources: the ones set in Hearth itself ({@link #setOwn}), which is
 * all there is without Home Assistant, and the ones Home Assistant's integration sends in its state document
 * ({@link #setFromHomeAssistant}, replaced as a whole each time it speaks). HearthTube is handed the union, and tells a
 * kid's own hides from these: it can't undo them.
 */
final class ParentBlocks {
    private static final String PREFS = "ltv_parent_blocks";
    private static final String VERSION_KEY = "version";
    static final int ITEM_MAX = 100;
    static final int LIST_MAX = 1000;

    private ParentBlocks() {
    }

    /** The three lists, each without repeats, in the order they were added. */
    static final class Lists {
        final Set<String> videos = new LinkedHashSet<>();
        final Set<String> channels = new LinkedHashSet<>();
        final Set<String> words = new LinkedHashSet<>();

        boolean isEmpty() {
            return videos.isEmpty() && channels.isEmpty() && words.isEmpty();
        }

        Lists union(Lists other) {
            Lists all = new Lists();
            all.videos.addAll(videos);
            all.videos.addAll(other.videos);
            all.channels.addAll(channels);
            all.channels.addAll(other.channels);
            all.words.addAll(words);
            all.words.addAll(other.words);
            return all;
        }

        JSONObject toJson() throws JSONException {
            return new JSONObject().put("videos", new JSONArray(videos)).put("channels", new JSONArray(channels))
                    .put("words", new JSONArray(words));
        }

        @Override
        public boolean equals(Object o) {
            return o instanceof Lists && ((Lists) o).videos.equals(videos) && ((Lists) o).channels.equals(channels)
                    && ((Lists) o).words.equals(words);
        }

        @Override
        public int hashCode() {
            return videos.hashCode() * 31 * 31 + channels.hashCode() * 31 + words.hashCode();
        }
    }

    /** Ids as YouTube writes them; anything else is not an id. */
    static boolean isId(String id) {
        return id != null && id.matches("[A-Za-z0-9_-]{5,40}");
    }

    /** A word to block: trimmed, lower case, no control characters, not empty. Null when it isn't one. */
    static String cleanWord(String word) {
        if (word == null) return null;
        String cleaned = word.replaceAll("\\p{Cntrl}", " ").trim().toLowerCase(java.util.Locale.ROOT);
        return cleaned.isEmpty() || cleaned.length() > ITEM_MAX ? null : cleaned;
    }

    /** Lists from JSON ({"videos":[…],"channels":[…],"words":[…]}); what isn't valid is dropped. Never null. */
    static Lists parse(JSONObject json) {
        Lists lists = new Lists();
        if (json == null) return lists;
        fill(lists.videos, json.optJSONArray("videos"), false);
        fill(lists.channels, json.optJSONArray("channels"), false);
        fill(lists.words, json.optJSONArray("words"), true);
        return lists;
    }

    private static void fill(Set<String> into, JSONArray array, boolean words) {
        if (array == null) return;
        for (int i = 0; i < array.length() && into.size() < LIST_MAX; i++) {
            String item = array.optString(i, null);
            item = words ? cleanWord(item) : isId(item) ? item : null;
            if (item != null) into.add(item);
        }
    }

    /** What HearthTube is handed for the profile: the JSON of both sources together, or null when nothing is blocked. */
    static String json(Context context, String profile) {
        Lists all = own(context, profile).union(fromHomeAssistant(context, profile));
        if (all.isEmpty()) return null;
        try {
            return all.toJson().toString();
        } catch (JSONException e) {
            return null;
        }
    }

    /** Goes up whenever what {@link #json} says changes, for any profile (0 before the first change). */
    static int version(Context context) {
        return prefs(context).getInt(VERSION_KEY, 0);
    }

    static Lists own(Context context, String profile) {
        return read(context, "own|", profile);
    }

    static Lists fromHomeAssistant(Context context, String profile) {
        return read(context, "ha|", profile);
    }

    /** Hearth's own settings for the profile (a parent's choice there). */
    static boolean setOwn(Context context, String profile, Lists lists) {
        return write(context, "own|", profile, lists);
    }

    /** Home Assistant's lists for the profile, as the integration last said them. */
    static boolean setFromHomeAssistant(Context context, String profile, Lists lists) {
        return write(context, "ha|", profile, lists);
    }

    private static Lists read(Context context, String source, String profile) {
        if (profile == null) return new Lists();
        try {
            String saved = prefs(context).getString(source + profile, null);
            return parse(saved != null ? new JSONObject(saved) : null);
        } catch (JSONException e) {
            return new Lists();
        }
    }

    /** Saves, and when the union for this profile changed, bumps the version. True when it did. */
    private static synchronized boolean write(Context context, String source, String profile, Lists lists) {
        if (profile == null) return false;
        String other = "own|".equals(source) ? "ha|" : "own|";
        Lists before = read(context, "own|", profile).union(read(context, "ha|", profile));
        Lists after = lists.union(read(context, other, profile));
        SharedPreferences.Editor edit = prefs(context).edit();
        try {
            if (lists.isEmpty()) edit.remove(source + profile); else edit.putString(source + profile, lists.toJson().toString());
        } catch (JSONException e) {
            return false;
        }
        boolean changed = !before.equals(after);
        if (changed) edit.putInt(VERSION_KEY, version(context) + 1);
        edit.apply();
        return changed;
    }

    /** Words, ids as a plain list, for screens. */
    static List<String> asList(Set<String> items) {
        return new ArrayList<>(items);
    }

    private static SharedPreferences prefs(Context context) {
        return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }
}
