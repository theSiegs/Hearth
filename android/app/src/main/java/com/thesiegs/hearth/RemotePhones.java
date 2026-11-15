package com.thesiegs.hearth;

import android.content.Context;
import android.content.SharedPreferences;

import org.json.JSONException;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;

/**
 * The phones paired with the remote API (docs/tv-remote-api.md "Who a phone is", and V2.4 "Told roles"): each by its
 * certificate's SHA-256, with the name it gave, its role as an adult bound it ({@code none} for every new pairing, a
 * kid's phone with the kid's profile, or {@code parent}: v1's "adult"), when it was paired and last used, and a kid's
 * last ask over the API. Kept in the TV owner's user only, never synced or backed up.
 */
final class RemotePhones {
    private static final String FILE = "hearth_remote_phones";
    private static final String KEY = "phones";

    static final class Phone {
        final String fingerprint;
        final String name;
        /** {@link RemoteSession#ROLE_NONE}, {@link RemoteSession#ROLE_KID} or {@link RemoteSession#ROLE_PARENT}. */
        final String role;
        /** The kid's profile key for a kid's phone; else null. */
        final String profileKey;
        final long pairedAt;
        final long lastUsed;

        Phone(String fingerprint, String name, String role, String profileKey, long pairedAt, long lastUsed) {
            RemoteSession.Binding binding = new RemoteSession.Binding(role, profileKey);
            this.fingerprint = fingerprint;
            this.name = name;
            this.role = binding.role;
            this.profileKey = binding.profileKey;
            this.pairedAt = pairedAt;
            this.lastUsed = lastUsed;
        }

        /** v1's "an adult's phone". */
        boolean adult() {
            return RemoteSession.ROLE_PARENT.equals(role);
        }

        RemoteSession.Binding binding() {
            return new RemoteSession.Binding(role, profileKey);
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

    /** A newly paired phone, "not this one" (role none); pairing again keeps the role an adult gave it. */
    synchronized void add(String fingerprint, String name, long now) {
        JSONObject all = all();
        JSONObject one = all.optJSONObject(fingerprint);
        try {
            if (one == null) one = new JSONObject().put("role", RemoteSession.ROLE_NONE);
            all.put(fingerprint, one.put("name", name).put("pairedAt", now).put("lastUsed", now));
        } catch (JSONException e) {
            return;
        }
        save(all);
    }

    /** v1's mark: an adult's phone ({@code parent}) or not ({@code none}). */
    synchronized boolean setAdult(String fingerprint, boolean adult) {
        return setRole(fingerprint, adult ? RemoteSession.ROLE_PARENT : RemoteSession.ROLE_NONE, null);
    }

    /** Binds the phone: {@code none}, {@code parent}, or {@code kid} with the kid's profile key. */
    synchronized boolean setRole(String fingerprint, String role, String profileKey) {
        RemoteSession.Binding binding = new RemoteSession.Binding(role, profileKey);
        if (!binding.role.equals(role)) return false; // a kid's phone needs its kid
        JSONObject all = all();
        JSONObject one = all.optJSONObject(fingerprint);
        if (one == null) return false;
        try {
            String had = one.optString("person", "");
            one.put("role", binding.role);
            one.remove("adult");
            if (binding.profileKey != null) {
                one.put("person", binding.profileKey);
            } else {
                one.remove("person");
            }
            // Another kid (or no kid): the last ask was someone else's
            if (!had.equals(binding.profileKey != null ? binding.profileKey : "")) one.remove("ask");
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

    /** A kid's last ask over the remote API (RemoteSession), or null. */
    synchronized JSONObject lastAsk(String fingerprint) {
        JSONObject one = all().optJSONObject(fingerprint);
        return one != null ? one.optJSONObject("ask") : null;
    }

    synchronized void setLastAsk(String fingerprint, JSONObject ask) {
        JSONObject all = all();
        JSONObject one = all.optJSONObject(fingerprint);
        if (one == null) return;
        try {
            if (ask == null) {
                one.remove("ask");
            } else {
                one.put("ask", ask);
            }
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
        // Before roles: v1's adult mark
        String role = one.has("role") ? one.optString("role", RemoteSession.ROLE_NONE)
                : one.optBoolean("adult", false) ? RemoteSession.ROLE_PARENT : RemoteSession.ROLE_NONE;
        String person = one.isNull("person") ? null : one.optString("person", null);
        return new Phone(fingerprint, one.optString("name", "phone"), role, person, one.optLong("pairedAt", 0),
                one.optLong("lastUsed", 0));
    }
}
