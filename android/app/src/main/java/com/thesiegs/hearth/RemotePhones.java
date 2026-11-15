package com.thesiegs.hearth;

import android.content.Context;
import android.content.SharedPreferences;

import org.json.JSONException;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;

/**
 * The phones paired with the remote API (docs/tv-remote-api.md "Who a phone is"): each by its certificate's SHA-256,
 * with the name it gave, whether an adult marked it as an adult's phone (new phones are restricted), and when it was
 * paired and last used. Kept in the TV owner's user only, never synced or backed up.
 */
final class RemotePhones {
    private static final String FILE = "hearth_remote_phones";
    private static final String KEY = "phones";

    static final class Phone {
        final String fingerprint;
        final String name;
        final boolean adult;
        final long pairedAt;
        final long lastUsed;

        Phone(String fingerprint, String name, boolean adult, long pairedAt, long lastUsed) {
            this.fingerprint = fingerprint;
            this.name = name;
            this.adult = adult;
            this.pairedAt = pairedAt;
            this.lastUsed = lastUsed;
        }

        JSONObject toJson() throws JSONException {
            return new JSONObject().put("fingerprint", fingerprint).put("name", name).put("adult", adult)
                    .put("pairedAt", pairedAt).put("lastUsed", lastUsed);
        }
    }

    private final SharedPreferences prefs;

    RemotePhones(Context context) {
        prefs = context.getSharedPreferences(FILE, Context.MODE_PRIVATE);
    }

    synchronized Phone get(String fingerprint) {
        JSONObject one = all().optJSONObject(fingerprint);
        return one == null ? null : phone(fingerprint, one);
    }

    synchronized List<Phone> list() {
        JSONObject all = all();
        List<Phone> found = new ArrayList<>();
        for (Iterator<String> keys = all.keys(); keys.hasNext(); ) {
            String fp = keys.next();
            JSONObject one = all.optJSONObject(fp);
            if (one != null) found.add(phone(fp, one));
        }
        found.sort((a, b) -> Long.compare(b.pairedAt, a.pairedAt));
        return found;
    }

    boolean any() {
        return !list().isEmpty();
    }

    /** A newly paired phone, restricted; pairing again keeps an adult's mark. */
    synchronized void add(String fingerprint, String name, long now) {
        JSONObject all = all();
        JSONObject one = all.optJSONObject(fingerprint);
        try {
            if (one == null) one = new JSONObject().put("adult", false);
            all.put(fingerprint, one.put("name", name).put("pairedAt", now).put("lastUsed", now));
        } catch (JSONException e) {
            return;
        }
        save(all);
    }

    synchronized boolean setAdult(String fingerprint, boolean adult) {
        JSONObject all = all();
        JSONObject one = all.optJSONObject(fingerprint);
        if (one == null) return false;
        try {
            one.put("adult", adult);
        } catch (JSONException e) {
            return false;
        }
        save(all);
        return true;
    }

    synchronized void touch(String fingerprint, long now) {
        JSONObject all = all();
        JSONObject one = all.optJSONObject(fingerprint);
        if (one == null) return;
        try {
            one.put("lastUsed", now);
        } catch (JSONException e) {
            return;
        }
        save(all);
    }

    synchronized boolean remove(String fingerprint) {
        JSONObject all = all();
        if (all.remove(fingerprint) == null) return false;
        save(all);
        return true;
    }

    private JSONObject all() {
        try {
            return new JSONObject(prefs.getString(KEY, "{}"));
        } catch (JSONException e) {
            return new JSONObject();
        }
    }

    private void save(JSONObject all) {
        prefs.edit().putString(KEY, all.toString()).apply();
    }

    private static Phone phone(String fingerprint, JSONObject one) {
        return new Phone(fingerprint, one.optString("name", "phone"), one.optBoolean("adult", false),
                one.optLong("pairedAt", 0), one.optLong("lastUsed", 0));
    }
}
