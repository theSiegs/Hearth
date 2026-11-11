package com.thesiegs.hearth;

import android.content.Context;
import android.content.SharedPreferences;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.util.Base64;
import android.util.Log;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.security.SecureRandom;
import java.util.List;

/**
 * Hearth's side of the Hearth integration for Home Assistant (custom_components/hearth, see
 * docs/home-assistant-integration.md): this TV's own id, the secret it gets when an adult pairs it, and the calls.
 * Paired, the TV posts its status to the integration instead of a webhook, and the answer carries each profile's
 * limits. The secret works on Hearth's endpoints only; it's kept sealed under a Keystore key, like the panel's token.
 */
final class HaIntegration {
    private static final String TAG = "HearthHaIntegration";
    private static final String DEVICE_ID_KEY = "ha_integration_device_id";
    private static final String SECRET_SEALED_KEY = "ha_integration_secret_sealed";
    private static final String SECRET_ALIAS = "hearth_ha_device_v1";
    static final String HEADER_SECRET = "X-Hearth-Secret";
    static final String HEADER_NONCE = "X-Hearth-Nonce";
    private static final int MAX_ANSWER_BYTES = 256 * 1024;
    /** The integration takes at most 50 started videos a post, and 10 posts a minute */
    static final int EVENTS_PER_POST = 50;
    private static final int MAX_EVENT_POSTS = 4;
    private static final String REFUSED_SINCE_KEY = "ha_integration_refused_since";
    // Refusals for this long, not one: Home Assistant answers 401 for a moment while it restarts or reloads
    static final long UNPAIR_AFTER_REFUSALS_MS = 10 * 60_000L;
    private static final String REFUSED_LAST_KEY = "ha_integration_refused_last";
    /** A paired TV posts every two minutes while on: refusals further apart than this aren't one stretch. */
    static final long REFUSAL_GAP_MS = 5 * 60_000L;

    private HaIntegration() {}

    /** This TV's id for the integration: made once, kept (also across unpairing, so pairing again is the same TV). */
    static synchronized String deviceId(Context context) {
        SharedPreferences prefs = HaConfig.prefs(context);
        String id = prefs.getString(DEVICE_ID_KEY, null);
        if (id == null) {
            id = "tv-" + randomToken(18);
            prefs.edit().putString(DEVICE_ID_KEY, id).apply();
        }
        return id;
    }

    static String randomToken(int bytes) {
        byte[] random = new byte[bytes];
        new SecureRandom().nextBytes(random);
        return Base64.encodeToString(random, Base64.URL_SAFE | Base64.NO_PADDING | Base64.NO_WRAP);
    }

    /** The secret from pairing; null when the TV isn't paired (or the sealed secret no longer opens). */
    static String secret(Context context) {
        String sealed = HaConfig.prefs(context).getString(SECRET_SEALED_KEY, null);
        if (sealed == null) return null;
        String secret = SecretBox.openText(SecretBox.keystore(), SECRET_ALIAS, sealed);
        return secret == null || secret.isEmpty() ? null : secret;
    }

    /** Keeps the secret sealed (null forgets it: unpaired); false when the Keystore wouldn't seal it. */
    static boolean setSecret(Context context, String secret) {
        SharedPreferences.Editor editor = HaConfig.prefs(context).edit();
        if (secret == null || secret.isEmpty()) {
            editor.remove(SECRET_SEALED_KEY).apply();
            return true;
        }
        String sealed = SecretBox.sealText(SecretBox.keystore(), SECRET_ALIAS, secret);
        if (sealed == null) return false;
        editor.putString(SECRET_SEALED_KEY, sealed).apply();
        return true;
    }

    /** Which pairing this is, without opening the secret: its sealed form, new with every pairing; null when unpaired. */
    static String pairingStamp(Context context) {
        return HaConfig.prefs(context).getString(SECRET_SEALED_KEY, null);
    }

    static boolean isPaired(Context context) {
        return HaConfig.baseUrl(context) != null && secret(context) != null;
    }

    static String statusUrl(Context context) {
        String base = HaConfig.baseUrl(context);
        return base == null ? null : base + "/api/hearth/device/" + deviceId(context) + "/status";
    }

    /** An answer from the integration: its HTTP code and JSON body (null when it had none). */
    static final class Answer {
        final int code;
        final JSONObject body;

        Answer(int code, JSONObject body) {
            this.code = code;
            this.body = body;
        }

        String error() {
            return body != null ? body.optString("error", null) : null;
        }
    }

    /**
     * Asks Home Assistant to pair (blocking): {pairing_id, code, expires_in} to show, or {error}. The nonce, made
     * here and never shown, is what later collects the secret; the caller keeps it for {@link #pollPairing}.
     * [base] is the address to ask; it becomes Home Assistant's address (the panel's too) only once paired.
     */
    static JSONObject startPairing(Context context, String base, String nonce) {
        JSONObject result = new JSONObject();
        try {
            if (base == null) return result.put("error", "no_address");
            JSONObject body = new JSONObject()
                    .put("device_id", deviceId(context))
                    .put("kind", "tv")
                    .put("name", ShareDiscovery.deviceName(context))
                    .put("model", Build.MODEL)
                    .put("version", versionName(context))
                    .put("nonce", nonce);
            Answer answer = request(base + "/api/hearth/pair", "POST", body, null);
            if (answer.code == 200 && answer.body != null) return answer.body;
            return result.put("error", answer.code == 404 && "not_set_up".equals(answer.error()) ? "not_set_up"
                    : answer.code == 404 ? "no_integration"
                    : answer.code == 429 ? "try_later"
                    : answer.code == 403 ? "not_local"
                    : answer.code == 0 ? "unreachable" : "failed");
        } catch (JSONException e) {
            return result;
        }
    }

    /**
     * Asks how the pairing stands (blocking): "pending", "paired" (the secret is kept: the TV is paired now),
     * "denied", "ended" (expired, or unknown), or "unreachable".
     */
    static String pollPairing(Context context, String base, String pairingId, String nonce) {
        if (base == null || pairingId == null || !pairingId.matches("[A-Za-z0-9_-]{8,64}")) return "ended";
        Answer answer = request(base + "/api/hearth/pair/" + pairingId, "GET", null, nonce);
        if (answer.code == 0) return "unreachable";
        if (answer.code != 200 || answer.body == null) {
            Log.i(TAG, "Pairing ended: Home Assistant answered " + answer.code);
            return "ended";
        }
        String status = answer.body.optString("status");
        if ("approved".equals(status)) {
            String secret = answer.body.optString("secret", "");
            if (secret.isEmpty() || !setSecret(context, secret)) {
                Log.w(TAG, "Pairing approved, but the secret " + (secret.isEmpty() ? "was missing" : "couldn't be kept"));
                return "ended";
            }
            // The address that answered is Home Assistant's now (only now: a mistyped one never replaces the panel's)
            HaConfig.prefs(context).edit().putString(HaConfig.URL_KEY, base).remove(LEFT_KEY).apply();
            Log.i(TAG, "Paired with Home Assistant");
            HaBridgeService.sync(context);
            // The household's other TVs pair through this one
            Household.onHaChanged(context);
            return "paired";
        }
        return "denied".equals(status) ? "denied" : "pending";
    }

    /**
     * Asks Home Assistant for a single-use pairing ticket (blocking; this TV must be paired): kind "tv" for another TV
     * of the household, or "mobile" with an adult's {@code person} for that adult's phone. The ticket, or null.
     */
    static String requestTicket(Context context, String kind, String person) {
        String base = HaConfig.baseUrl(context);
        String secret = secret(context);
        if (base == null || secret == null) return null;
        try {
            JSONObject body = new JSONObject().put("kind", kind);
            if (person != null) body.put("person", person);
            Answer answer = request(base + "/api/hearth/device/" + deviceId(context) + "/ticket", "POST", body, null,
                    secret);
            if (answer.code != 200 || answer.body == null) {
                Log.i(TAG, "No pairing ticket: Home Assistant answered " + answer.code + " " + answer.error());
                return null;
            }
            String ticket = answer.body.optString("ticket", "");
            return ticketShaped(ticket) ? ticket : null;
        } catch (JSONException e) {
            return null;
        }
    }

    /** A ticket as Home Assistant makes them (URL-safe base64), never anything that could be more than that. */
    static boolean ticketShaped(String ticket) {
        return ticket != null && ticket.matches("[A-Za-z0-9_-]{16,128}");
    }

    /**
     * Pairs with the ticket another TV of the household got for this one (blocking): "paired", "refused" (the ticket
     * was used, expired or wrong: another TV can get a new one), or "unreachable".
     */
    static String redeemTicket(Context context, String base, String ticket) {
        if (base == null || !ticketShaped(ticket)) return "refused";
        try {
            JSONObject body = new JSONObject()
                    .put("ticket", ticket)
                    .put("device_id", deviceId(context))
                    .put("kind", "tv")
                    .put("name", ShareDiscovery.deviceName(context))
                    .put("model", Build.MODEL)
                    .put("version", versionName(context));
            Answer answer = request(base + "/api/hearth/pair/redeem", "POST", body, null);
            if (answer.code == 0) return "unreachable";
            String secret = answer.code == 200 && answer.body != null ? answer.body.optString("secret", "") : "";
            if (secret.isEmpty() || !setSecret(context, secret)) {
                Log.i(TAG, "Pairing ticket refused: Home Assistant answered " + answer.code);
                HaConfig.prefs(context).edit().putLong(TICKET_REFUSED_AT_KEY, System.currentTimeMillis()).apply();
                return "refused";
            }
            HaConfig.prefs(context).edit().putString(HaConfig.URL_KEY, base).remove(LEFT_KEY).apply();
            Log.i(TAG, "Paired with Home Assistant through another TV of the household");
            HaBridgeService.sync(context);
            Household.onHaChanged(context);
            return "paired";
        } catch (JSONException e) {
            return "refused";
        }
    }

    /** When a ticket was last refused here (a lasting reason, such as Home Assistant not taking this TV as local). */
    private static final String TICKET_REFUSED_AT_KEY = "ha_ticket_refused_at";
    /** How long a TV whose ticket was refused waits before the household tries again. */
    static final long TICKET_RETRY_MS = 60 * 60_000;

    /** Whether a ticket was refused here in the last {@link #TICKET_RETRY_MS}. */
    static boolean ticketRefusedLately(Context context, long now) {
        long at = HaConfig.prefs(context).getLong(TICKET_REFUSED_AT_KEY, 0);
        return at > 0 && now >= at && now - at < TICKET_RETRY_MS;
    }

    /** Someone unpaired this TV here: the household's other TVs don't pair it again by themselves. */
    private static final String LEFT_KEY = "ha_integration_left";

    static boolean leftOnPurpose(Context context) {
        return HaConfig.prefs(context).getBoolean(LEFT_KEY, false);
    }

    /** Forgets the pairing on this TV (Home Assistant keeps the device until it's deleted there). */
    static void unpair(Context context) {
        HaConfig.prefs(context).edit().putBoolean(LEFT_KEY, true).apply();
        setSecret(context, null);
        forgetHomeAssistantBlocks(context);
        HaBridgeService.sync(context);
        Household.onHaChanged(context);
    }

    /** A TV that left Home Assistant no longer holds kids to the YouTube blocks set there (Hearth's own stay). */
    private static void forgetHomeAssistantBlocks(Context context) {
        ParentBlocks.clearHomeAssistant(context);
        new Handler(Looper.getMainLooper()).post(() -> ProfileProvider.notifyChanged(context));
    }

    static String eventsUrl(Context context) {
        String base = HaConfig.baseUrl(context);
        return base == null ? null : base + "/api/hearth/device/" + deviceId(context) + "/events";
    }

    /**
     * Sends Home Assistant the videos kids profiles started that it hasn't had (blocking; after a status post), up to
     * {@link #EVENTS_PER_POST} a post and a few posts a time; what is left goes with the next status. Entries more
     * than a day old stay in Hearth's log only. Home Assistant drops a profile mapped to no one, and a resend is
     * harmless, so a profile's mark moves on with every answered post.
     */
    static void sendStartedLog(Context context) {
        String url = eventsUrl(context);
        String secret = secret(context);
        if (url == null || secret == null) return;
        long now = System.currentTimeMillis();
        int posts = 0;
        for (String profile : StartedLog.profiles(context)) {
            while (posts < MAX_EVENT_POSTS) {
                List<StartedLog.Entry> batch = StartedLog.unsent(StartedLog.read(context, profile),
                        StartedLog.sentUpTo(context, profile), now, EVENTS_PER_POST);
                if (batch.isEmpty()) break;
                JSONArray events = new JSONArray();
                try {
                    for (StartedLog.Entry entry : batch) {
                        events.put(entry.toJson().put("type", "video_started").put("profile_id", profile));
                    }
                    posts++;
                    Answer answer = request(url, "POST", new JSONObject().put("events", events), null, secret);
                    if (answer.code != 200) {
                        // An integration without the endpoint (404), or busy: the next status tries again
                        Log.d(TAG, "Videos started not sent: Home Assistant answered " + answer.code);
                        return;
                    }
                } catch (JSONException e) {
                    return;
                }
                StartedLog.setSentUpTo(context, profile, batch.get(batch.size() - 1).timeMs);
            }
        }
    }

    /** Posts the status (blocking); 401s for 10 minutes mean Home Assistant removed this TV, and the TV is unpaired. */
    static Answer postStatus(Context context, String body) {
        String url = statusUrl(context);
        String secret = secret(context);
        if (url == null || secret == null) return new Answer(0, null);
        Answer answer;
        try {
            answer = request(url, "POST", new JSONObject(body), null, secret);
        } catch (JSONException e) {
            return new Answer(0, null);
        }
        SharedPreferences prefs = HaConfig.prefs(context);
        if (answer.code == 401) {
            long now = System.currentTimeMillis();
            long since = refusalsSince(prefs.getLong(REFUSED_SINCE_KEY, 0), prefs.getLong(REFUSED_LAST_KEY, 0), now);
            if (refusedLongEnough(since, now)) {
                Log.w(TAG, "Home Assistant no longer knows this TV: unpaired");
                // Deleted in Home Assistant: the household's other TVs don't pair it again by themselves
                prefs.edit().remove(REFUSED_SINCE_KEY).remove(REFUSED_LAST_KEY).putBoolean(LEFT_KEY, true).apply();
                setSecret(context, null);
                forgetHomeAssistantBlocks(context);
            } else {
                prefs.edit().putLong(REFUSED_SINCE_KEY, since).putLong(REFUSED_LAST_KEY, now).apply();
            }
        } else if (answer.code > 0 && prefs.contains(REFUSED_SINCE_KEY)) {
            prefs.edit().remove(REFUSED_SINCE_KEY).remove(REFUSED_LAST_KEY).apply();
        }
        return answer;
    }

    /** How a held wait ended (see {@link #waitForChange}). */
    enum WaitResult { CHANGED, NOT_CHANGED, UNSUPPORTED, FAILED }

    /**
     * Holds the integration's long-poll (blocking, up to {@code timeoutS} seconds): CHANGED as soon as this TV's state
     * document isn't {@code version} any more (a pause, a lock, an answered request), NOT_CHANGED at the timeout,
     * UNSUPPORTED from an older integration without it (404), FAILED otherwise. It never carries the document: on
     * CHANGED the status is posted and the answer read as usual. See the integration's wait.py.
     */
    static WaitResult waitForChange(Context context, String version, int timeoutS) {
        String base = HaConfig.baseUrl(context);
        String secret = secret(context);
        if (base == null || secret == null) return WaitResult.FAILED;
        Answer answer = request(waitUrl(base, deviceId(context), version, timeoutS), "GET", null, null, secret,
                5_000, (timeoutS + 10) * 1_000);
        return waitResult(answer.code, answer.body);
    }

    static String waitUrl(String base, String deviceId, String version, int timeoutS) {
        StringBuilder url = new StringBuilder(base).append("/api/hearth/device/").append(deviceId)
                .append("/wait?timeout=").append(timeoutS);
        // The version is the document's short hex hash; anything else is left out (the integration then says changed)
        if (version != null && version.matches("[0-9a-f]{1,32}")) url.append("&version=").append(version);
        return url.toString();
    }

    static WaitResult waitResult(int code, JSONObject body) {
        if (code == 200 && body != null) {
            return body.optBoolean("changed", false) ? WaitResult.CHANGED : WaitResult.NOT_CHANGED;
        }
        return code == 404 ? WaitResult.UNSUPPORTED : WaitResult.FAILED;
    }

    /**
     * Asks the integration whether {@code pin} is an adult's parent PIN (it keeps the lockout). UNKNOWN when it can't
     * say: unreachable, not paired any more, or it has none set. Quick to give up, as someone waits at the PIN pad.
     */
    static HaParentPins.Verdict verifyPin(Context context, String pin) {
        String base = HaConfig.baseUrl(context);
        String secret = secret(context);
        if (base == null || secret == null || pin == null) return HaParentPins.Verdict.UNKNOWN;
        Answer answer;
        try {
            answer = request(base + "/api/hearth/device/" + deviceId(context) + "/verify_pin", "POST",
                    new JSONObject().put("pin", pin), null, secret, 2_000, 3_000);
        } catch (JSONException e) {
            return HaParentPins.Verdict.UNKNOWN;
        }
        if (answer.code == 200 && answer.body != null) {
            return answer.body.optBoolean("ok", false) ? HaParentPins.Verdict.YES : HaParentPins.Verdict.NO;
        }
        // Locked out there: no, even for the right PIN, as on a phone
        if (answer.code == 429) return HaParentPins.Verdict.NO;
        return HaParentPins.Verdict.UNKNOWN;
    }

    /** The amounts of more time a kid can ask for, in minutes (the integration's asks.AMOUNTS). */
    static final int[] ASK_MINUTES = {15, 30, 45, 60};

    /**
     * Asks the adults for more time for a TV profile (blocking): POST .../ask {minutes, group, profile_id}. Answers
     * {ok: true, request} or {error, request?, retry_in?}: already_open (with the open request), cooldown (retry_in
     * seconds after a "not now"), no_person (the profile is nobody's in Home Assistant), not_paired, too_often,
     * unreachable, or failed.
     */
    static JSONObject ask(Context context, String profileKey, int minutes, String group) {
        JSONObject result = new JSONObject();
        try {
            String base = HaConfig.baseUrl(context);
            String secret = secret(context);
            if (base == null || secret == null) return result.put("error", "not_paired");
            JSONObject body = new JSONObject().put("minutes", minutes)
                    .put("group", group == null || group.isEmpty() ? HaAllowance.ALL_GROUP : group);
            if (profileKey != null) body.put("profile_id", profileKey);
            Answer answer = request(base + "/api/hearth/device/" + deviceId(context) + "/ask", "POST", body, null,
                    secret);
            return askResult(answer.code, answer.body);
        } catch (JSONException e) {
            return result;
        }
    }

    /** The integration's answer to an ask, as {@link #ask} gives it. */
    static JSONObject askResult(int code, JSONObject body) throws JSONException {
        JSONObject result = new JSONObject();
        JSONObject request = body != null ? body.optJSONObject("request") : null;
        if (request != null) result.put("request", request);
        if (code == 200 && request != null) return result.put("ok", true);
        String error = body != null ? body.optString("error", "") : "";
        if (code == 429 && body != null && body.has("retry_in")) result.put("retry_in", body.optInt("retry_in"));
        return result.put("error", code == 409 ? "already_open"
                : code == 429 && "cooldown".equals(error) ? "cooldown"
                : code == 429 ? "too_often"
                : code == 404 && "no_person".equals(error) ? "no_person"
                : code == 401 ? "not_paired"
                : code == 0 ? "unreachable" : "failed");
    }

    /**
     * Since when the refusals have lasted, given a refusal now: {@code since} (0: none counted yet) and {@code last},
     * the previous refusal. Refusals more than {@link #REFUSAL_GAP_MS} apart aren't one stretch (the TV was off, or Home
     * Assistant was unreachable meanwhile, which answers nothing either way), so a refusal then starts a new one: a
     * restart's moment of 401s that happens to come long after an earlier one doesn't unpair at once.
     */
    static long refusalsSince(long since, long last, long now) {
        if (since <= 0 || since > now || last <= 0 || last > now || now - last > REFUSAL_GAP_MS) return now;
        return since;
    }

    /** Whether the integration has refused this TV since [since] long enough to mean it was removed. */
    static boolean refusedLongEnough(long since, long now) {
        return now - since >= UNPAIR_AFTER_REFUSALS_MS;
    }

    /** Android's category for an app, as the integration names it ("game", "video"...); null when none or unknown. */
    static String category(PackageManager pm, String packageName) {
        try {
            ApplicationInfo info = pm.getApplicationInfo(packageName, 0);
            // Games that only set the old flag
            if ((info.flags & ApplicationInfo.FLAG_IS_GAME) != 0) return "game";
            switch (info.category) {
                case ApplicationInfo.CATEGORY_GAME: return "game";
                case ApplicationInfo.CATEGORY_VIDEO: return "video";
                case ApplicationInfo.CATEGORY_AUDIO: return "audio";
                case ApplicationInfo.CATEGORY_IMAGE: return "image";
                case ApplicationInfo.CATEGORY_SOCIAL: return "social";
                case ApplicationInfo.CATEGORY_NEWS: return "news";
                case ApplicationInfo.CATEGORY_MAPS: return "maps";
                case ApplicationInfo.CATEGORY_PRODUCTIVITY: return "productivity";
                case ApplicationInfo.CATEGORY_ACCESSIBILITY: return "accessibility";
                default: return null;
            }
        } catch (PackageManager.NameNotFoundException e) {
            return null;
        }
    }

    private static String versionName(Context context) {
        try {
            return context.getPackageManager().getPackageInfo(context.getPackageName(), 0).versionName;
        } catch (PackageManager.NameNotFoundException e) {
            return null;
        }
    }

    private static Answer request(String url, String method, JSONObject body, String nonce) {
        return request(url, method, body, nonce, null);
    }

    private static Answer request(String url, String method, JSONObject body, String nonce, String secret) {
        return request(url, method, body, nonce, secret, 5_000, 8_000);
    }

    private static Answer request(String url, String method, JSONObject body, String nonce, String secret,
                                  int connectMs, int readMs) {
        HttpURLConnection connection = null;
        try {
            URL target = new URL(url);
            // The integration answers the home network only; never send a secret over plain HTTP elsewhere
            if (!LocalNet.allows(target)) {
                Log.w(TAG, "Refusing plain HTTP to a non-local address; use https");
                return new Answer(0, null);
            }
            connection = (HttpURLConnection) target.openConnection();
            connection.setConnectTimeout(connectMs);
            connection.setReadTimeout(readMs);
            connection.setRequestMethod(method);
            connection.setInstanceFollowRedirects(false);
            connection.setRequestProperty("Accept", "application/json");
            if (nonce != null) connection.setRequestProperty(HEADER_NONCE, nonce);
            if (secret != null) connection.setRequestProperty(HEADER_SECRET, secret);
            if (body != null) {
                connection.setDoOutput(true);
                connection.setRequestProperty("Content-Type", "application/json");
                try (OutputStream out = connection.getOutputStream()) {
                    out.write(body.toString().getBytes(StandardCharsets.UTF_8));
                }
            }
            int code = connection.getResponseCode();
            InputStream in = code >= 400 ? connection.getErrorStream() : connection.getInputStream();
            return new Answer(code, in == null ? null : readJson(in));
        } catch (IOException e) {
            Log.w(TAG, "Couldn't reach Home Assistant: " + e.getMessage());
            return new Answer(0, null);
        } finally {
            if (connection != null) connection.disconnect();
        }
    }

    private static JSONObject readJson(InputStream in) throws IOException {
        try (InputStream stream = in) {
            ByteArrayOutputStream out = new ByteArrayOutputStream();
            byte[] buffer = new byte[8192];
            int read;
            while ((read = stream.read(buffer)) != -1) {
                out.write(buffer, 0, read);
                if (out.size() > MAX_ANSWER_BYTES) return null;
            }
            return new JSONObject(out.toString(StandardCharsets.UTF_8.name()));
        } catch (JSONException e) {
            return null;
        }
    }
}
