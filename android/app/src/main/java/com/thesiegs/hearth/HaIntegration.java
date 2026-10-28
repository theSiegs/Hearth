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
            HaConfig.prefs(context).edit().putString(HaConfig.URL_KEY, base).apply();
            Log.i(TAG, "Paired with Home Assistant");
            HaBridgeService.sync(context);
            return "paired";
        }
        return "denied".equals(status) ? "denied" : "pending";
    }

    /** Forgets the pairing on this TV (Home Assistant keeps the device until it's deleted there). */
    static void unpair(Context context) {
        setSecret(context, null);
        forgetHomeAssistantBlocks(context);
        HaBridgeService.sync(context);
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
                prefs.edit().remove(REFUSED_SINCE_KEY).remove(REFUSED_LAST_KEY).apply();
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
        HttpURLConnection connection = null;
        try {
            URL target = new URL(url);
            // The integration answers the home network only; never send a secret over plain HTTP elsewhere
            if (!LocalNet.allows(target)) {
                Log.w(TAG, "Refusing plain HTTP to a non-local address; use https");
                return new Answer(0, null);
            }
            connection = (HttpURLConnection) target.openConnection();
            connection.setConnectTimeout(5_000);
            connection.setReadTimeout(8_000);
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
