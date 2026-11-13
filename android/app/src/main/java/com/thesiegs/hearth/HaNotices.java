package com.thesiegs.hearth;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.Collections;
import java.util.HashSet;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;

/**
 * The Hearth integration's notices (docs/home-assistant-integration.md): its state document's {@code notices}, for a
 * TV whose status declares the cap "notices". Each goes in the Bell the way a Home Assistant notification does
 * (Household: a tag replaces, {@code for} names the person, none is every adult), but only ever in adult profiles, and
 * one gone from the document is cleared on every TV. A button is pressed by asking the integration
 * ({@code POST /api/hearth/device/<id>/notice}) with a Parent PIN or a parent's phone, never by calling a service.
 * Nothing here knows about Android, so the rules can be tested alone.
 */
final class HaNotices {
    /** The notice's key in the household entry's value (HouseholdNotices.parse tells the integration's by it). */
    static final String KEY = "k";
    private static final String ACTIONS = "na";
    private static final String URGENCY = "ur";
    private static final String EXPIRES = "ex";
    static final String INFO = "info";
    static final String NOTICE = "notice";
    static final String URGENT = "urgent";
    /** Kept apart from Home Assistant's own tags (port 7676), so the two never replace each other. */
    private static final String TAG_PREFIX = "hearth-notice|";
    /** A document's notices taken at most. */
    static final int MAX_NOTICES = 30;
    static final int MAX_KEY = 200;

    /** One notice as the document has it. */
    static final class Item {
        final String key;
        final String tag;
        final String title;
        final String message;
        /** Who it's for (a person ref, "person.alex"); null: every adult. */
        final String target;
        final String urgency;
        final List<HouseholdNotices.Action> actions;
        /** When it goes (epoch ms), or null. */
        final Long expiresMs;

        Item(String key, String tag, String title, String message, String target, String urgency,
                List<HouseholdNotices.Action> actions, Long expiresMs) {
            this.key = key;
            this.tag = tag;
            this.title = title;
            this.message = message;
            this.target = target;
            this.urgency = urgency;
            this.actions = actions;
            this.expiresMs = expiresMs;
        }
    }

    private HaNotices() {
    }

    // ---- The document ----

    /** The document's notices, checked; none when it has none (absent, or not a list). Unknown fields are ignored. */
    static List<Item> fromDocument(JSONObject state) {
        List<Item> out = new ArrayList<>();
        JSONArray list = state != null ? state.optJSONArray("notices") : null;
        if (list == null) return out;
        Set<String> keys = new HashSet<>();
        for (int i = 0; i < list.length() && out.size() < MAX_NOTICES; i++) {
            Item item = item(list.optJSONObject(i));
            if (item != null && keys.add(item.key)) out.add(item);
        }
        return out;
    }

    private static Item item(JSONObject o) {
        if (o == null) return null;
        String key = o.optString("key", "").trim();
        if (!validKey(key)) return null;
        String title = clip(o.optString("title", ""), HouseholdNotices.MAX_TITLE);
        String message = clip(o.optString("message", ""), HouseholdNotices.MAX_TEXT);
        if (title.isEmpty() && message.isEmpty()) return null;
        String tag = clip(o.optString("tag", ""), MAX_KEY);
        if (tag.isEmpty()) tag = key;
        String target = o.isNull("for") ? "" : clip(o.optString("for", ""), HaNotificationServer.MAX_NAME_CHARS);
        List<HouseholdNotices.Action> actions = new ArrayList<>();
        JSONArray buttons = o.optJSONArray("actions");
        Set<String> ids = new HashSet<>();
        for (int i = 0; buttons != null && i < buttons.length()
                && actions.size() < HaNotificationServer.MAX_ACTIONS; i++) {
            JSONObject b = buttons.optJSONObject(i);
            if (b == null) continue;
            HouseholdNotices.Action a = action(b.opt("id"), b.optString("title", ""));
            if (a != null && ids.add(a.id)) actions.add(a);
        }
        return new Item(key, tag, title, message, target.isEmpty() ? null : target, urgency(o.optString("urgency")),
                Collections.unmodifiableList(actions), expires(o.opt("expires")));
    }

    /** A notice's key: something, not too long, and nothing that isn't printable. */
    static boolean validKey(String key) {
        if (key == null || key.isEmpty() || key.length() > MAX_KEY) return false;
        for (int i = 0; i < key.length(); i++) {
            if (Character.isISOControl(key.charAt(i))) return false;
        }
        return true;
    }

    /** A button: an id "0", "1" or "2" (a number too) and a title; null when it isn't one. */
    private static HouseholdNotices.Action action(Object id, String title) {
        String i = id instanceof Number ? String.valueOf(((Number) id).intValue()) : id instanceof String
                ? ((String) id).trim() : "";
        if (!i.matches("[0-2]")) return null;
        String t = clip(title, HouseholdNotices.MAX_TITLE);
        return t.isEmpty() ? null : new HouseholdNotices.Action(i, t);
    }

    private static String urgency(String value) {
        String u = value == null ? "" : value.trim().toLowerCase(Locale.ROOT);
        return NOTICE.equals(u) || URGENT.equals(u) ? u : INFO;
    }

    /** An ISO date-time with an offset (as the integration sends it), or epoch seconds or ms; null otherwise. */
    static Long expires(Object value) {
        if (value instanceof Number) {
            long n = ((Number) value).longValue();
            if (n <= 0) return null;
            return n < 100_000_000_000L ? n * 1000 : n;
        }
        return value instanceof String ? HaLocks.parseTime((String) value) : null;
    }

    // ---- In the household's log ----

    /** The Bell's item of a notice for {@code person} (its tag's, so a later one with that tag replaces it). */
    static String item(String person, Item n) {
        return HouseholdNotices.haItem(person, TAG_PREFIX + n.tag, null, null);
    }

    /** The household entry's value of a notice written now; null when it has already gone past its time. */
    static String value(Item n, long nowMs) {
        if (n.expiresMs != null && n.expiresMs <= nowMs) return null;
        long until = nowMs + HouseholdNotices.MAX_AGE_MS;
        if (n.expiresMs != null) until = Math.min(until, n.expiresMs);
        try {
            JSONObject o = new JSONObject().put("f", HouseholdNotices.FROM_HA).put("ti", n.title).put("tx", n.message)
                    .put("at", nowMs).put("u", until).put(KEY, n.key).put(URGENCY, n.urgency);
            if (n.expiresMs != null) o.put(EXPIRES, n.expiresMs);
            if (!n.actions.isEmpty()) {
                JSONArray list = new JSONArray();
                for (HouseholdNotices.Action a : n.actions) list.put(new JSONObject().put("id", a.id).put("ti", a.title));
                o.put(ACTIONS, list);
            }
            return o.toString();
        } catch (JSONException e) {
            throw new IllegalStateException(e);
        }
    }

    /**
     * Whether two values say the same (when written aside): the document is read again and again, and an unchanged
     * notice isn't written again (that would pop it up again, and send it to every TV for nothing).
     */
    static boolean same(String a, String b) {
        if (a == null || b == null) return false;
        try {
            JSONObject x = new JSONObject(a);
            JSONObject y = new JSONObject(b);
            for (String field : new String[] {"f", "ti", "tx", KEY, URGENCY}) {
                if (!x.optString(field, "").equals(y.optString(field, ""))) return false;
            }
            if (x.optLong(EXPIRES, 0) != y.optLong(EXPIRES, 0)) return false;
            return actionsIn(x).size() == actionsIn(y).size() && String.valueOf(x.optJSONArray(ACTIONS))
                    .equals(String.valueOf(y.optJSONArray(ACTIONS)));
        } catch (JSONException e) {
            return false;
        }
    }

    /** The buttons in an entry's value, checked again as they're read (another TV wrote it). */
    static List<HouseholdNotices.Action> actionsIn(JSONObject value) {
        JSONArray list = value.optJSONArray(ACTIONS);
        if (list == null) return Collections.emptyList();
        List<HouseholdNotices.Action> out = new ArrayList<>();
        Set<String> ids = new HashSet<>();
        for (int i = 0; i < list.length() && out.size() < HaNotificationServer.MAX_ACTIONS; i++) {
            JSONObject b = list.optJSONObject(i);
            if (b == null) continue;
            HouseholdNotices.Action a = action(b.opt("id"), b.optString("ti", ""));
            if (a != null && ids.add(a.id)) out.add(a);
        }
        return Collections.unmodifiableList(out);
    }

    static String urgencyIn(JSONObject value) {
        return urgency(value.optString(URGENCY, INFO));
    }

    /** Whether a notice pops up as it comes (an "info" one waits in the Bell). */
    static boolean popsUp(String urgency) {
        return !INFO.equals(urgency);
    }

    // ---- Cleared when gone from the document ----

    /** One notice filed here: who it's for and its Bell item, as one string. */
    static String filed(String person, String item) {
        return person + "\n" + item;
    }

    static String personOf(String filed) {
        return filed.substring(0, filed.indexOf('\n'));
    }

    static String itemOf(String filed) {
        return filed.substring(filed.indexOf('\n') + 1);
    }

    /** What was filed from an earlier document and isn't in this one: the integration cleared it. */
    static Set<String> gone(Set<String> before, Set<String> now) {
        Set<String> out = new LinkedHashSet<>(before);
        out.removeAll(now);
        return out;
    }

    static JSONArray toJson(Set<String> filed) {
        return new JSONArray(filed);
    }

    static Set<String> fromJson(String json) {
        Set<String> out = new LinkedHashSet<>();
        if (json == null) return out;
        try {
            JSONArray list = new JSONArray(json);
            for (int i = 0; i < list.length(); i++) {
                String s = list.optString(i, "");
                // Every adult's person is "": the line break may come first
                if (s.indexOf('\n') >= 0) out.add(s);
            }
        } catch (JSONException ignored) {
            // None kept
        }
        return out;
    }

    // ---- A button pressed ----

    /** How the integration answered a press. */
    enum Outcome {
        /** Run, as the adult whose PIN it was. */
        DONE,
        /** Sent to the adults' phones; the tap there runs it. */
        PENDING,
        /** The notice no longer exists: it's cleared here. */
        GONE,
        /** Not a parent PIN (maybe locked out: {@link Result#retryAfterS}). */
        WRONG_PIN,
        TOO_MANY,
        BAD_REQUEST,
        /** An older integration without the endpoint: the adult answers on their phone. */
        UNSUPPORTED,
        /** The integration no longer knows this TV (401). */
        NOT_PAIRED,
        UNREACHABLE,
        FAILED
    }

    static final class Result {
        final Outcome outcome;
        /** With {@link Outcome#WRONG_PIN}: seconds the PIN pad waits (0: it doesn't). */
        final int retryAfterS;

        Result(Outcome outcome, int retryAfterS) {
            this.outcome = outcome;
            this.retryAfterS = Math.max(0, retryAfterS);
        }
    }

    /** The press's body: with a PIN, or (null) asking the adults' phones. */
    static JSONObject pressBody(String key, String actionId, String pin) {
        try {
            JSONObject body = new JSONObject().put("key", key).put("action", Integer.parseInt(actionId));
            return pin != null ? body.put("pin", pin) : body.put("approval", "phone");
        } catch (JSONException | NumberFormatException e) {
            throw new IllegalArgumentException("Not a notice's button: " + actionId);
        }
    }

    /**
     * The integration's answer: {ok, done} or {ok, pending}; errors by code and {error}. A 404 is the notice gone
     * only when it says so ("gone"); any other 404 is an integration without the endpoint. 403 not_local, 503
     * not_set_up and 500 failed are FAILED.
     */
    static Result outcome(int code, JSONObject body) {
        String error = body != null ? body.optString("error", "") : "";
        if (code == 200 && body != null && body.optBoolean("ok", false)) {
            if (!body.optBoolean("done", false) && !body.optString("pending", "").isEmpty()) {
                return new Result(Outcome.PENDING, 0);
            }
            return new Result(Outcome.DONE, 0);
        }
        if (code == 404) return new Result("gone".equals(error) ? Outcome.GONE : Outcome.UNSUPPORTED, 0);
        if (code == 403 && "wrong_pin".equals(error)) {
            return new Result(Outcome.WRONG_PIN, body.optInt("retry_after", 0));
        }
        if (code == 429) return new Result(Outcome.TOO_MANY, 0);
        if (code == 401) return new Result(Outcome.NOT_PAIRED, 0);
        if (code == 400) return new Result(Outcome.BAD_REQUEST, 0);
        if (code == 0) return new Result(Outcome.UNREACHABLE, 0);
        return new Result(Outcome.FAILED, 0);
    }

    private static String clip(String s, int max) {
        String t = s == null ? "" : s.trim();
        return t.length() > max ? t.substring(0, max) : t;
    }
}
