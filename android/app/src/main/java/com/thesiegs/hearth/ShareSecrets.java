package com.thesiegs.hearth;

import android.content.Context;
import android.util.Log;

import org.json.JSONArray;
import org.json.JSONObject;

import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Date;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

/**
 * The secrets of a copy to another TV (ShareService): the streaming apps' PINs and the Home Assistant settings. They
 * are the Java side's alone: they travel as a message of their own, are never handed to Flutter, are built only once
 * both parents said the digits match, and the receiving TV checks every line again before it saves it.
 *
 * <p>A PIN is saved only where this TV has the pairing it belongs to (a PIN for an app profile nobody here is paired
 * with would never be typed), never over a PIN that works, and never as a kids profile's Google TV PIN. Home Assistant
 * isn't sent the sender's token: the sender has Home Assistant make a new one for the other TV, which the person can
 * see (and revoke) by its name in their Home Assistant profile. The TV status webhook id isn't sent either: it belongs
 * to one TV's automation.
 */
final class ShareSecrets {
    private static final String TAG = "HearthShare";
    private static final int MAX_PINS = 200;
    private static final int MIN_PIN = 3;
    private static final int MAX_PIN = 8;
    private static final int MAX_TEXT = 200;
    private static final int TOKEN_DAYS = 3650;

    private ShareSecrets() {
    }

    // ---- The sending TV ----

    /** What this TV could send for these profiles ({@code keys}): {pins: how many saved, ha: set up}. For the screen. */
    static Map<String, Object> offer(Context context, List<String> keys) {
        int pins = 0;
        for (String key : keys) pins += slotsToSend(context, key, ProfilePairing.isKids(context, key)).size();
        pins += slotsToSend(context, PinVault.SHARED, false).size();
        Map<String, Object> offer = new HashMap<>();
        offer.put("pins", pins);
        offer.put("ha", HaConfig.isConfigured(context));
        return offer;
    }

    /**
     * The message of secrets to send. {@code request}: {"profiles": {"p1": "user:0:alex"}, "pins": true|false,
     * "ha": true|false}. Makes the Home Assistant token now, so it exists only for a copy that is really happening.
     * Blocks (Home Assistant): run it off the main thread.
     */
    static String build(Context context, String request, String fromTv) {
        JSONObject out = new JSONObject();
        try {
            JSONObject wanted = new JSONObject(request);
            out.put("v", 1);
            if (wanted.optBoolean("pins")) {
                JSONArray pins = new JSONArray();
                JSONObject profiles = wanted.optJSONObject("profiles");
                if (profiles != null) {
                    for (java.util.Iterator<String> it = profiles.keys(); it.hasNext(); ) {
                        String id = it.next();
                        String key = profiles.optString(id, "");
                        if (!key.isEmpty()) addPins(context, pins, id, key, ProfilePairing.isKids(context, key));
                    }
                }
                addPins(context, pins, null, PinVault.SHARED, false);
                out.put("pins", pins);
            }
            if (wanted.optBoolean("household")) {
                // The household's key goes to the other TV (a household is made here first if there is none)
                byte[] key = Household.keyToJoin(context);
                if (key != null) {
                    out.put("household", java.util.Base64.getEncoder().encodeToString(key));
                    java.util.Arrays.fill(key, (byte) 0);
                } else {
                    out.put("householdFailed", true);
                }
            }
            if (wanted.optBoolean("ha")) {
                String base = HaConfig.baseUrl(context);
                String name = tokenName(fromTv, new Date());
                String token = base == null ? null : HaEvents.mintToken(context, name, TOKEN_DAYS);
                if (token == null) {
                    out.put("haFailed", true);
                } else {
                    out.put("ha", new JSONObject().put("url", base).put("token", token));
                }
            }
        } catch (Exception e) {
            Log.w(TAG, "The secrets weren't put together: " + e.getClass().getSimpleName());
            return "{\"v\":1}";
        }
        return out.toString();
    }

    /** The name the other TV's token has in Home Assistant: unique (Home Assistant refuses a name twice). */
    static String tokenName(String fromTv, Date now) {
        String stamp = new SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.ROOT).format(now);
        String tv = ShareData.tidy(fromTv == null ? "" : fromTv);
        return "Hearth copy from " + (tv.isEmpty() ? "another TV" : tv) + " " + stamp;
    }

    private static List<PinVault.Slot> slotsToSend(Context context, String owner, boolean kids) {
        List<PinVault.Slot> out = new ArrayList<>();
        for (PinVault.Slot slot : PinVault.slots(context, owner)) {
            if (!PinVault.STATUS_SAVED.equals(slot.status)) continue; // one the app refused isn't worth sending
            if (kids && isGoogleTvPin(slot.pkg)) continue; // a kids profile's way into Google TV isn't copied
            out.add(slot);
        }
        return out;
    }

    private static void addPins(Context context, JSONArray pins, String profileId, String owner, boolean kids)
            throws Exception {
        for (PinVault.Slot slot : slotsToSend(context, owner, kids)) {
            char[] pin = PinVault.open(context, slot.owner, slot.pkg, slot.appProfile);
            if (pin == null) continue;
            try {
                JSONObject line = new JSONObject().put("pkg", slot.pkg).put("appProfile", slot.appProfile)
                        .put("pin", new String(pin));
                if (profileId != null) line.put("profile", profileId);
                pins.put(line);
            } finally {
                java.util.Arrays.fill(pin, '\0');
            }
        }
    }

    static boolean isGoogleTvPin(String pkg) {
        return LauncherAccessibilityService.GOOGLE_TV_PACKAGE.equals(pkg);
    }

    // ---- The receiving TV ----

    /** What arrived, for the screen: {pins: how many, ha: the address or "", haFailed}. Never the PINs or the token. */
    static Map<String, Object> summary(String secrets) {
        Map<String, Object> out = new HashMap<>();
        int pins = 0;
        String ha = "";
        boolean haFailed = false;
        try {
            JSONObject root = new JSONObject(secrets);
            pins = Math.min(root.optJSONArray("pins") == null ? 0 : root.optJSONArray("pins").length(), MAX_PINS);
            JSONObject haObject = root.optJSONObject("ha");
            if (haObject != null && !haObject.optString("token", "").isEmpty()) {
                ha = hostOf(haObject.optString("url", ""));
            }
            haFailed = root.optBoolean("haFailed");
        } catch (Exception ignored) {
        }
        out.put("pins", pins);
        out.put("ha", ha);
        out.put("haFailed", haFailed);
        boolean household = false;
        try {
            household = new JSONObject(secrets).optString("household", "").length() > 0;
        } catch (Exception ignored) {
        }
        out.put("household", household);
        return out;
    }

    private static String hostOf(String url) {
        String normalized = HaConfig.normalizeUrl(url);
        if (normalized == null) return "";
        try {
            return new java.net.URL(normalized).getHost();
        } catch (Exception e) {
            return "";
        }
    }

    /** Where PINs go on the receiving TV: what it needs to know about its own profiles and vault. */
    interface Target {
        /** Whether the profile (key) is a kids profile. */
        boolean isKids(String profileKey);

        /** The app profile this TV has the profile paired with for the app (lower case), or null. */
        String chosenProfile(String pkg, String profileKey);

        /** The vault's status for this PIN here: PinVault.STATUS_NONE, STATUS_SAVED or STATUS_REJECTED. */
        String status(String owner, String pkg, String appProfile);

        boolean save(String owner, String pkg, String appProfile, char[] pin);
    }

    /**
     * Saves the PINs of {@code secrets} that belong here. {@code targets}: the copy's profile id to this TV's profile
     * key (a profile the parent didn't choose isn't in it). Returns {added, kept, skipped}.
     */
    static Map<String, Object> applyPins(String secrets, Map<String, String> targets, Target target) {
        int added = 0;
        int kept = 0;
        int skipped = 0;
        JSONArray pins = null;
        try {
            pins = new JSONObject(secrets).optJSONArray("pins");
        } catch (Exception ignored) {
        }
        for (int i = 0; pins != null && i < Math.min(pins.length(), MAX_PINS); i++) {
            JSONObject line = pins.optJSONObject(i);
            String pkg = line == null ? null : line.optString("pkg", null);
            String appProfile = line == null ? "" : ShareData.tidy(line.optString("appProfile", ""));
            String pin = line == null ? "" : line.optString("pin", "");
            String profileId = line == null || line.isNull("profile") ? null : line.optString("profile", null);
            if (!validPin(pin) || appProfile.isEmpty() || !knownApp(pkg, profileId == null)
                    || (profileId == null && !appProfile.equalsIgnoreCase(ContentPin.VAULT_PROFILE))) {
                skipped++;
                continue;
            }
            String owner = null;
            if (profileId != null) {
                owner = targets.get(profileId);
                if (owner == null) {
                    skipped++; // a profile the parent didn't copy
                    continue;
                }
                if (isGoogleTvPin(pkg) ? target.isKids(owner) : !samePerson(appProfile, target.chosenProfile(pkg, owner))) {
                    skipped++; // not for a kids profile, or for an app profile nobody here is paired with
                    continue;
                }
            }
            String status = target.status(owner, pkg, appProfile);
            if (PinVault.STATUS_SAVED.equals(status)) {
                kept++;
                continue;
            }
            if (target.save(owner, pkg, appProfile, pin.toCharArray())) added++;
            else skipped++;
        }
        Map<String, Object> result = new HashMap<>();
        result.put("added", added);
        result.put("kept", kept);
        result.put("skipped", skipped);
        return result;
    }

    /** Digits only, of a length a PIN has. */
    static boolean validPin(String pin) {
        if (pin == null || pin.length() < MIN_PIN || pin.length() > MAX_PIN) return false;
        for (int i = 0; i < pin.length(); i++) {
            if (pin.charAt(i) < '0' || pin.charAt(i) > '9') return false;
        }
        return true;
    }

    /** An app Hearth types PINs for (a profile's), or the whole-TV content PIN's app. */
    private static boolean knownApp(String pkg, boolean wholeTv) {
        if (pkg == null) return false;
        if (wholeTv) return ContentPin.PACKAGE.equals(pkg);
        return ProfilePairing.supports(pkg) || isGoogleTvPin(pkg);
    }

    private static boolean samePerson(String a, String b) {
        return b != null && PinVault.id("x", "p", a).equals(PinVault.id("x", "p", b));
    }

    /** The Home Assistant settings of {@code secrets}, saved as this TV's: false when there are none or they're unusable. */
    static boolean applyHa(Context context, String secrets) {
        try {
            JSONObject ha = new JSONObject(secrets).optJSONObject("ha");
            if (ha == null) return false;
            String url = HaConfig.normalizeUrl(ha.optString("url", ""));
            String token = ha.optString("token", "").replaceAll("\\s", "");
            if (url == null || token.isEmpty() || token.length() > 4096) return false;
            if (!HaConfig.setToken(context, token)) return false;
            HaConfig.prefs(context).edit().putString(HaConfig.URL_KEY, url).apply();
            return true;
        } catch (Exception e) {
            return false;
        }
    }

    /** The real vault, for {@link #applyPins}. */
    static Target vaultOf(Context context) {
        return new Target() {
            @Override
            public boolean isKids(String profileKey) {
                return ProfilePairing.isKids(context, profileKey);
            }

            @Override
            public String chosenProfile(String pkg, String profileKey) {
                return ProfilePairing.getChosenProfile(context, pkg, profileKey);
            }

            @Override
            public String status(String owner, String pkg, String appProfile) {
                return PinVault.statusOf(context, owner, pkg, appProfile);
            }

            @Override
            public boolean save(String owner, String pkg, String appProfile, char[] pin) {
                return PinVault.save(context, owner, pkg, appProfile, pin);
            }
        };
    }
}
