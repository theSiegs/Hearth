package com.thesiegs.hearth;

import android.content.Context;
import android.content.SharedPreferences;
import android.util.Log;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * What keeps streaming PIN entry in check besides the per-PIN rules (ProfilePairingService.whyNotProfilePin):
 * <ul>
 * <li>one switch for the whole TV that turns PIN typing off ({@link #isTypingOn});</li>
 * <li>a list in Hearth's repository of app versions whose PIN screens Hearth's recipes are known not to handle
 * ({@link #disabledFor}), read at most every {@link #REFRESH_MS} while a PIN is saved. It can only turn typing
 * off, never on, so it needs no signature: the worst a tampered list could do is stop Hearth typing;</li>
 * <li>a log of the last {@link #LOG_SIZE} entries on the TV (app, its version, outcome; no names or digits) for
 * Settings and bug reports ({@link #log}).</li>
 * </ul>
 */
final class PinSafety {
    private static final String TAG = "HearthPins";
    private static final String PREFS = "pin_safety";
    private static final String TYPING_ON_KEY = "typing_on";
    private static final String LIST_KEY = "disabled_list";
    private static final String LIST_AT_KEY = "disabled_list_at";
    private static final String LOG_KEY = "log";
    static final String LIST_URL = "https://raw.githubusercontent.com/theSiegs/Hearth/master/pin-entry/disabled.json";
    static final long REFRESH_MS = 12 * 60 * 60_000L;
    static final int LOG_SIZE = 20;
    private static final ExecutorService FETCH = Executors.newSingleThreadExecutor();

    private PinSafety() {
    }

    private static SharedPreferences prefs(Context context) {
        return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    static boolean isTypingOn(Context context) {
        return prefs(context).getBoolean(TYPING_ON_KEY, true);
    }

    static void setTypingOn(Context context, boolean on) {
        prefs(context).edit().putBoolean(TYPING_ON_KEY, on).apply();
        Log.i(TAG, "PIN typing " + (on ? "on" : "off"));
    }

    // ---- The list of app versions not to type PINs in ----

    /** Why PINs mustn't be typed in this version of the app, from the last list read; null when they may. */
    static String disabledFor(Context context, String pkg, long versionCode) {
        return disabledIn(prefs(context).getString(LIST_KEY, null), pkg, versionCode);
    }

    /**
     * The list's verdict for an app version: {"disabled": [{"package": "…", "from": versionCode, "to": versionCode,
     * "note": "…"}]}, where "from" and "to" are optional and inclusive (none: every version).
     */
    static String disabledIn(String json, String pkg, long versionCode) {
        if (json == null || pkg == null) return null;
        try {
            JSONArray entries = new JSONObject(json).optJSONArray("disabled");
            if (entries == null) return null;
            for (int i = 0; i < entries.length(); i++) {
                JSONObject entry = entries.optJSONObject(i);
                if (entry == null || !pkg.equals(entry.optString("package"))) continue;
                long from = entry.optLong("from", 0);
                long to = entry.has("to") && !entry.isNull("to") ? entry.optLong("to") : Long.MAX_VALUE;
                if (versionCode >= from && versionCode <= to) {
                    String note = entry.optString("note", "");
                    return note.isEmpty() ? "turned off for this version of the app" : note;
                }
            }
        } catch (Exception e) {
            Log.w(TAG, "Couldn't read the list of apps not to type PINs in: " + e.getClass().getSimpleName());
        }
        return null;
    }

    /** Reads the list again in the background if it's older than {@link #REFRESH_MS}. Nothing is sent but the request. */
    static void refreshIfDue(Context context) {
        Context app = context.getApplicationContext();
        long at = prefs(app).getLong(LIST_AT_KEY, 0);
        if (System.currentTimeMillis() - at < REFRESH_MS) return;
        prefs(app).edit().putLong(LIST_AT_KEY, System.currentTimeMillis()).apply();
        FETCH.execute(() -> {
            HttpURLConnection connection = null;
            try {
                connection = (HttpURLConnection) new URL(LIST_URL).openConnection();
                connection.setConnectTimeout(10_000);
                connection.setReadTimeout(10_000);
                connection.setRequestProperty("User-Agent", "Hearth");
                int code = connection.getResponseCode();
                if (code == HttpURLConnection.HTTP_NOT_FOUND) {
                    prefs(app).edit().remove(LIST_KEY).apply();
                    return;
                }
                if (code != HttpURLConnection.HTTP_OK) return;
                String body = read(connection.getInputStream());
                new JSONObject(body); // only a list that parses replaces the last one
                prefs(app).edit().putString(LIST_KEY, body).apply();
                Log.i(TAG, "Read the list of apps not to type PINs in");
            } catch (Exception e) {
                Log.i(TAG, "Couldn't read the list of apps not to type PINs in: " + e.getClass().getSimpleName());
            } finally {
                if (connection != null) connection.disconnect();
            }
        });
    }

    private static String read(InputStream in) throws Exception {
        try (InputStream stream = in; ByteArrayOutputStream out = new ByteArrayOutputStream()) {
            byte[] buffer = new byte[4096];
            int total = 0;
            int n;
            while ((n = stream.read(buffer)) > 0) {
                total += n;
                if (total > 64 * 1024) throw new IllegalStateException("too long");
                out.write(buffer, 0, n);
            }
            return out.toString("UTF-8");
        }
    }

    // ---- The log of recent entries ----

    /** One more entry, newest first; the oldest past {@link #LOG_SIZE} go. No names or digits: app, version, outcome. */
    static void log(Context context, String pkg, long versionCode, boolean content, String result, long at) {
        SharedPreferences prefs = prefs(context);
        prefs.edit().putString(LOG_KEY, withEntry(prefs.getString(LOG_KEY, "[]"), pkg, versionCode, content,
                result, at)).apply();
    }

    static String withEntry(String json, String pkg, long versionCode, boolean content, String result, long at) {
        JSONArray out = new JSONArray();
        try {
            out.put(new JSONObject().put("package", pkg).put("versionCode", versionCode).put("content", content)
                    .put("result", result).put("at", at));
            JSONArray old = json != null ? new JSONArray(json) : new JSONArray();
            for (int i = 0; i < old.length() && out.length() < LOG_SIZE; i++) out.put(old.get(i));
        } catch (Exception e) {
            // A damaged log starts again
            Log.i(TAG, "The entry log was damaged and starts again: " + e.getClass().getSimpleName());
        }
        return out.toString();
    }

    /** The log, newest first, for Settings: {package, versionCode, content, result, at}. */
    static List<Map<String, Object>> entries(Context context) {
        List<Map<String, Object>> out = new ArrayList<>();
        try {
            JSONArray log = new JSONArray(prefs(context).getString(LOG_KEY, "[]"));
            for (int i = 0; i < log.length(); i++) {
                JSONObject entry = log.getJSONObject(i);
                Map<String, Object> map = new HashMap<>();
                map.put("package", entry.optString("package"));
                map.put("versionCode", entry.optLong("versionCode"));
                map.put("content", entry.optBoolean("content"));
                map.put("result", entry.optString("result"));
                map.put("at", entry.optLong("at"));
                out.add(map);
            }
        } catch (Exception e) {
            // Nothing readable
            Log.i(TAG, "The entry log couldn't be read: " + e.getClass().getSimpleName());
        }
        return out;
    }

    static long versionCodeOf(Context context, String pkg) {
        try {
            return context.getPackageManager().getPackageInfo(pkg, 0).getLongVersionCode();
        } catch (Exception e) {
            return -1;
        }
    }
}
