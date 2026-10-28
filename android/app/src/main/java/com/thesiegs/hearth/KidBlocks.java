package com.thesiegs.hearth;

import android.content.Context;
import android.content.SharedPreferences;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.Map;
import java.util.Set;

/**
 * What a kids profile hid or blocked itself in HearthTube (provider contract 10, {@code report_kid_blocks}): its
 * hidden videos, blocked channels and blocked words, as HearthTube last sent them (the whole each time), for a parent to
 * see in Hearth's settings. A parent can take one back ({@link #undo}): it goes down in the {@code kid_unblocks}
 * column, HearthTube takes it back, and once its next list no longer has it, the undo is done and dropped.
 * <p>
 * A video or channel is known by its key (a channel blocked without an id by its name, as HearthTube keeps it).
 */
final class KidBlocks {
    private static final String PREFS = "ltv_kid_blocks";
    static final int LIST_MAX = 500;
    /** What a call may carry: HearthTube cuts each list to 500 and each label to 150 */
    static final int JSON_MAX = 256 * 1024;
    static final String VIDEOS = "videos";
    static final String CHANNELS = "channels";
    static final String WORDS = "words";

    private KidBlocks() {
    }

    /** The kid's lists: key -> label (a word is its own label), in HearthTube's order. */
    static final class Lists {
        final Map<String, String> videos = new LinkedHashMap<>();
        final Map<String, String> channels = new LinkedHashMap<>();
        final Map<String, String> words = new LinkedHashMap<>();

        Map<String, String> of(String kind) {
            switch (kind) {
                case VIDEOS: return videos;
                case CHANNELS: return channels;
                case WORDS: return words;
                default: return null;
            }
        }

        boolean isEmpty() {
            return videos.isEmpty() && channels.isEmpty() && words.isEmpty();
        }

        JSONObject toJson() throws JSONException {
            JSONObject json = new JSONObject();
            for (String kind : new String[]{VIDEOS, CHANNELS}) {
                JSONArray array = new JSONArray();
                for (Map.Entry<String, String> entry : of(kind).entrySet()) {
                    array.put(new JSONObject().put("key", entry.getKey()).put("label", entry.getValue()));
                }
                json.put(kind, array);
            }
            return json.put(WORDS, new JSONArray(words.keySet()));
        }
    }

    /** HearthTube's JSON ({"videos": [{"key", "label"}], "channels": [...], "words": [...]}); what isn't valid is dropped. */
    static Lists parse(JSONObject json) {
        Lists lists = new Lists();
        if (json == null) return lists;
        for (String kind : new String[]{VIDEOS, CHANNELS}) {
            JSONArray array = json.optJSONArray(kind);
            for (int i = 0; array != null && i < array.length() && lists.of(kind).size() < LIST_MAX; i++) {
                JSONObject item = array.optJSONObject(i);
                String key = item != null ? StartedLog.clean(item.optString("key", "")) : "";
                if (key.isEmpty()) continue;
                String label = StartedLog.clean(item.optString("label", ""));
                lists.of(kind).put(key, label.isEmpty() ? key : label);
            }
        }
        JSONArray words = json.optJSONArray(WORDS);
        for (int i = 0; words != null && i < words.length() && lists.words.size() < LIST_MAX; i++) {
            String word = StartedLog.clean(words.optString(i, ""));
            if (!word.isEmpty()) lists.words.put(word, word);
        }
        return lists;
    }

    /** The undo lists ({"videos": [keys], "channels": [keys], "words": [...]}) */
    static Map<String, Set<String>> parseUndo(JSONObject json) {
        Map<String, Set<String>> undo = new LinkedHashMap<>();
        for (String kind : new String[]{VIDEOS, CHANNELS, WORDS}) {
            Set<String> keys = new LinkedHashSet<>();
            JSONArray array = json != null ? json.optJSONArray(kind) : null;
            for (int i = 0; array != null && i < array.length() && keys.size() < LIST_MAX; i++) {
                String key = array.optString(i, "");
                if (!key.isEmpty()) keys.add(key);
            }
            undo.put(kind, keys);
        }
        return undo;
    }

    /** An undo is done once the kid's list no longer has it: what is still to take back. */
    static Map<String, Set<String>> stillToUndo(Map<String, Set<String>> undo, Lists kid) {
        Map<String, Set<String>> left = new LinkedHashMap<>();
        for (Map.Entry<String, Set<String>> entry : undo.entrySet()) {
            Set<String> keys = new LinkedHashSet<>();
            for (String key : entry.getValue()) {
                if (kid.of(entry.getKey()).containsKey(key)) keys.add(key);
            }
            left.put(entry.getKey(), keys);
        }
        return left;
    }

    private static boolean noUndo(Map<String, Set<String>> undo) {
        for (Set<String> keys : undo.values()) if (!keys.isEmpty()) return false;
        return true;
    }

    /** HearthTube sent the kid's lists for this profile. False when they weren't JSON. */
    static synchronized boolean record(Context context, String profile, String json) {
        profile = ParentBlocks.userKey(profile);
        if (profile == null || json == null || json.length() > JSON_MAX) return false;
        Lists lists;
        try {
            lists = parse(new JSONObject(json));
        } catch (JSONException e) {
            return false;
        }
        Map<String, Set<String>> left = stillToUndo(undo(context, profile), lists);
        try {
            SharedPreferences.Editor edit = prefs(context).edit().putString("kid|" + profile, lists.toJson().toString());
            if (noUndo(left)) edit.remove("undo|" + profile); else edit.putString("undo|" + profile, undoJson(left));
            edit.apply();
        } catch (JSONException e) {
            return false;
        }
        return true;
    }

    /** The kid's lists, as HearthTube last sent them, without what a parent is taking back. */
    static synchronized Lists read(Context context, String profile) {
        profile = ParentBlocks.userKey(profile);
        Lists lists = new Lists();
        if (profile == null) return lists;
        try {
            String saved = prefs(context).getString("kid|" + profile, null);
            if (saved != null) lists = parse(new JSONObject(saved));
        } catch (JSONException e) {
            return new Lists();
        }
        for (Map.Entry<String, Set<String>> entry : undo(context, profile).entrySet()) {
            for (String key : entry.getValue()) lists.of(entry.getKey()).remove(key);
        }
        return lists;
    }

    /** A parent takes one back. kind: "video", "channel" or "word". False when the kid's list doesn't have it. */
    static synchronized boolean undo(Context context, String profile, String kind, String key) {
        profile = ParentBlocks.userKey(profile);
        String list = "video".equals(kind) ? VIDEOS : "channel".equals(kind) ? CHANNELS : "word".equals(kind) ? WORDS : null;
        if (profile == null || list == null || key == null || !read(context, profile).of(list).containsKey(key)) return false;
        Map<String, Set<String>> undo = undo(context, profile);
        if (!undo.get(list).add(key)) return false;
        prefs(context).edit().putString("undo|" + profile, undoJson(undo)).apply();
        return true;
    }

    /** What HearthTube in the profile is to take back (the kid_unblocks column), or null when nothing. */
    static synchronized String undoJson(Context context, String profile) {
        profile = ParentBlocks.userKey(profile);
        if (profile == null) return null;
        Map<String, Set<String>> undo = undo(context, profile);
        return noUndo(undo) ? null : undoJson(undo);
    }

    private static Map<String, Set<String>> undo(Context context, String profile) {
        try {
            String saved = prefs(context).getString("undo|" + profile, null);
            return parseUndo(saved != null ? new JSONObject(saved) : null);
        } catch (JSONException e) {
            return parseUndo(null);
        }
    }

    private static String undoJson(Map<String, Set<String>> undo) {
        JSONObject json = new JSONObject();
        try {
            for (Map.Entry<String, Set<String>> entry : undo.entrySet()) json.put(entry.getKey(), new JSONArray(entry.getValue()));
        } catch (JSONException e) {
            return "{}";
        }
        return json.toString();
    }

    private static SharedPreferences prefs(Context context) {
        return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }
}
