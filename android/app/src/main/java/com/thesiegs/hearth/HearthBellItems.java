package com.thesiegs.hearth;

import android.content.Context;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * What Hearth lists in its notification Bell itself, beside the apps' notifications: a TV asking this one to join the
 * household (HouseholdJoining), with Allow and Don't allow, only for adults (never while a kids profile is on); and the
 * household's notifications for the profile on screen (Household.notices: Home Assistant's, and a TV asking another TV
 * of the household to join, answered from here). Clearing one of those here clears it on every TV, and so does
 * pressing one of a Home Assistant notification's buttons (Household.pressNotice runs it once).
 */
final class HearthBellItems {
    private static final String PREFIX = "hearth:";
    static final String JOIN_KEY = PREFIX + "household-join";
    /** A household notification's key: this, its item, "|" and its person (an item never holds a "|"). */
    private static final String NOTICE_PREFIX = PREFIX + "notice:";
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
     * adult who came on; a kids profile's Bell loses it. The household's notifications follow the profile too.
     */
    static void profileChanged(Context context) {
        Household.noticesProfileChanged(context);
        String joiner = HouseholdJoining.requestName();
        if (joiner == null) return;
        LauncherNotificationListenerService.hearthItemsChanged();
        if (!ProfileUsers.isKids(context)) {
            LauncherNotificationListenerService.popUpHearthItem(context.getString(R.string.household_join_bell_app),
                    context.getString(R.string.household_join_bell_title, joiner),
                    context.getString(R.string.household_join_bell_text));
        }
    }

    /** A household notification that came from another TV pops up (Household decides when). */
    static void popUp(Context context, HouseholdNotices.Notice n) {
        if (!n.actions.isEmpty()) {
            // With its buttons, as Home Assistant's own card: pressed here, it runs once and goes from every TV
            HaNotificationServer.Notification card = new HaNotificationServer.Notification();
            card.title = n.title;
            card.message = n.text;
            for (HouseholdNotices.Action a : n.actions) card.actions.add(a.asSent());
            card.onAction = index -> Household.pressNotice(context, n.person, n.item, n.at, index);
            if (LauncherAccessibilityService.showHaNotification(card)) return;
        }
        String[] shown = texts(context, n);
        LauncherNotificationListenerService.popUpHearthItem(shown[0], shown[1], shown[2]);
    }

    /** Adds Hearth's items to the Bell's list, in its form; a kids profile sees only what is for that kid. */
    static void addTo(Context context, List<Map<String, Object>> list) {
        String joiner = HouseholdJoining.requestName();
        if (joiner != null && !ProfileUsers.isKids(context)) {
            long posted;
            synchronized (HearthBellItems.class) {
                posted = sJoinPosted > 0 ? sJoinPosted : System.currentTimeMillis();
            }
            // Counted on the Bell like any app's; clearing it is Don't allow ({@link #dismiss}). It also goes away
            // when the request ends.
            list.add(item(context, JOIN_KEY, context.getString(R.string.household_join_bell_app),
                    context.getString(R.string.household_join_bell_title, joiner),
                    context.getString(R.string.household_join_bell_text), posted, true));
        }
        long now = System.currentTimeMillis();
        for (HouseholdNotices.Notice n : Household.notices(context)) {
            if (now >= n.until) continue;
            String[] shown = texts(context, n);
            Map<String, Object> item = item(context, NOTICE_PREFIX + n.item + "|" + n.person, shown[0], shown[1],
                    shown[2], n.at, n.isJoin());
            if (!n.isJoin()) {
                // Home Assistant's buttons, numbered as in the notification (Household.pressNotice)
                @SuppressWarnings("unchecked")
                List<Map<String, Object>> actions = (List<Map<String, Object>>) item.get("actions");
                for (int i = 0; i < n.actions.size(); i++) actions.add(action(i, n.actions.get(i).title));
                // They act on the home: the Bell opens its options on Dismiss, as the pop-up's card on Close
                item.put("carefulActions", !n.actions.isEmpty());
            }
            list.add(item);
        }
    }

    /** A household notification's app name, title and text, as the Bell and its pop-up show them. */
    private static String[] texts(Context context, HouseholdNotices.Notice n) {
        if (n.isJoin()) {
            String joiner = n.joiner.isEmpty() ? context.getString(R.string.household_join_unnamed) : n.joiner;
            String asked = n.askedName.isEmpty() ? context.getString(R.string.household_join_asked_unnamed)
                    : n.askedName;
            return new String[] {context.getString(R.string.household_join_bell_app),
                    context.getString(R.string.household_join_bell_title, joiner),
                    context.getString(R.string.household_join_bell_text_other, asked)};
        }
        return new String[] {context.getString(R.string.ha_notification_bell_app), n.title, n.text};
    }

    private static Map<String, Object> item(Context context, String key, String label, String title, String text,
            long posted, boolean join) {
        Map<String, Object> item = new HashMap<>();
        item.put("key", key);
        item.put("packageName", context.getPackageName());
        item.put("appLabel", label);
        item.put("title", title);
        item.put("text", text);
        item.put("postTime", posted);
        item.put("isClearable", true);
        item.put("canOpen", false);
        List<Map<String, Object>> actions = new ArrayList<>();
        if (join) {
            actions.add(action(ALLOW, context.getString(R.string.household_join_allow)));
            actions.add(action(DENY, context.getString(R.string.household_join_deny)));
        }
        item.put("actions", actions);
        return item;
    }

    /** One of Hearth's items' buttons pressed. Whether it did something. */
    static boolean open(Context context, String key, int action) {
        String[] notice = noticeOf(key);
        if (notice != null && HouseholdNotices.requestIdOf(notice[0]) == null) {
            // A Home Assistant notification's button: run once, and the notification goes from every TV
            return Household.pressNotice(context, notice[1], notice[0], action);
        }
        if (action != ALLOW && action != DENY) return false;
        if (JOIN_KEY.equals(key)) {
            boolean answered = HouseholdJoining.answer(action == ALLOW);
            if (answered) LauncherNotificationListenerService.hearthItemsChanged();
            return answered;
        }
        if (notice == null) return false;
        return Household.answerJoin(context, notice[0], action == ALLOW);
    }

    /**
     * One of Hearth's items cleared: a TV asking to join isn't allowed; a household notification goes from every TV's
     * Bell.
     */
    static boolean dismiss(Context context, String key) {
        String[] notice = noticeOf(key);
        if (notice == null) return open(context, key, DENY);
        if (HouseholdNotices.requestIdOf(notice[0]) != null) return Household.answerJoin(context, notice[0], false);
        Household.clearNotice(context, notice[1], notice[0]);
        return true;
    }

    /** Clear all: the household's notifications the profile on screen sees go too (not a TV asking to join). */
    static void clearAll(Context context) {
        Household.clearNotices(context);
    }

    /** {item, person} of a household notification's key, or null when it isn't one. */
    private static String[] noticeOf(String key) {
        if (key == null || !key.startsWith(NOTICE_PREFIX)) return null;
        String rest = key.substring(NOTICE_PREFIX.length());
        int bar = rest.indexOf('|');
        return bar <= 0 ? null : new String[] {rest.substring(0, bar), rest.substring(bar + 1)};
    }

    private static Map<String, Object> action(int index, String title) {
        Map<String, Object> out = new HashMap<>();
        out.put("index", index);
        out.put("title", title);
        return out;
    }
}
