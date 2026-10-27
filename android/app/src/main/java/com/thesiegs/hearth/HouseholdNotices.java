package com.thesiegs.hearth;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * Notifications that follow the household (docs/household-sync.md, "Notifications"): Home Assistant's, and a TV asking
 * to join. Each is a {@link #KIND} entry: the person it is for (a person id; {@link #ALL_ADULTS} for every adult), an
 * item naming it, and its text as the value. Cleared is a delete, so it goes from every TV; the newest write wins as for
 * any entry. A join request's answer from another TV is an {@link #ANSWER} entry, which the TV holding the request takes
 * (the first it sees decides). A Home Assistant notification carries its buttons; one pressed on a TV without its own
 * Home Assistant connection is a {@link #PRESS} entry, which the TV that received the notification takes, once
 * ({@link #due}). All three kinds leave every TV's log after {@link #MAX_AGE_MS}. Nothing here knows about Android, so
 * the rules can be tested alone.
 */
final class HouseholdNotices {
    static final String KIND = "notice";
    static final String ANSWER = "join_answer";
    /** A Home Assistant notification's button pressed on a TV that asks the one that received it to run it. */
    static final String PRESS = "notice_press";
    /** The person of a notification for every adult: the whole household's, as for a setting of the whole TV. */
    static final String ALL_ADULTS = HouseholdBridge.SHARED;
    static final String FROM_HA = "ha";
    static final String FROM_JOIN = "join";
    /** How long a notification stays (in the Bell and in the log), answered, cleared or not. */
    static final long MAX_AGE_MS = 3L * 24 * 60 * 60 * 1000;
    /** A notification that came from another TV pops up there only while it is this new. */
    static final long POP_UP_MS = 2 * 60_000;
    static final int MAX_TITLE = 200;
    static final int MAX_TEXT = 1000;
    /** Home Assistant notifications one TV keeps in the household's log at most (each stays three days). */
    static final int MAX_FROM_TV = 300;
    /** A button's data (as JSON) longer than this isn't carried to the other TVs. */
    static final int MAX_ACTION_DATA = 1000;
    /** A press the receiving TV hears later than this isn't run (an "Unlock door" mustn't happen long after). */
    static final long PRESS_MS = 2 * 60_000;
    private static final String JOIN_PREFIX = "join:";

    /** One of a Home Assistant notification's buttons, as Home Assistant sent it and HaNotificationServer allowed. */
    static final class Action {
        final String title;
        /** "domain.service". */
        final String service;
        /** The service's data as JSON ("{}" for none). */
        final String data;

        Action(String title, String service, String data) {
            this.title = title;
            this.service = service;
            this.data = data;
        }

        JSONObject dataObject() {
            try {
                return new JSONObject(data);
            } catch (JSONException e) {
                return new JSONObject();
            }
        }

        /** As HaNotificationServer.Notification holds a button: {"title", "service", "data"}. */
        JSONObject asSent() {
            try {
                return new JSONObject().put("title", title).put("service", service).put("data", dataObject());
            } catch (JSONException e) {
                throw new IllegalStateException(e);
            }
        }
    }

    /** A pressed button the TV holding the notification runs: {@link #action} null when the press came too late. */
    static final class Due {
        final Notice notice;
        final Action action;

        Due(Notice notice, Action action) {
            this.notice = notice;
            this.action = action;
        }
    }

    /** One notification as the Bell shows it. */
    static final class Notice {
        final String item;
        final String person;
        final String from;
        final String title;
        final String text;
        /** When it was written, by the writing TV's clock. */
        final long at;
        /** When it goes from the Bell even if no one clears it. */
        final long until;
        /** The TV that wrote it. */
        final String writer;
        /** A join request: the TV that asked to join, and the household's TV it asked (its id and name). */
        final String joiner;
        final String askedTv;
        final String askedName;
        /** A Home Assistant notification's buttons (checked again where read); empty for others. */
        final List<Action> actions;

        Notice(String item, String person, String from, String title, String text, long at, long until, String writer,
                String joiner, String askedTv, String askedName) {
            this(item, person, from, title, text, at, until, writer, joiner, askedTv, askedName,
                    Collections.<Action>emptyList());
        }

        Notice(String item, String person, String from, String title, String text, long at, long until, String writer,
                String joiner, String askedTv, String askedName, List<Action> actions) {
            this.item = item;
            this.person = person;
            this.from = from;
            this.title = title;
            this.text = text;
            this.at = at;
            this.until = until;
            this.writer = writer;
            this.joiner = joiner;
            this.askedTv = askedTv;
            this.askedName = askedName;
            this.actions = actions;
        }

        boolean isJoin() {
            return FROM_JOIN.equals(from);
        }
    }

    /** A profile on this TV, for finding who a notification is for. */
    static final class Person {
        final String key;
        final String id;
        final String name;
        final String email;

        Person(String key, String id, String name, String email) {
            this.key = key;
            this.id = id;
            this.name = name;
            this.email = email;
        }
    }

    private HouseholdNotices() {
    }

    // ---- Home Assistant's ----

    /**
     * A Home Assistant notification's item: by its {@code tag} when it has one (a later one with the same tag replaces
     * it, as on Home Assistant's phone app), else by what it says, so the same notification sent to every TV of the
     * household is one notification, not one per TV.
     */
    static String haItem(String person, String tag, String title, String text) {
        String what = !isBlank(tag) ? "t|" + person + "|" + tag.trim()
                : "c|" + person + "|" + nonNull(title).trim() + "|" + nonNull(text).trim();
        return FROM_HA + ":" + digest(what);
    }

    /** A Home Assistant notification's value; null when it says nothing (a camera alone has nothing for the Bell). */
    static String haValue(String title, String text, long nowMs) {
        return haValue(title, text, null, nowMs);
    }

    /**
     * The same, with its buttons ({@code actions}, as HaNotificationServer allowed them). They are carried only when
     * every one of them can be ({@link #carried}), so a button's number is the same on every TV and in the pop-up.
     */
    static String haValue(String title, String text, List<JSONObject> actions, long nowMs) {
        String t = clip(title, MAX_TITLE);
        String x = clip(text, MAX_TEXT);
        if (t.isEmpty() && x.isEmpty()) return null;
        try {
            JSONObject o = new JSONObject().put("f", FROM_HA).put("ti", t).put("tx", x).put("at", nowMs)
                    .put("u", nowMs + MAX_AGE_MS);
            List<Action> carried = carried(actions);
            if (!carried.isEmpty()) {
                JSONArray list = new JSONArray();
                for (Action a : carried) {
                    list.put(new JSONObject().put("ti", a.title).put("s", a.service).put("d", a.data));
                }
                o.put("ac", list);
            }
            return o.toString();
        } catch (JSONException e) {
            throw new IllegalStateException(e);
        }
    }

    /**
     * The buttons that go in the household's entry: all of {@code actions}, or none when any of them isn't allowed
     * (HaNotificationServer.allowedAction), is too long, or there are more than HaNotificationServer.MAX_ACTIONS.
     * What travels is checked the same way again where it is read ({@link #parse}), so an entry from another TV can't
     * hold a button Home Assistant's own notification couldn't.
     */
    static List<Action> carried(List<JSONObject> actions) {
        if (actions == null || actions.isEmpty() || actions.size() > HaNotificationServer.MAX_ACTIONS) {
            return Collections.emptyList();
        }
        List<Action> out = new ArrayList<>();
        for (JSONObject a : actions) {
            Action ok = action(a);
            if (ok == null) return Collections.emptyList();
            out.add(ok);
        }
        return Collections.unmodifiableList(out);
    }

    /** {@code a} ({"title", "service", "data"}) as a button the household may carry, or null. */
    private static Action action(JSONObject a) {
        if (!HaNotificationServer.allowedAction(a)) return null;
        String title = a.optString("title").trim();
        if (title.length() > MAX_TITLE) return null;
        JSONObject data = a.optJSONObject("data");
        String json = data == null ? "{}" : data.toString();
        if (json.length() > MAX_ACTION_DATA) return null;
        return new Action(title, a.optString("service"), json);
    }

    /** The buttons in an entry's value, checked as when they came from Home Assistant; none when any isn't allowed. */
    private static List<Action> actionsIn(JSONObject value) {
        JSONArray list = value.optJSONArray("ac");
        if (list == null || list.length() == 0 || list.length() > HaNotificationServer.MAX_ACTIONS) {
            return Collections.emptyList();
        }
        List<JSONObject> asSent = new ArrayList<>();
        try {
            for (int i = 0; i < list.length(); i++) {
                JSONObject a = list.getJSONObject(i);
                String d = a.getString("d");
                if (d.length() > MAX_ACTION_DATA) return Collections.emptyList();
                asSent.add(new JSONObject().put("title", a.getString("ti")).put("service", a.getString("s"))
                        .put("data", new JSONObject(d)));
            }
        } catch (JSONException e) {
            return Collections.emptyList();
        }
        return carried(asSent);
    }

    // ---- Its buttons, pressed on any TV ----

    /** A press of button {@code index} of the notification written at {@code noticeAt} (its {@link Notice#at}). */
    static String pressValue(int index, long noticeAt) {
        try {
            return new JSONObject().put("a", index).put("at", noticeAt).toString();
        } catch (JSONException e) {
            throw new IllegalStateException(e);
        }
    }

    /** The button pressed for {@code n}, or -1 when none was (a press for an older one with the same item isn't). */
    static int pressed(List<HouseholdEntry> entries, Notice n) {
        for (HouseholdEntry e : entries) {
            if (!PRESS.equals(e.kind) || e.deleted || !e.item.equals(n.item) || !e.profile.equals(n.person)) continue;
            return pressIndex(e, n);
        }
        return -1;
    }

    private static int pressIndex(HouseholdEntry press, Notice n) {
        try {
            JSONObject o = new JSONObject(press.value);
            if (o.getLong("at") != n.at) return -1;
            int index = o.getInt("a");
            return index >= 0 && index < n.actions.size() ? index : -1;
        } catch (JSONException ex) {
            return -1;
        }
    }

    /**
     * The presses this TV ({@code ownTv}) runs: one for each Home Assistant notification it wrote and still holds whose
     * button another TV pressed. The TV deletes each notification before running it, so a press runs at most once and
     * the notification goes from every Bell. One heard more than {@link #PRESS_MS} from when it was pressed only clears
     * it ({@link Due#action} null). The button run is always the one in this TV's own copy of the notification, by its
     * number, so a press can't name a service of its own.
     */
    static List<Due> due(List<HouseholdEntry> entries, String ownTv, long nowMs) {
        Map<String, HouseholdEntry> presses = new HashMap<>();
        for (HouseholdEntry e : entries) {
            if (PRESS.equals(e.kind) && !e.deleted) presses.put(e.profile + "|" + e.item, e);
        }
        List<Due> out = new ArrayList<>();
        if (presses.isEmpty() || ownTv == null) return out;
        for (HouseholdEntry e : entries) {
            if (!e.tv.equals(ownTv)) continue;
            Notice n = parse(e);
            if (n == null || n.actions.isEmpty() || nowMs >= n.until) continue;
            HouseholdEntry press = presses.get(n.person + "|" + n.item);
            if (press == null) continue;
            int index = pressIndex(press, n);
            if (index < 0) continue;
            boolean late = Math.abs(nowMs - HouseholdLog.millisOf(press)) > PRESS_MS;
            out.add(new Due(n, late ? null : n.actions.get(index)));
        }
        return out;
    }

    /**
     * Who a notification sent with {@code wanted} is for, among this TV's profiles: the person id of the one whose key
     * (as Hearth's Home Assistant integration names profiles, "user:10"), Google account address or name it is. Null
     * when none is, or two profiles have that name.
     */
    static String target(String wanted, List<Person> people) {
        if (isBlank(wanted)) return null;
        String w = wanted.trim();
        for (Person p : people) {
            if (p.id != null && w.equals(p.key)) return p.id;
        }
        for (Person p : people) {
            if (p.id != null && p.email != null && w.equalsIgnoreCase(p.email.trim())) return p.id;
        }
        String found = null;
        String name = HouseholdEntry.normalize(w);
        for (Person p : people) {
            if (p.id == null || !name.equals(HouseholdEntry.normalize(p.name))) continue;
            if (found != null && !found.equals(p.id)) return null;
            found = p.id;
        }
        return found;
    }

    /**
     * Whether this TV ({@code tv}, as it signs entries) may file the Home Assistant notification {@code item}: one
     * already held (the same tag, or the same text again) always may; a new one only while fewer than
     * {@link #MAX_FROM_TV} of this TV's are held. Home Assistant's port takes posts from anything on the network
     * without a password, and each new one is an entry every TV keeps for three days, so a flood mustn't grow the log
     * (and every save and exchange of it) without end; what doesn't fit still pops up here, it just isn't in the Bells.
     */
    static boolean roomFor(java.util.Collection<HouseholdEntry> entries, String tv, String item) {
        int held = 0;
        for (HouseholdEntry e : entries) {
            if (!KIND.equals(e.kind) || !e.item.startsWith(FROM_HA + ":")) continue;
            if (e.item.equals(item)) return true;
            if (e.tv.equals(tv)) held++;
        }
        return held < MAX_FROM_TV;
    }

    // ---- A TV asking to join ----

    /** The item of the join request numbered {@code requestId} (random, made by the TV that was asked). */
    static String joinItem(String requestId) {
        return JOIN_PREFIX + requestId;
    }

    /** The request id in a join request's item, or null when it isn't one. */
    static String requestIdOf(String item) {
        return item != null && item.startsWith(JOIN_PREFIX) && item.length() > JOIN_PREFIX.length()
                ? item.substring(JOIN_PREFIX.length()) : null;
    }

    static String joinValue(String joiner, String askedTv, String askedName, long nowMs, long untilMs) {
        try {
            return new JSONObject().put("f", FROM_JOIN).put("j", clip(joiner, MAX_TITLE)).put("tv", nonNull(askedTv))
                    .put("tn", clip(askedName, MAX_TITLE)).put("at", nowMs).put("u", untilMs).toString();
        } catch (JSONException e) {
            throw new IllegalStateException(e);
        }
    }

    static String answerValue(boolean allow) {
        return allow ? "{\"allow\":true}" : "{\"allow\":false}";
    }

    /** The answer the household gave to the join request {@code item}: true Allow, false Don't allow, null none yet. */
    static Boolean answer(List<HouseholdEntry> entries, String item) {
        for (HouseholdEntry e : entries) {
            if (!ANSWER.equals(e.kind) || e.deleted || !e.item.equals(item)) continue;
            try {
                return new JSONObject(e.value).getBoolean("allow");
            } catch (JSONException ex) {
                return null;
            }
        }
        return null;
    }

    // ---- What the Bell shows ----

    /** The notification in a live {@link #KIND} entry, or null when it isn't one (a delete, or not well formed). */
    static Notice parse(HouseholdEntry e) {
        if (e == null || !KIND.equals(e.kind) || e.deleted) return null;
        try {
            JSONObject o = new JSONObject(e.value);
            String from = o.getString("f");
            long at = HouseholdLog.millisOf(e);
            long until = Math.min(o.optLong("u", at + MAX_AGE_MS), at + MAX_AGE_MS);
            if (FROM_HA.equals(from)) {
                String title = clip(o.optString("ti", ""), MAX_TITLE);
                String text = clip(o.optString("tx", ""), MAX_TEXT);
                if (title.isEmpty() && text.isEmpty()) return null;
                return new Notice(e.item, e.profile, from, title, text, at, until, e.tv, null, null, null,
                        actionsIn(o));
            }
            if (FROM_JOIN.equals(from)) {
                // Only for every adult, and only one the asked TV wrote about itself
                if (!ALL_ADULTS.equals(e.profile) || requestIdOf(e.item) == null) return null;
                String asked = o.optString("tv", "");
                if (!asked.equals(e.tv)) return null;
                return new Notice(e.item, e.profile, from, "", "", at, until, e.tv,
                        clip(o.optString("j", ""), MAX_TITLE), asked, clip(o.optString("tn", ""), MAX_TITLE));
            }
            return null;
        } catch (JSONException ex) {
            return null;
        }
    }

    /**
     * What the Bell shows the profile on screen ({@code person}, its person id; {@code kids}: a kids profile), newest
     * first: notifications for that person, and while an adult is on, those for every adult. Not ones gone past their
     * time, nor a join request this TV holds itself ({@code ownTv}: its own Bell item answers it) or one already
     * answered from a TV, nor a Home Assistant one whose button was pressed (it is being run, and goes everywhere).
     */
    static List<Notice> visible(List<HouseholdEntry> entries, String person, boolean kids, String ownTv, long nowMs) {
        List<Notice> out = new ArrayList<>();
        for (HouseholdEntry e : entries) {
            Notice n = parse(e);
            if (n == null || nowMs >= n.until) continue;
            if (ALL_ADULTS.equals(n.person)) {
                if (kids) continue;
            } else if (person == null || person.isEmpty() || !n.person.equals(person)) {
                continue;
            }
            if (n.isJoin() && (n.askedTv.equals(ownTv) || answer(entries, n.item) != null)) continue;
            if (!n.actions.isEmpty() && pressed(entries, n) >= 0) continue;
            out.add(n);
        }
        out.sort((a, b) -> Long.compare(b.at, a.at));
        return out;
    }

    /** Whether an entry is a notification (or an answer to one) gone past {@link #MAX_AGE_MS}: it leaves the log. */
    static boolean expired(HouseholdEntry e, long nowMs) {
        return (KIND.equals(e.kind) || ANSWER.equals(e.kind) || PRESS.equals(e.kind)) && nowMs - HouseholdLog.millisOf(e) > MAX_AGE_MS;
    }

    // ----

    private static String digest(String text) {
        try {
            byte[] d = MessageDigest.getInstance("SHA-256").digest(text.getBytes(StandardCharsets.UTF_8));
            return Hex.of(Arrays.copyOf(d, 12));
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException(e);
        }
    }

    private static String clip(String s, int max) {
        String t = nonNull(s).trim();
        return t.length() > max ? t.substring(0, max) : t;
    }

    private static String nonNull(String s) {
        return s == null ? "" : s;
    }

    private static boolean isBlank(String s) {
        return s == null || s.trim().isEmpty();
    }
}
