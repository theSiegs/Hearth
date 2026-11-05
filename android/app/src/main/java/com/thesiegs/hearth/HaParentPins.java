package com.thesiegs.hearth;

import android.content.Context;
import android.content.SharedPreferences;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.List;

/**
 * The adults' parent PINs from the Hearth integration (docs/home-assistant-integration.md, Parent PINs). While the
 * integration has any, they are the TV's Parent PIN (any of them), in place of its own: a PIN is checked by the
 * integration ({@code verify_pin}), whose answer and lockout are final whenever it's reachable. The hashes the state
 * document carries (only when they changed: {@code parent_pins_version}) are kept here, sealed with a Keystore key, to
 * check PINs with Home Assistant down.
 *
 * The document stops naming them (Home Assistant's were removed) or the TV is unpaired: the last ones are kept, so the
 * TV is never left without a Parent PIN, but they're no longer Home Assistant's to manage ([managed]), and an adult can
 * set a PIN of the TV's own again, which replaces them ([forget]).
 */
final class HaParentPins {
    private static final String KEY_SEALED = "ha_parent_pins_sealed";
    private static final String KEY_VERSION = "ha_parent_pins_version";
    private static final String KEY_MANAGED = "ha_parent_pins_managed";
    /** Hashes kept in the clear by 2026.11.04: sealed on first read, then removed. */
    private static final String KEY_PLAIN = "ha_parent_pins";
    /** How many times a Parent PIN pad here locked out wrong guesses, for the integration (only goes up). */
    private static final String KEY_LOCKOUTS = "parent_pin_lockouts";
    private static final String ALIAS = "hearth_ha_parent_pins";

    /** What the integration said about a PIN: yes, no, or nothing (unreachable, or it has none: check here). */
    enum Verdict { YES, NO, UNKNOWN }

    private HaParentPins() {}

    private static SharedPreferences prefs(Context context) {
        return context.getSharedPreferences(LauncherAccessibilityService.DEVICE_PREFS, Context.MODE_PRIVATE);
    }

    /**
     * Takes the document's parent PINs. With {@code parent_pins} the hashes changed: they're kept. With only
     * {@code parent_pins_version}, the kept ones are still current. With neither, Home Assistant has none: the last
     * ones stay, no longer managed.
     */
    static synchronized void applyDocument(Context context, JSONObject state) {
        if (state == null) return;
        JSONArray pins = state.optJSONArray("parent_pins");
        String version = state.optString("parent_pins_version", "");
        SharedPreferences.Editor editor = prefs(context).edit();
        if (pins != null) {
            List<String> hashes = new ArrayList<>();
            for (int i = 0; i < pins.length(); i++) {
                JSONObject pin = pins.optJSONObject(i);
                String hash = pin != null ? pin.optString("hash", "") : "";
                if (Household.PARENT_PIN_HASH.matcher(hash).matches() && !hashes.contains(hash)) hashes.add(hash);
            }
            String sealed = hashes.isEmpty() ? null
                    : SecretBox.sealText(SecretBox.keystore(), ALIAS, new JSONArray(hashes).toString());
            if (sealed == null) {
                editor.putBoolean(KEY_MANAGED, false);
            } else {
                editor.putString(KEY_SEALED, sealed).putString(KEY_VERSION, version).putBoolean(KEY_MANAGED, true)
                        .remove(KEY_PLAIN);
            }
        } else if (version.isEmpty() || !version.equals(prefs(context).getString(KEY_VERSION, null))) {
            editor.putBoolean(KEY_MANAGED, false);
        } else {
            editor.putBoolean(KEY_MANAGED, true);
        }
        editor.apply();
    }

    /** The kept hashes' version, for the status ("" when none: the next document carries them). */
    static String version(Context context) {
        return hashes(context).isEmpty() ? "" : prefs(context).getString(KEY_VERSION, "");
    }

    /** The kept hashes (empty: the TV's own Parent PIN applies). */
    static synchronized List<String> hashes(Context context) {
        SharedPreferences prefs = prefs(context);
        String json = null;
        String sealed = prefs.getString(KEY_SEALED, null);
        if (sealed != null) {
            json = SecretBox.openText(SecretBox.keystore(), ALIAS, sealed);
        } else if (prefs.contains(KEY_PLAIN)) {
            // Kept in the clear by an older build: sealed now
            json = prefs.getString(KEY_PLAIN, "[]");
            String resealed = SecretBox.sealText(SecretBox.keystore(), ALIAS, json);
            if (resealed != null) prefs.edit().putString(KEY_SEALED, resealed).remove(KEY_PLAIN).apply();
        }
        List<String> out = new ArrayList<>();
        if (json == null) return out;
        try {
            JSONArray array = new JSONArray(json);
            for (int i = 0; i < array.length(); i++) {
                String hash = array.optString(i, "");
                if (Household.PARENT_PIN_HASH.matcher(hash).matches()) out.add(hash);
            }
        } catch (Exception ignored) {
            // None kept
        }
        return out;
    }

    /** Whether Home Assistant's parent PINs are kept here (in place of the TV's own). */
    static boolean kept(Context context) {
        return !hashes(context).isEmpty();
    }

    /** Home Assistant sets the Parent PIN: the TV is paired and its last document named PINs. */
    static boolean managed(Context context) {
        return prefs(context).getBoolean(KEY_MANAGED, false) && kept(context) && HaIntegration.isPaired(context);
    }

    /** A Parent PIN of the TV's own was set here: the kept ones go. */
    static synchronized void forget(Context context) {
        prefs(context).edit().remove(KEY_SEALED).remove(KEY_VERSION).remove(KEY_MANAGED).remove(KEY_PLAIN).apply();
    }

    /**
     * Whether {@code pin} is a Parent PIN: while Home Assistant's are kept, the integration decides when it answers
     * (its lockout included), else the kept hashes; otherwise the TV's own. Not on the main thread: it may ask Home
     * Assistant.
     */
    static boolean verify(Context context, String pin) {
        List<String> hashes = hashes(context);
        if (hashes.isEmpty()) {
            return ParentPinHash.verify(pin, FlutterPrefs.getString(context, "device_parent_pin_hash", null));
        }
        Verdict verdict = HaIntegration.isPaired(context) ? HaIntegration.verifyPin(context, pin) : Verdict.UNKNOWN;
        if (verdict != Verdict.UNKNOWN) return verdict == Verdict.YES;
        boolean ok = false;
        // Every one is checked, so the time doesn't tell which matched
        for (String hash : hashes) ok |= ParentPinHash.verify(pin, hash);
        return ok;
    }

    /** Whether the TV has a Parent PIN at all. */
    static boolean any(Context context) {
        return kept(context) || FlutterPrefs.getString(context, "device_parent_pin_hash", null) != null;
    }

    static synchronized void noteLockout(Context context) {
        SharedPreferences prefs = prefs(context);
        prefs.edit().putInt(KEY_LOCKOUTS, prefs.getInt(KEY_LOCKOUTS, 0) + 1).apply();
    }

    static int lockouts(Context context) {
        return prefs(context).getInt(KEY_LOCKOUTS, 0);
    }
}
