package com.thesiegs.hearth;

import android.content.Context;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * What Hearth lists in its notification Bell itself, beside the apps' notifications: a TV asking to join the household
 * (HouseholdJoining), with Allow and Don't allow. Only grown-ups see it: never while a kids profile is on.
 */
final class HearthBellItems {
    private static final String PREFIX = "hearth:";
    static final String JOIN_KEY = PREFIX + "household-join";
    static final int ALLOW = 0;
    static final int DENY = 1;

    /** When the waiting request came, so it sorts among the apps' notifications. */
    private static long sJoinPosted;

    private HearthBellItems() {
    }

    /** Whether this Bell key is one of Hearth's own items. */
    static boolean owns(String key) {
        return key != null && key.startsWith(PREFIX);
    }

    /** A request came ({@code joiner}, its TV's name) or ended (null): the Bell changes, and a new one pops up. */
    static void joinRequestChanged(Context context, String joiner) {
        synchronized (HearthBellItems.class) {
            sJoinPosted = joiner != null ? System.currentTimeMillis() : 0;
        }
        LauncherNotificationListenerService.hearthItemsChanged();
        if (joiner != null && !ProfileUsers.isKids(context)) {
            LauncherNotificationListenerService.popUpHearthItem(context.getString(R.string.household_join_bell_app),
                    context.getString(R.string.household_join_bell_title, joiner),
                    context.getString(R.string.household_join_bell_text));
        }
    }

    /**
     * The profile on screen changed: a request that came while a kids profile was on shows now, and pops up, for the
     * adult who came on; a kids profile's Bell loses it.
     */
    static void profileChanged(Context context) {
        String joiner = HouseholdJoining.requestName();
        if (joiner == null) return;
        LauncherNotificationListenerService.hearthItemsChanged();
        if (!ProfileUsers.isKids(context)) {
            LauncherNotificationListenerService.popUpHearthItem(context.getString(R.string.household_join_bell_app),
                    context.getString(R.string.household_join_bell_title, joiner),
                    context.getString(R.string.household_join_bell_text));
        }
    }

    /** Adds Hearth's items to the Bell's list, in its form; none on a kids profile. */
    static void addTo(Context context, List<Map<String, Object>> list) {
        String joiner = HouseholdJoining.requestName();
        if (joiner == null || ProfileUsers.isKids(context)) return;
        long posted;
        synchronized (HearthBellItems.class) {
            posted = sJoinPosted > 0 ? sJoinPosted : System.currentTimeMillis();
        }
        Map<String, Object> item = new HashMap<>();
        item.put("key", JOIN_KEY);
        item.put("packageName", context.getPackageName());
        item.put("appLabel", context.getString(R.string.household_join_bell_app));
        item.put("title", context.getString(R.string.household_join_bell_title, joiner));
        item.put("text", context.getString(R.string.household_join_bell_text));
        item.put("postTime", posted);
        // Counted on the Bell like any app's; clearing it is Don't allow ({@link #dismiss}). It also goes away when
        // the request ends.
        item.put("isClearable", true);
        item.put("canOpen", false);
        List<Map<String, Object>> actions = new ArrayList<>();
        actions.add(action(ALLOW, context.getString(R.string.household_join_allow)));
        actions.add(action(DENY, context.getString(R.string.household_join_deny)));
        item.put("actions", actions);
        list.add(item);
    }

    /** One of Hearth's items' buttons pressed. Whether it did something. */
    static boolean open(String key, int action) {
        if (!JOIN_KEY.equals(key) || (action != ALLOW && action != DENY)) return false;
        boolean answered = HouseholdJoining.answer(action == ALLOW);
        if (answered) LauncherNotificationListenerService.hearthItemsChanged();
        return answered;
    }

    /** One of Hearth's items cleared: a TV asking to join isn't allowed. */
    static boolean dismiss(String key) {
        return open(key, DENY);
    }

    private static Map<String, Object> action(int index, String title) {
        Map<String, Object> out = new HashMap<>();
        out.put("index", index);
        out.put("title", title);
        return out;
    }
}
