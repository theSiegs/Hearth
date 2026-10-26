package com.thesiegs.hearth;

import java.util.Arrays;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * Between the household's entries and this TV's own settings (docs/household-sync.md): which settings are entries, how a
 * person's name stands for their profile on each TV, and what to do with an entry that arrives. Nothing here knows
 * about Android; {@link Local} is this TV's settings, so the rules can be tested alone.
 *
 * <p>Two kinds so far. {@code pairing}: a profile's choice of app profile (or "always ask") for a streaming app; the
 * item is the app's package and the value is {@code {"mode":"profile","appProfile":"…"}} or {@code {"mode":"picker"}};
 * no entry means the automatic match. {@code pin}: a saved PIN; the item is {@code <package>|<app profile>} and the value
 * is the PIN's digits; a profile of "" is the whole TV's (a content PIN not tied to a person).
 *
 * <p>Three more that the app's own side puts in place, not this class (they're its settings and files): {@code look}, a
 * profile's chosen settings as JSON; {@code layout}, its apps, rows and spacers as JSON; and {@code wallpaper}, one of its
 * pictures, the item being the slot ({@link #SLOTS}) and the value {@code {"hash":"…"}} naming a HouseholdPictures file.
 */
final class HouseholdBridge {
    static final String PAIRING = "pairing";
    static final String PIN = "pin";
    static final String LOOK = "look";
    static final String LAYOUT = "layout";
    static final String WALLPAPER = "wallpaper";
    /** The household's Parent PIN: the whole TV's ({@link #SHARED}), item "", the value its salted hash (never the PIN). */
    static final String PARENT_PIN = "parent_pin";
    /** Continue Watching: a person's played and kept titles (HouseholdWatch). */
    static final String WATCH = "watch";
    /** Where a wallpaper picture shows: always, by day, by night. */
    static final List<String> SLOTS = Arrays.asList("any", "day", "night");
    /** A look or layout's JSON may be this long; a layout with hundreds of apps is some 100 KB. */
    static final int MAX_LOOK_CHARS = 1024 * 1024;
    /** The profile name of a setting that belongs to the whole TV, not a person. */
    static final String SHARED = "";

    /** This TV's own settings, as sync reads and changes them. */
    interface Local {
        /** The profiles this TV knows, as {@code normalized name -> its own key}. A name two profiles share isn't in it. */
        Map<String, String> profiles();

        /** A profile's pairing choices that aren't automatic, as {@code package -> value} (see the class comment). */
        Map<String, String> pairings(String key);

        /** Sets a pairing choice; {@code value} null makes it automatic again. */
        void setPairing(String key, String pkg, String value);

        /** PINs saved for a profile ({@code key} null: the whole TV's), as {@code item -> digits}. */
        Map<String, String> pins(String key);

        /** Saves a PIN; {@code digits} null removes it. */
        void setPin(String key, String item, String digits);
    }

    private HouseholdBridge() {
    }

    /** A pairing as its entry value. */
    static String pairingValue(String mode, String appProfile) {
        if (ProfilePairing.MODE_PICKER.equals(mode)) return "{\"mode\":\"picker\"}";
        try {
            return new org.json.JSONObject().put("mode", "profile").put("appProfile", appProfile).toString();
        } catch (org.json.JSONException e) {
            throw new IllegalStateException(e);
        }
    }

    /** A wallpaper entry's value for the picture named {@code hash}. */
    static String wallpaperValue(String hash) {
        try {
            return new org.json.JSONObject().put("hash", hash).toString();
        } catch (org.json.JSONException e) {
            throw new IllegalStateException(e);
        }
    }

    /** The picture a wallpaper entry's value names, or null when it names none. */
    static String pictureOf(String value) {
        try {
            String hash = new org.json.JSONObject(value).optString("hash", "");
            return HouseholdPictures.validHash(hash) ? hash : null;
        } catch (org.json.JSONException e) {
            return null;
        }
    }

    /**
     * The pictures the live entries name: wallpapers, then Continue Watching posters (HouseholdWatch), so an exchange
     * that can carry only some brings the wallpapers first. What a TV keeps, and asks another TV for when it lacks one.
     */
    static Set<String> pictures(HouseholdLog log) {
        Set<String> out = new LinkedHashSet<>();
        List<HouseholdEntry> all = log.all();
        for (HouseholdEntry entry : all) {
            if (!WALLPAPER.equals(entry.kind) || entry.deleted) continue;
            String hash = pictureOf(entry.value);
            if (hash != null) out.add(hash);
        }
        for (HouseholdEntry entry : all) {
            String poster = HouseholdWatch.posterOf(entry);
            if (poster != null) out.add(poster);
        }
        return out;
    }

    /** What a profile's settings are now, as entries that don't match the log yet: {@code kind|profile|item -> value}. */
    static Map<String, String[]> unpublished(Local local, HouseholdLog log) {
        Map<String, String[]> out = new HashMap<>();
        for (Map.Entry<String, String> profile : local.profiles().entrySet()) {
            String name = profile.getKey();
            for (Map.Entry<String, String> pairing : local.pairings(profile.getValue()).entrySet()) {
                addIfNew(out, log, PAIRING, name, pairing.getKey(), pairing.getValue());
            }
            for (Map.Entry<String, String> pin : local.pins(profile.getValue()).entrySet()) {
                addIfNew(out, log, PIN, name, pin.getKey(), pin.getValue());
            }
        }
        for (Map.Entry<String, String> pin : local.pins(null).entrySet()) {
            addIfNew(out, log, PIN, SHARED, pin.getKey(), pin.getValue());
        }
        return out;
    }

    private static void addIfNew(Map<String, String[]> out, HouseholdLog log, String kind, String profile, String item,
            String value) {
        HouseholdEntry have = log.get(kind, profile, item);
        // A deleted entry counts too: a value saved here again after a delete is a newer write, but one the household
        // already deleted and this TV never heard about must not come back, so only a missing entry is published.
        if (have == null && !log.hasEntry(kind, profile, item)) out.put(kind + "|" + profile + "|" + item, new String[] {kind, profile, item, value});
    }

    /**
     * Applies every live or deleted entry whose profile this TV has. Returns how many settings it changed. A setting
     * that already matches isn't touched. An entry for a profile this TV doesn't have yet stays in the log and is applied
     * when the profile appears (call this again).
     */
    static int apply(Local local, HouseholdLog log) {
        int changed = 0;
        Map<String, String> profiles = local.profiles();
        for (HouseholdEntry entry : log.all()) {
            String key;
            if (PIN.equals(entry.kind) && SHARED.equals(entry.profile)) {
                key = null;
            } else {
                key = profiles.get(entry.profile);
                if (key == null) continue;
            }
            if (PAIRING.equals(entry.kind) && key != null) {
                String have = local.pairings(key).get(entry.item);
                if (entry.deleted) {
                    if (have != null) {
                        local.setPairing(key, entry.item, null);
                        changed++;
                    }
                } else if (!entry.value.equals(have) && validPairing(entry.value)) {
                    local.setPairing(key, entry.item, entry.value);
                    changed++;
                }
            } else if (PIN.equals(entry.kind)) {
                String have = local.pins(key).get(entry.item);
                if (entry.deleted) {
                    if (have != null) {
                        local.setPin(key, entry.item, null);
                        changed++;
                    }
                } else if (!entry.value.equals(have) && validPin(entry.item, entry.value)) {
                    local.setPin(key, entry.item, entry.value);
                    changed++;
                }
            }
        }
        return changed;
    }

    static boolean validPairing(String value) {
        try {
            org.json.JSONObject o = new org.json.JSONObject(value);
            String mode = o.optString("mode", "");
            if (ProfilePairing.MODE_PICKER.equals(mode)) return true;
            return ProfilePairing.MODE_PROFILE.equals(mode) && !o.optString("appProfile", "").trim().isEmpty()
                    && o.optString("appProfile").length() <= 200;
        } catch (org.json.JSONException e) {
            return false;
        }
    }

    /** A PIN of digits only, for an item of the form {@code package|app profile}. */
    static boolean validPin(String item, String digits) {
        int bar = item.indexOf('|');
        if (bar <= 0 || bar == item.length() - 1 || digits.isEmpty() || digits.length() > 12) return false;
        for (int i = 0; i < digits.length(); i++) {
            char c = digits.charAt(i);
            if (c < '0' || c > '9') return false;
        }
        return true;
    }
}
