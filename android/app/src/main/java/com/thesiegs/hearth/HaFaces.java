package com.thesiegs.hearth;

import android.content.Context;
import android.content.SharedPreferences;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.util.Log;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Profile photos from Home Assistant (experiment, feature/own-chooser): each Google TV profile's Home Assistant
 * person's picture (its entity_picture), when the TV is paired with Home Assistant. The person is the one the
 * Hearth integration maps the profile to, else the one person whose name is the profile's (whole, or first name).
 * Photographing Google TV's chooser tiles (ProfileAvatars) stays the fallback for profiles with no Home Assistant
 * picture. Read at most once a day, in the background.
 */
final class HaFaces {
    private static final String TAG = "HearthAvatars";
    private static final String PREFS = "hearth_ha_faces";
    private static final String AT_KEY = "at";
    static final long REFRESH_MS = 24 * 60 * 60_000L;
    /** A picture bigger than this isn't a face. */
    private static final int MAX_BYTES = 4 * 1024 * 1024;
    private static final ExecutorService EXECUTOR = Executors.newSingleThreadExecutor();

    private HaFaces() {
    }

    /** A Home Assistant person: entity id, name, picture path (null: none). */
    static final class Person {
        final String id;
        final String name;
        final String picture;

        Person(String id, String name, String picture) {
            this.id = id;
            this.name = name;
            this.picture = picture;
        }
    }

    /** The people in Home Assistant's /api/states answer. */
    static List<Person> people(JSONArray states) {
        List<Person> out = new ArrayList<>();
        if (states == null) return out;
        for (int i = 0; i < states.length(); i++) {
            JSONObject state = states.optJSONObject(i);
            String id = state != null ? state.optString("entity_id", "") : "";
            if (!id.startsWith("person.")) continue;
            JSONObject attributes = state.optJSONObject("attributes");
            String name = attributes != null ? attributes.optString("friendly_name", "") : "";
            String picture = attributes != null ? attributes.optString("entity_picture", "") : "";
            out.add(new Person(id, name.trim(), picture.trim().isEmpty() ? null : picture.trim()));
        }
        return out;
    }

    /**
     * The Home Assistant person a profile is: the one the integration maps its key to, else the only person whose
     * whole name or first name is the profile's name (two such people: none, rather than the wrong face).
     */
    static Person personFor(String key, String name, Map<String, String> mapped, List<Person> people) {
        String id = key != null && mapped != null ? mapped.get(key) : null;
        if (id != null) {
            for (Person p : people) {
                if (p.id.equals(id)) return p;
            }
        }
        if (name == null || name.trim().isEmpty()) return null;
        String wanted = name.trim().toLowerCase(Locale.ROOT);
        Person whole = null;
        Person first = null;
        int wholeCount = 0;
        int firstCount = 0;
        for (Person p : people) {
            String n = p.name.toLowerCase(Locale.ROOT);
            if (n.isEmpty()) continue;
            if (n.equals(wanted)) {
                whole = p;
                wholeCount++;
            } else if (n.split("\\s+")[0].equals(wanted) || wanted.split("\\s+")[0].equals(n)) {
                first = p;
                firstCount++;
            }
        }
        if (wholeCount == 1) return whole;
        if (wholeCount == 0 && firstCount == 1) return first;
        return null;
    }

    /** Whether a picture path is one to fetch from Home Assistant itself (its own server, not anywhere else). */
    static boolean fetchable(String picture) {
        return picture != null && picture.startsWith("/") && !picture.startsWith("//");
    }

    private static SharedPreferences prefs(Context context) {
        return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    /** Fetches the faces again in the background if they're older than {@link #REFRESH_MS} (or {@code force}). */
    static void refreshIfDue(Context context, boolean force) {
        Context app = context.getApplicationContext();
        if (!HaConfig.isConfigured(app)) return;
        long at = prefs(app).getLong(AT_KEY, 0);
        if (!force && Math.abs(System.currentTimeMillis() - at) < REFRESH_MS) return;
        prefs(app).edit().putLong(AT_KEY, System.currentTimeMillis()).apply();
        EXECUTOR.execute(() -> refresh(app));
    }

    private static void refresh(Context context) {
        HaApi.Response states = HaApi.exchange(context, "GET", "/api/states", null);
        if (!states.ok() || states.body == null) {
            Log.i(TAG, "Home Assistant faces: couldn't read the people (" + states.code + ")");
            return;
        }
        List<Person> people;
        try {
            people = people(new JSONArray(new String(states.body, "UTF-8")));
        } catch (Exception e) {
            Log.i(TAG, "Home Assistant faces: the people aren't readable");
            return;
        }
        Map<String, String> mapped = HaAllowance.people(context);
        int saved = 0;
        int none = 0;
        boolean changed = false;
        for (ProfileUsers.Known profile : ProfileUsers.known(context)) {
            Person person = personFor(profile.key, profile.name, mapped, people);
            if (person == null || !fetchable(person.picture)) {
                // No Home Assistant picture: the chooser's photo (if any) is used
                if (ProfileAvatars.dropHaPhoto(context, profile.name)) changed = true;
                none++;
                continue;
            }
            HaApi.Response picture = HaApi.exchange(context, "GET", person.picture, null);
            if (!picture.ok() || picture.body == null || picture.body.length > MAX_BYTES) {
                none++;
                continue;
            }
            Bitmap bitmap = BitmapFactory.decodeByteArray(picture.body, 0, picture.body.length);
            if (bitmap == null) {
                none++;
                continue;
            }
            int outcome = ProfileAvatars.saveHaPhoto(context, profile.name, bitmap);
            bitmap.recycle();
            if (outcome == ProfileAvatars.SAVED) changed = true;
            if (outcome != ProfileAvatars.FAILED) saved++;
        }
        Log.i(TAG, "Home Assistant faces: " + saved + " profile(s) with one, " + none + " without");
        if (changed) MainActivity.notifyProfileChanged();
    }
}
