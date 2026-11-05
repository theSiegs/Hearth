package com.thesiegs.hearth;

import android.content.Context;
import android.content.SharedPreferences;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.List;

/**
 * The adults' parent PINs from the Hearth integration (docs/home-assistant-integration.md, Parent PINs): each adult's
 * own, as hashes in this TV's form, taken from the state document's "parent_pins". While there are any, they are the
 * TV's Parent PIN (any of them), in place of its own; they are kept here so PINs work with Home Assistant down.
 *
 * The document stops naming them (Home Assistant's were removed) or the TV is unpaired: the last ones are kept, so the
 * TV is never left without a Parent PIN, but they're no longer Home Assistant's to manage ([managed]), and an adult can
 * set a PIN of the TV's own again, which replaces them ([forget]).
 */
final class HaParentPins {
    private static final String KEY_HASHES = "ha_parent_pins";
    private static final String KEY_MANAGED = "ha_parent_pins_managed";
    /** How many times a Parent PIN pad here locked out wrong guesses, for the integration (only goes up). */
    private static final String KEY_LOCKOUTS = "parent_pin_lockouts";

    private HaParentPins() {}

    private static SharedPreferences prefs(Context context) {
        return context.getSharedPreferences(LauncherAccessibilityService.DEVICE_PREFS, Context.MODE_PRIVATE);
    }

    /** Takes the document's parent PINs; a document without them leaves the last ones, no longer managed. */
    static void applyDocument(Context context, JSONObject state) {
        if (state == null) return;
        JSONArray pins = state.optJSONArray("parent_pins");
        List<String> hashes = new ArrayList<>();
        for (int i = 0; pins != null && i < pins.length(); i++) {
            JSONObject pin = pins.optJSONObject(i);
            String hash = pin != null ? pin.optString("hash", "") : "";
            if (Household.PARENT_PIN_HASH.matcher(hash).matches() && !hashes.contains(hash)) hashes.add(hash);
        }
        SharedPreferences.Editor editor = prefs(context).edit();
        if (hashes.isEmpty()) {
            editor.putBoolean(KEY_MANAGED, false);
        } else {
            editor.putString(KEY_HASHES, new JSONArray(hashes).toString()).putBoolean(KEY_MANAGED, true);
        }
        editor.apply();
    }

    /** The kept hashes (empty: the TV's own Parent PIN applies). */
    static List<String> hashes(Context context) {
        List<String> out = new ArrayList<>();
        try {
            JSONArray array = new JSONArray(prefs(context).getString(KEY_HASHES, "[]"));
            for (int i = 0; i < array.length(); i++) {
                String hash = array.optString(i, "");
                if (Household.PARENT_PIN_HASH.matcher(hash).matches()) out.add(hash);
            }
        } catch (Exception ignored) {
            // None kept
        }
        return out;
    }

    /** Home Assistant sets the Parent PIN: the TV is paired and its last document named PINs. */
    static boolean managed(Context context) {
        return prefs(context).getBoolean(KEY_MANAGED, false) && !hashes(context).isEmpty()
                && HaIntegration.isPaired(context);
    }

    /** A Parent PIN of the TV's own was set here: the kept ones go. */
    static void forget(Context context) {
        prefs(context).edit().remove(KEY_HASHES).remove(KEY_MANAGED).apply();
    }

    /** Whether [pin] is a Parent PIN: any adult's from Home Assistant while there are any, else the TV's own. */
    static boolean verify(Context context, String pin) {
        List<String> hashes = hashes(context);
        if (hashes.isEmpty()) {
            return ParentPinHash.verify(pin, FlutterPrefs.getString(context, "device_parent_pin_hash", null));
        }
        boolean ok = false;
        // Every one is checked, so the time doesn't tell which matched
        for (String hash : hashes) ok |= ParentPinHash.verify(pin, hash);
        return ok;
    }

    /** Whether the TV has a Parent PIN at all. */
    static boolean any(Context context) {
        return !hashes(context).isEmpty() || FlutterPrefs.getString(context, "device_parent_pin_hash", null) != null;
    }

    static synchronized void noteLockout(Context context) {
        SharedPreferences prefs = prefs(context);
        prefs.edit().putInt(KEY_LOCKOUTS, prefs.getInt(KEY_LOCKOUTS, 0) + 1).apply();
    }

    static int lockouts(Context context) {
        return prefs(context).getInt(KEY_LOCKOUTS, 0);
    }
}
