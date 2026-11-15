package com.thesiegs.hearth;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

/**
 * One phone's session on the remote API (docs/tv-remote-api.md "Session" and "Version 2"): its JSON messages in, the
 * TV's answers out, and the rules for its role. Knows nothing about sockets or Android: {@link Tv} does what's asked,
 * {@link Phone} is what the TV keeps about this phone. A hello with v 1 gets version 1 exactly; v 2 adds the told role
 * ({@code welcome}), {@code state.time}, request ids and the new messages.
 */
final class RemoteSession {
    /** The highest version the TV speaks (TXT {@code v}); a hello may say 1 or 2. */
    static final int VERSION = 2;

    static final String ROLE_NONE = "none";
    static final String ROLE_KID = "kid";
    static final String ROLE_PARENT = "parent";
    static final String MODE_LOCAL = "local";
    static final String MODE_HA = "ha";

    /** What the TV can do for a phone. Calls may throw {@link Refused} with an error code. */
    interface Tv {
        /** The state message's fields (without "t" and "time"). */
        JSONObject state();

        void media(String action) throws Refused;

        void seekTo(long positionMs) throws Refused;

        void seekBy(long deltaMs) throws Refused;

        void launch(String pkg) throws Refused;

        void volumeSet(int percent) throws Refused;

        void volumeStep(int direction) throws Refused;

        void mute(boolean muted) throws Refused;

        /** The current profile's apps: [{pkg, label}]. */
        JSONArray apps();

        /** Whether the current profile may open the app now (Hearth's holds, the profile's own blocks). */
        boolean allowed(String pkg);

        /** The art of the current title as a JPEG, or null; [id] is the state's artId. */
        byte[] art(String id);

        // --- Version 2

        /** {@link #MODE_HA} while the TV is paired with Home Assistant (its rules win), else {@link #MODE_LOCAL}. */
        default String mode() {
            return MODE_LOCAL;
        }

        /** The TV's clock (epoch ms). */
        default long now() {
            return System.currentTimeMillis();
        }

        /** The household's time zone (an IANA id). */
        default String zone() {
            return java.util.TimeZone.getDefault().getID();
        }

        /** The household day at {@code now}, "yyyy-MM-dd". */
        default String day(long now) {
            return java.time.Instant.ofEpochMilli(now).atZone(java.time.ZoneId.of(zone())).toLocalDate().toString();
        }

        /** The household's TVs a phone may trust, [{id, n}] (this TV's at least). */
        default JSONArray tvs() {
            return new JSONArray();
        }

        /** The profile in front's key (null: not known). */
        default String frontProfileKey() {
            return null;
        }

        /** A profile's allowance entry (HaAllowance.entryFor): null for an adult's profile or one without limits. */
        default JSONObject entry(String profileKey) {
            return null;
        }

        /** Who a kids profile is to the household: {id, name}; null when it isn't known. */
        default JSONObject person(String profileKey) {
            return null;
        }

        /** The kids profiles of this TV, by key. */
        default List<String> kids() {
            return Collections.emptyList();
        }

        /** A kid's rules as the remote API sends them (mode local; null: none), without {@code tag} and {@code tz}. */
        default JSONObject rules(String profileKey) {
            return null;
        }

        /**
         * Asks Home Assistant for more time for the kid (HaIntegration.ask's answer: {ok, request} or {error,
         * retry_in?, request?}).
         */
        default JSONObject askHomeAssistant(String profileKey, int minutes, String group) {
            return new JSONObject();
        }
    }

    /** What the TV keeps about this phone, read from its own store on every message (never from the phone's word). */
    interface Phone {
        /** Its role, as an adult bound it (or v1's adult mark). */
        Binding binding();

        /** Forgets this phone (unpair). */
        void unpair();

        /** Another app on the phone is Hearth's agent there: this pairing becomes "not this one". */
        void standDown();

        /** The kid's last ask over the remote API: {ask, req, minutes, group, at, pending, told}; null: none. */
        JSONObject lastAsk();

        void setLastAsk(JSONObject ask);
    }

    /** A phone's told role: {@link #ROLE_NONE}, {@link #ROLE_KID} (with the kid's profile) or {@link #ROLE_PARENT}. */
    static final class Binding {
        final String role;
        /** The kid's profile key on this TV, for {@link #ROLE_KID}; else null. */
        final String profileKey;

        Binding(String role, String profileKey) {
            this.role = ROLE_KID.equals(role) && profileKey != null ? ROLE_KID
                    : ROLE_PARENT.equals(role) ? ROLE_PARENT : ROLE_NONE;
            this.profileKey = ROLE_KID.equals(this.role) ? profileKey : null;
        }

        boolean kid() {
            return ROLE_KID.equals(role);
        }

        boolean parent() {
            return ROLE_PARENT.equals(role);
        }
    }

    static final class Refused extends Exception {
        final String code;
        final Integer retryInSec;

        Refused(String code) {
            this(code, null);
        }

        Refused(String code, Integer retryInSec) {
            super(code);
            this.code = code;
            this.retryInSec = retryInSec;
        }
    }

    static final String NOT_PAIRED = "not_paired";
    static final String NOT_ALLOWED = "not_allowed";
    static final String UNSUPPORTED = "unsupported";
    static final String NO_SESSION = "no_session";
    static final String BAD_REQUEST = "bad_request";
    static final String FORBIDDEN = "forbidden";
    static final String NOT_BOUND = "not_bound";
    static final String HA_RULES = "ha_rules";
    static final String TOO_OFTEN = "too_often";
    static final int MAX_ART = 64 * 1024;
    static final int MAX_ID = 64;
    static final int MAX_ASK_MINUTES = 240;
    /** An ask Home Assistant hasn't said anything about for this long counts as expired. */
    static final long ASK_UNHEARD_MS = 60 * 60 * 1000;

    private final Tv tv;
    private final Phone phone;
    private int version;
    private boolean saidKid;
    private boolean started;
    private boolean ended;
    private String lastState;
    private int lastMinutesLeft = -1;

    /** [adultPhone]: an adult marked this phone as an adult's in Settings; anything else is restricted. */
    RemoteSession(Tv tv, boolean adultPhone) {
        this(tv, new Fixed(new Binding(adultPhone ? ROLE_PARENT : ROLE_NONE, null)));
    }

    RemoteSession(Tv tv, Phone phone) {
        this.tv = tv;
        this.phone = phone;
    }

    /** The kid rules apply: anything but a parent's phone, or one that said it's a kid's (the stricter wins). */
    boolean restricted() {
        return !phone.binding().parent() || saidKid;
    }

    boolean ended() {
        return ended;
    }

    /** The version the hello asked for (0 before hello). */
    int version() {
        return version;
    }

    /** The TV's answers to one message from the phone (state goes out after hello and on change only). */
    List<JSONObject> handle(byte[] frame) {
        List<JSONObject> out = new ArrayList<>();
        JSONObject message;
        String type;
        try {
            message = new JSONObject(new String(frame, StandardCharsets.UTF_8));
            type = message.getString("t");
        } catch (JSONException e) {
            out.add(error(BAD_REQUEST, null));
            return out;
        }
        if (!started && !"hello".equals(type)) {
            out.add(error(BAD_REQUEST, type));
            return out;
        }
        // Request ids are version 2's: a v1 session's messages are answered as v1 answers them. An art message's "id"
        // is v1's art id, unless the art's id comes as "art"
        boolean artId = "art".equals(type) && !message.has("art");
        String id = version >= 2 && !artId ? requestId(message) : null;
        try {
            if (version >= 2 && !artId && message.has("id") && id == null) throw new Refused(BAD_REQUEST);
            boolean answered = handle(type, message, id, out);
            if (version >= 2 && id != null && !answered) out.add(new JSONObject().put("t", "ok").put("re", id));
        } catch (Refused refused) {
            JSONObject error = error(refused.code, type);
            if (version >= 2) v2Error(error, id, refused);
            out.add(error);
        } catch (JSONException e) {
            JSONObject error = error(BAD_REQUEST, type);
            if (version >= 2) v2Error(error, id, null);
            out.add(error);
        }
        return out;
    }

    /** Handles one message; true when its answer is already in {@code out} (else a v2 request id gets "ok"). */
    private boolean handle(String type, JSONObject message, String id, List<JSONObject> out)
            throws Refused, JSONException {
        switch (type) {
            case "hello": {
                int asked = message.optInt("v", 0);
                if (asked < 1 || asked > VERSION) {
                    out.add(error(UNSUPPORTED, type));
                    return true;
                }
                version = asked;
                started = true;
                saidKid = message.optBoolean("kid", false);
                if (version >= 2) {
                    // The hello's own id: its answer is the welcome
                    String helloId = requestId(message);
                    JSONObject welcome = welcome();
                    if (helloId != null) welcome.put("re", helloId);
                    out.add(welcome);
                }
                out.add(stateMessage(true));
                return true;
            }
            case "media": {
                String action = message.optString("do", "");
                if (!action.matches("play|pause|toggle|next|prev|stop")) throw new Refused(UNSUPPORTED);
                tv.media(action);
                return false;
            }
            case "seek":
                if (message.has("toMs")) {
                    tv.seekTo(Math.max(0, message.getLong("toMs")));
                } else if (message.has("byMs")) {
                    tv.seekBy(message.getLong("byMs"));
                } else {
                    throw new Refused(BAD_REQUEST);
                }
                return false;
            case "launch": {
                String pkg = message.optString("pkg", "");
                if (pkg.isEmpty()) throw new Refused(BAD_REQUEST);
                if (!mayOpen(pkg)) throw new Refused(NOT_ALLOWED);
                tv.launch(pkg);
                return false;
            }
            case "volume":
                if (message.has("set")) {
                    int percent = message.getInt("set");
                    if (percent < 0 || percent > 100) throw new Refused(BAD_REQUEST);
                    tv.volumeSet(percent);
                } else if (message.has("step")) {
                    int step = message.getInt("step");
                    if (step != 1 && step != -1) throw new Refused(BAD_REQUEST);
                    tv.volumeStep(step);
                } else if (message.has("mute")) {
                    tv.mute(message.getBoolean("mute"));
                } else {
                    throw new Refused(BAD_REQUEST);
                }
                return false;
            case "apps": {
                JSONArray list = tv.apps();
                JSONArray marked = new JSONArray();
                for (int i = 0; i < list.length(); i++) {
                    JSONObject app = list.getJSONObject(i);
                    String pkg = app.optString("pkg");
                    marked.put(new JSONObject(app.toString()).put("allowed", version >= 2 ? mayOpen(pkg)
                            : tv.allowed(pkg)));
                }
                out.add(reply("apps", id).put("list", marked));
                return true;
            }
            case "art": {
                String artId = message.optString("id", "");
                // In v2 a request id may come too: then the art's id is "art"
                if (version >= 2 && message.has("art")) artId = message.optString("art", "");
                byte[] jpeg = artId.isEmpty() ? null : tv.art(artId);
                if (jpeg == null) throw new Refused(NO_SESSION);
                if (jpeg.length > MAX_ART) throw new Refused(UNSUPPORTED);
                out.add(reply("art", id).put("id", artId).put("mime", "image/jpeg")
                        .put("data", java.util.Base64.getEncoder().encodeToString(jpeg)));
                return true;
            }
            case "bye":
                ended = true;
                return true;
            default:
                if (version >= 2) return handleV2(type, message, id, out);
                out.add(error(UNSUPPORTED, type));
                return true;
        }
    }

    /** Version 2's own messages (V2.1), each checked against the phone's role (V2.9). */
    private boolean handleV2(String type, JSONObject message, String id, List<JSONObject> out)
            throws Refused, JSONException {
        Binding binding = phone.binding();
        String mode = tv.mode();
        switch (type) {
            case "sync":
                out.add(synced(message, id));
                return true;
            case "ask":
                if (binding.parent()) throw new Refused(FORBIDDEN);
                if (!binding.kid()) throw new Refused(NOT_BOUND);
                ask(binding, mode, message);
                return false;
            case "kids": {
                if (!binding.parent()) throw new Refused(FORBIDDEN);
                out.add(reply("kids", id).put("list", kids(mode)));
                return true;
            }
            case "answer":
            case "hold":
            case "hold_end":
                if (!binding.parent()) throw new Refused(FORBIDDEN);
                if (MODE_HA.equals(mode)) throw new Refused(HA_RULES);
                // Asks and holds in mode local (V2.10a) aren't built on this TV yet
                throw new Refused(UNSUPPORTED);
            case "ha_ticket":
                if (!binding.parent() || !MODE_HA.equals(mode)) throw new Refused(FORBIDDEN);
                // The one-tap Home Assistant link (V2.10b) isn't built yet
                throw new Refused(UNSUPPORTED);
            case "unpair":
                phone.unpair();
                if (id != null) out.add(new JSONObject().put("t", "ok").put("re", id));
                ended = true;
                return true;
            default:
                throw new Refused(UNSUPPORTED);
        }
    }

    /** Whether this phone may open {@code pkg}: kid rules for all but a parent's, a kid's own rules too (V2.9). */
    private boolean mayOpen(String pkg) {
        Binding binding = phone.binding();
        if (!restricted()) return true;
        if (!tv.allowed(pkg)) return false;
        if (version >= 2 && binding.kid()) {
            return RemoteTime.allowed(tv.entry(binding.profileKey), pkg, tv.now());
        }
        return true;
    }

    // --- Version 2: welcome, time, sync, kids, ask

    private JSONObject welcome() throws JSONException {
        Binding binding = phone.binding();
        JSONObject welcome = new JSONObject().put("t", "welcome").put("v", VERSION).put("role", binding.role)
                .put("mode", tv.mode());
        if (binding.kid()) {
            JSONObject person = tv.person(binding.profileKey);
            if (person != null) welcome.put("person", person);
        }
        return welcome.put("tvs", tv.tvs()).put("now", tv.now()).put("tz", tv.zone());
    }

    /** {@code state.time} for this phone (V2.3): the profile in front's, for a kid's phone only their own. */
    private Object time(JSONObject state) throws JSONException {
        Binding binding = phone.binding();
        String front = tv.frontProfileKey();
        if (front == null || ROLE_NONE.equals(binding.role)) return JSONObject.NULL;
        if (binding.kid() && !sameProfile(front, binding.profileKey)) return JSONObject.NULL;
        String app = state.isNull("app") ? null : state.optString("app", null);
        JSONObject time = RemoteTime.front(tv.entry(front), app, tv.now());
        return time != null ? time : JSONObject.NULL;
    }

    private JSONObject synced(JSONObject message, String id) throws JSONException {
        if (message.optBoolean("standDown", false)) phone.standDown();
        Binding binding = phone.binding();
        String mode = tv.mode();
        long now = tv.now();
        JSONObject synced = reply("synced", id).put("role", binding.role).put("mode", mode).put("now", now);
        if (!binding.kid()) return synced;
        String key = binding.profileKey;
        Object rules = JSONObject.NULL;
        if (MODE_LOCAL.equals(mode)) {
            JSONObject own = tv.rules(key);
            if (own != null) {
                String tag = rulesTag(own);
                if (!tag.equals(message.optString("have", ""))) {
                    rules = new JSONObject(own.toString()).put("tag", tag).put("tz", tv.zone());
                }
            }
        }
        synced.put("rules", rules);
        JSONObject time = RemoteTime.day(tv.entry(key), now, tv.day(now));
        synced.put("time", time != null ? time : JSONObject.NULL);
        // The phone's own use isn't counted on the TV yet (mode ha never takes it: Home Assistant counts the phone)
        if (message.has("usage")) synced.put("usage", "not_taken");
        if (MODE_HA.equals(mode)) retryPendingAsk(key);
        JSONObject ask = askStatus(key, now);
        if (ask != null) synced.put("ask", ask);
        return synced;
    }

    private JSONArray kids(String mode) throws JSONException {
        JSONArray list = new JSONArray();
        long now = tv.now();
        for (String key : tv.kids()) {
            JSONObject person = tv.person(key);
            if (person == null) continue;
            JSONObject kid = new JSONObject().put("person", person).put("time", RemoteTime.kid(tv.entry(key), now));
            // Asks in mode local aren't built yet (none to list); in mode ha the list is display only, without asks
            if (MODE_LOCAL.equals(mode)) kid.put("asks", new JSONArray());
            list.put(kid);
        }
        return list;
    }

    /** A kid's ask for more time (V2.6). Mode ha: forwarded to Home Assistant for the bound kid. */
    private void ask(Binding binding, String mode, JSONObject message) throws Refused, JSONException {
        String askId = message.optString("ask", "");
        int minutes = message.optInt("minutes", 0);
        if (askId.isEmpty() || askId.length() > MAX_ID || minutes <= 0 || minutes > MAX_ASK_MINUTES) {
            throw new Refused(BAD_REQUEST);
        }
        String group = message.isNull("group") ? null : message.optString("group", null);
        // Asks in mode local (household asks, V2.10a) aren't built on this TV yet
        if (!MODE_HA.equals(mode)) throw new Refused(UNSUPPORTED);
        JSONObject last = phone.lastAsk();
        if (last != null && askId.equals(last.optString("ask"))) {
            // A resend is the same ask
            if (last.optBoolean("pending")) forward(last);
            return;
        }
        JSONObject ask = new JSONObject().put("ask", askId).put("minutes", minutes).put("at", tv.now())
                .put("profile", binding.profileKey);
        if (group != null && !group.isEmpty()) ask.put("group", group);
        forward(ask);
    }

    /** Sends the ask to Home Assistant; unreachable, it waits (pending) and goes at the kid's next sync or resend. */
    private void forward(JSONObject ask) throws Refused, JSONException {
        JSONObject answer = tv.askHomeAssistant(ask.optString("profile"), ask.optInt("minutes"),
                ask.optString("group", null));
        JSONObject request = answer != null ? answer.optJSONObject("request") : null;
        String error = answer != null ? answer.optString("error", "") : "unreachable";
        if (answer != null && answer.optBoolean("ok", false) || "already_open".equals(error)) {
            ask.remove("pending");
            if (request != null) ask.put("req", request.optString("id", ""));
            phone.setLastAsk(ask);
            return;
        }
        if ("too_often".equals(error) || "cooldown".equals(error)) {
            throw new Refused(TOO_OFTEN, answer.has("retry_in") ? answer.optInt("retry_in") : null);
        }
        if ("no_person".equals(error)) throw new Refused(UNSUPPORTED);
        phone.setLastAsk(ask.put("pending", true));
    }

    private void retryPendingAsk(String profileKey) {
        JSONObject last = phone.lastAsk();
        if (last == null || !last.optBoolean("pending") || !profileKey.equals(last.optString("profile"))) return;
        try {
            forward(last);
        } catch (Refused | JSONException e) {
            // It stays as it was: refused now (too often), nothing more to do until the kid asks again
        }
    }

    /**
     * The kid's last ask as {@code synced.ask}: {id, status} with status waiting, approved, not_now or expired, from
     * Home Assistant's request in the kid's entry. Null when the kid hasn't asked over the remote API.
     */
    private JSONObject askStatus(String profileKey, long now) throws JSONException {
        JSONObject last = phone.lastAsk();
        if (last == null || !profileKey.equals(last.optString("profile"))) return null;
        return new JSONObject().put("id", last.optString("ask")).put("status", status(last, profileKey, now));
    }

    private String status(JSONObject last, String profileKey, long now) {
        if (last.optBoolean("pending")) return "waiting";
        JSONObject request = HaLocks.locksOf(tv.entry(profileKey)).optJSONObject("request");
        String req = last.optString("req", "");
        if (request != null && !req.isEmpty() && req.equals(request.optString("id"))) {
            switch (request.optString("status", "")) {
                case "pending":
                    return "waiting";
                case "approved":
                    return "approved";
                case "denied":
                    return "not_now";
                default:
                    return "expired";
            }
        }
        // Home Assistant hasn't told this TV about it yet (or has moved on to a newer one)
        return request == null && now - last.optLong("at", now) < ASK_UNHEARD_MS ? "waiting" : "expired";
    }

    /**
     * What to push to this phone now: the state when it changed, and in a kid's v2 session the answer to its ask
     * once Home Assistant gave one (V2.6 {@code answered}). Empty before hello and after bye.
     */
    List<JSONObject> pushes() {
        List<JSONObject> out = new ArrayList<>();
        if (!started || ended) return out;
        JSONObject state = stateMessage(false);
        if (state != null) out.add(state);
        if (version >= 2) {
            JSONObject answered = answered();
            if (answered != null) out.add(answered);
        }
        return out;
    }

    private JSONObject answered() {
        Binding binding = phone.binding();
        JSONObject last = phone.lastAsk();
        if (!binding.kid() || last == null || last.optBoolean("told") || !binding.profileKey.equals(
                last.optString("profile"))) {
            return null;
        }
        long now = tv.now();
        String status = status(last, binding.profileKey, now);
        if (!"approved".equals(status) && !"not_now".equals(status)) return null;
        try {
            JSONObject request = HaLocks.locksOf(tv.entry(binding.profileKey)).optJSONObject("request");
            int minutes = "approved".equals(status) && request != null ? Math.max(0, request.optInt("minutes", 0)) : 0;
            Long at = request != null ? HaLocks.parseTime(request.optString("answered", null)) : null;
            phone.setLastAsk(new JSONObject(last.toString()).put("told", true));
            return new JSONObject().put("t", "answered").put("ask", last.optString("ask")).put("minutes", minutes)
                    .put("by", "an adult").put("at", at != null ? at : now);
        } catch (JSONException e) {
            return null;
        }
    }

    /** The state message when it changed since the last one sent (null: nothing new, or before hello). */
    JSONObject stateIfChanged() {
        return started && !ended ? stateMessage(false) : null;
    }

    private JSONObject stateMessage(boolean always) {
        JSONObject state = tv.state();
        int minutesLeft = -1;
        if (version >= 2) {
            try {
                Object time = time(state);
                state.put("time", time);
                if (time instanceof JSONObject && !((JSONObject) time).isNull("minutesLeft")) {
                    minutesLeft = ((JSONObject) time).optInt("minutesLeft", -1);
                }
            } catch (JSONException e) {
                return null;
            }
        }
        // positionAtMs changes with every read, and a minute ticking down isn't a change (the phone counts down):
        // compare without them, so a still position or one minute less isn't news; more minutes are
        JSONObject compare;
        try {
            compare = new JSONObject(state.toString());
        } catch (JSONException e) {
            compare = state;
        }
        compare.remove("positionAtMs");
        JSONObject time = compare.optJSONObject("time");
        if (time != null) time.remove("minutesLeft");
        String key = compare.toString();
        boolean more = minutesLeft > lastMinutesLeft && lastMinutesLeft >= 0;
        boolean limitCameOrWent = (minutesLeft < 0) != (lastMinutesLeft < 0);
        if (!always && key.equals(lastState) && !more && !limitCameOrWent) return null;
        lastState = key;
        lastMinutesLeft = minutesLeft;
        try {
            return state.put("t", "state");
        } catch (JSONException e) {
            return null;
        }
    }

    /** A rules tag (V2.6 {@code have}): changes whenever the rules do. */
    static String rulesTag(JSONObject rules) {
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256").digest(rules.toString().getBytes(StandardCharsets.UTF_8));
            return "r-" + Hex.of(digest).substring(0, 8);
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException(e);
        }
    }

    /** Whether two profile keys are the same profile: the same key, or an account's profile in the kid's user. */
    static boolean sameProfile(String front, String kid) {
        return front != null && kid != null && (front.equals(kid) || front.startsWith(kid + ":"));
    }

    private static String requestId(JSONObject message) {
        if (!message.has("id") || message.isNull("id")) return null;
        Object value = message.opt("id");
        if (!(value instanceof String)) return null;
        String id = (String) value;
        return id.isEmpty() || id.length() > MAX_ID ? null : id;
    }

    private static JSONObject reply(String type, String id) throws JSONException {
        JSONObject reply = new JSONObject().put("t", type);
        if (id != null) reply.put("re", id);
        return reply;
    }

    private static void v2Error(JSONObject error, String id, Refused refused) {
        try {
            if (id != null) error.put("re", id);
            error.put("message", error.optString("code"));
            if (refused != null && refused.retryInSec != null) error.put("retryInSec", refused.retryInSec);
        } catch (JSONException ignored) {
            // The code alone still says it
        }
    }

    static JSONObject error(String code, String forType) {
        try {
            JSONObject error = new JSONObject().put("t", "error").put("code", code);
            if (forType != null) error.put("for", forType);
            return error;
        } catch (JSONException e) {
            throw new IllegalStateException(e);
        }
    }

    /** A phone whose role doesn't change and which keeps nothing (v1's tests, a phone with no store). */
    static final class Fixed implements Phone {
        private final Binding binding;
        private JSONObject lastAsk;
        boolean unpaired;
        boolean stoodDown;

        Fixed(Binding binding) {
            this.binding = binding;
        }

        @Override public Binding binding() {
            return stoodDown ? new Binding(ROLE_NONE, null) : binding;
        }

        @Override public void unpair() {
            unpaired = true;
        }

        @Override public void standDown() {
            stoodDown = true;
        }

        @Override public JSONObject lastAsk() {
            return lastAsk;
        }

        @Override public void setLastAsk(JSONObject ask) {
            lastAsk = ask;
        }
    }
}
