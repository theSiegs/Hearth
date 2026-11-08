package com.thesiegs.hearth;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.List;

/**
 * One phone's session on the remote API (docs/tv-remote-api.md "Session"): its JSON messages in, the TV's answers
 * out, and the kid rules. Knows nothing about sockets or Android: {@link Tv} does what's asked.
 */
final class RemoteSession {
    static final int VERSION = 1;

    /** What the TV can do for a phone. Calls may throw {@link Refused} with an error code. */
    interface Tv {
        /** The state message's fields (without "t"). */
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
    }

    static final class Refused extends Exception {
        final String code;

        Refused(String code) {
            super(code);
            this.code = code;
        }
    }

    static final String NOT_PAIRED = "not_paired";
    static final String NOT_ALLOWED = "not_allowed";
    static final String UNSUPPORTED = "unsupported";
    static final String NO_SESSION = "no_session";
    static final String BAD_REQUEST = "bad_request";
    static final int MAX_ART = 64 * 1024;

    private final Tv tv;
    private final boolean adultPhone;
    private boolean saidKid;
    private boolean started;
    private boolean ended;
    private String lastState;

    /** [adultPhone]: an adult marked this phone as an adult's in Settings; anything else is restricted. */
    RemoteSession(Tv tv, boolean adultPhone) {
        this.tv = tv;
        this.adultPhone = adultPhone;
    }

    /** The kid rules apply: a restricted phone, or one that said it's a kid's (the stricter wins). */
    boolean restricted() {
        return !adultPhone || saidKid;
    }

    boolean ended() {
        return ended;
    }

    /** The TV's answers to one message from the phone (state goes out after hello and on change only). */
    List<JSONObject> handle(byte[] frame) {
        List<JSONObject> out = new ArrayList<>();
        JSONObject message;
        String type;
        try {
            message = new JSONObject(new String(frame, java.nio.charset.StandardCharsets.UTF_8));
            type = message.getString("t");
        } catch (JSONException e) {
            out.add(error(BAD_REQUEST, null));
            return out;
        }
        if (!started && !"hello".equals(type)) {
            out.add(error(BAD_REQUEST, type));
            return out;
        }
        try {
            switch (type) {
                case "hello":
                    if (message.optInt("v", 0) != VERSION) {
                        out.add(error(UNSUPPORTED, type));
                        return out;
                    }
                    started = true;
                    saidKid = message.optBoolean("kid", false);
                    out.add(stateMessage(true));
                    break;
                case "media": {
                    String action = message.optString("do", "");
                    if (!action.matches("play|pause|toggle|next|prev|stop")) throw new Refused(UNSUPPORTED);
                    tv.media(action);
                    break;
                }
                case "seek":
                    if (message.has("toMs")) {
                        tv.seekTo(Math.max(0, message.getLong("toMs")));
                    } else if (message.has("byMs")) {
                        tv.seekBy(message.getLong("byMs"));
                    } else {
                        throw new Refused(BAD_REQUEST);
                    }
                    break;
                case "launch": {
                    String pkg = message.optString("pkg", "");
                    if (pkg.isEmpty()) throw new Refused(BAD_REQUEST);
                    if (restricted() && !tv.allowed(pkg)) throw new Refused(NOT_ALLOWED);
                    tv.launch(pkg);
                    break;
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
                    break;
                case "apps": {
                    JSONArray list = tv.apps();
                    JSONArray marked = new JSONArray();
                    for (int i = 0; i < list.length(); i++) {
                        JSONObject app = list.getJSONObject(i);
                        marked.put(new JSONObject(app.toString()).put("allowed", tv.allowed(app.optString("pkg"))));
                    }
                    out.add(new JSONObject().put("t", "apps").put("list", marked));
                    break;
                }
                case "art": {
                    String id = message.optString("id", "");
                    byte[] jpeg = id.isEmpty() ? null : tv.art(id);
                    if (jpeg == null) throw new Refused(NO_SESSION);
                    if (jpeg.length > MAX_ART) throw new Refused(UNSUPPORTED);
                    out.add(new JSONObject().put("t", "art").put("id", id).put("mime", "image/jpeg")
                            .put("data", java.util.Base64.getEncoder().encodeToString(jpeg)));
                    break;
                }
                case "bye":
                    ended = true;
                    break;
                default:
                    out.add(error(UNSUPPORTED, type));
            }
        } catch (Refused refused) {
            out.add(error(refused.code, type));
        } catch (JSONException e) {
            out.add(error(BAD_REQUEST, type));
        }
        return out;
    }

    /** The state message when it changed since the last one sent (null: nothing new, or before hello). */
    JSONObject stateIfChanged() {
        return started && !ended ? stateMessage(false) : null;
    }

    private JSONObject stateMessage(boolean always) {
        JSONObject state = tv.state();
        // positionAtMs changes with every read: compare without it, so a still position isn't a change
        JSONObject compare;
        try {
            compare = new JSONObject(state.toString());
        } catch (JSONException e) {
            compare = state;
        }
        compare.remove("positionAtMs");
        String key = compare.toString();
        if (!always && key.equals(lastState)) return null;
        lastState = key;
        try {
            return state.put("t", "state");
        } catch (JSONException e) {
            return null;
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
}
