package com.thesiegs.hearth;

import android.content.Context;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * What Hearth's own screens (Settings > Family > Kids profiles > the kid) read and change for the parent channel
 * (provider contract 8): the kid's log of started videos, and the parent's blocked videos, channels and words. The
 * screens only touch what is set in Hearth ("own"); what Home Assistant sends is shown, and taken back there.
 */
final class ParentChannelApi {
    /** Lines the log screen gets: the newest */
    static final int LOG_MAX = 500;

    private ParentChannelApi() {
    }

    /** The kid's started videos, newest first, as maps the screen reads: t (ms), v, title, ch, cid. */
    static List<Map<String, Object>> startedLog(Context context, String profile) {
        List<StartedLog.Entry> entries = StartedLog.read(context, profile);
        List<Map<String, Object>> result = new ArrayList<>();

        for (int i = entries.size() - 1; i >= 0 && result.size() < LOG_MAX; i--) {
            StartedLog.Entry entry = entries.get(i);
            Map<String, Object> row = new HashMap<>();
            row.put("t", entry.timeMs);
            row.put("v", entry.videoId);
            row.put("title", entry.title);
            row.put("ch", entry.channel);
            row.put("cid", entry.channelId);
            result.add(row);
        }

        return result;
    }

    /** {"own": lists, "ha": lists}; each is {"videos": [{id, label}], "channels": [{id, label}], "words": [word]} */
    static Map<String, Object> parentBlocks(Context context, String profile) {
        Map<String, Object> result = new HashMap<>();
        result.put("own", describe(ParentBlocks.own(context, profile)));
        result.put("ha", describe(ParentBlocks.fromHomeAssistant(context, profile)));
        return result;
    }

    private static Map<String, Object> describe(ParentBlocks.Lists lists) {
        Map<String, Object> map = new HashMap<>();
        map.put("videos", withLabels(lists.videos, lists.labels));
        map.put("channels", withLabels(lists.channels, lists.labels));
        map.put("words", new ArrayList<>(lists.words));
        return map;
    }

    private static List<Map<String, String>> withLabels(Set<String> ids, Map<String, String> labels) {
        List<Map<String, String>> list = new ArrayList<>();

        for (String id : ids) {
            Map<String, String> item = new HashMap<>();
            item.put("id", id);
            item.put("label", labels.containsKey(id) ? labels.get(id) : id);
            list.add(item);
        }

        return list;
    }

    /**
     * Blocks or unblocks one thing for the profile, in what is set in Hearth. kind: "video", "channel" or "word". False
     * when it isn't a valid id or word. The kid's HearthTube is told the next time Hearth sends its row.
     */
    static boolean setBlock(Context context, String profile, String kind, String id, String label, boolean on) {
        if (profile == null || kind == null || id == null) return false;

        ParentBlocks.Lists lists = ParentBlocks.own(context, profile);
        String item;
        java.util.Set<String> target;

        switch (kind) {
            case "video":
                item = ParentBlocks.isId(id) ? id : null;
                target = lists.videos;
                break;
            case "channel":
                item = ParentBlocks.isId(id) ? id : null;
                target = lists.channels;
                break;
            case "word":
                item = ParentBlocks.cleanWord(id);
                target = lists.words;
                break;
            default:
                return false;
        }

        if (item == null) return false;

        if (on) {
            target.add(item);
            String clean = StartedLog.clean(label);
            if (!"word".equals(kind) && !clean.isEmpty()) lists.labels.put(item, clean);
        } else {
            target.remove(item);
            lists.labels.remove(item);
        }

        if (ParentBlocks.setOwn(context, profile, lists)) ProfileProvider.notifyChanged(context);
        return true;
    }
}
