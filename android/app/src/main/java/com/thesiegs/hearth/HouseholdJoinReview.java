package com.thesiegs.hearth;

import org.json.JSONException;
import org.json.JSONObject;

import java.util.HashMap;
import java.util.Iterator;
import java.util.Map;

/**
 * What joining a household would change on this TV's own side, and the copy kept to put it back (docs/household-sync.md,
 * "Before joining"): Profile Pairing choices and saved PINs. Nothing here knows about Android; {@link HouseholdBridge.Local}
 * is this TV's settings, so the rules can be tested alone. The app's side does the same for looks, layouts and pictures.
 */
final class HouseholdJoinReview {
    /** The key of the whole TV's PINs (no profile) in {@link #changes} and the copy. */
    static final String TV = "";

    private HouseholdJoinReview() {
    }

    /**
     * How many of each profile's settings the household's entries would change ({@link HouseholdBridge#apply}'s rule),
     * by the profile's own key ({@link #TV} for the whole TV's PINs): {pairings, pins}. A profile with none isn't in it.
     */
    static Map<String, int[]> changes(HouseholdBridge.Local local, HouseholdLog log) {
        Map<String, int[]> out = new HashMap<>();
        Map<String, String> profiles = local.profiles();
        for (HouseholdEntry entry : log.all()) {
            boolean pairing = HouseholdBridge.PAIRING.equals(entry.kind);
            if (!pairing && !HouseholdBridge.PIN.equals(entry.kind)) continue;
            String key;
            if (!pairing && HouseholdBridge.SHARED.equals(entry.profile)) {
                key = null;
            } else {
                key = profiles.get(entry.profile);
                if (key == null) continue;
            }
            String have = pairing ? local.pairings(key).get(entry.item) : local.pins(key).get(entry.item);
            boolean changes;
            if (entry.deleted) {
                changes = have != null;
            } else {
                boolean valid = pairing ? HouseholdBridge.validPairing(entry.value)
                        : HouseholdBridge.validPin(entry.item, entry.value);
                changes = valid && !entry.value.equals(have);
            }
            if (!changes) continue;
            int[] counts = out.computeIfAbsent(key == null ? TV : key, k -> new int[2]);
            counts[pairing ? 0 : 1]++;
        }
        return out;
    }

    /**
     * This TV's pairings and PINs as they are now, as JSON: {pairings: {key: {pkg: value}}, pins: {key: {item: digits}}},
     * the whole TV's PINs under {@link #TV}. It holds PINs: the caller seals it.
     */
    static String snapshot(HouseholdBridge.Local local) {
        try {
            JSONObject pairings = new JSONObject();
            JSONObject pins = new JSONObject();
            for (String key : local.profiles().values()) {
                pairings.put(key, new JSONObject(local.pairings(key)));
                pins.put(key, new JSONObject(local.pins(key)));
            }
            pins.put(TV, new JSONObject(local.pins(null)));
            return new JSONObject().put("pairings", pairings).put("pins", pins).toString();
        } catch (JSONException e) {
            throw new IllegalStateException(e);
        }
    }

    /**
     * Puts back what {@link #snapshot} kept where it differs from now. What the household added that this TV didn't have
     * stays: taking it away would take it from every TV. Returns how many settings it changed; -1 when the copy
     * doesn't read.
     */
    static int restore(HouseholdBridge.Local local, String snapshot) {
        try {
            JSONObject root = new JSONObject(snapshot);
            int changed = 0;
            JSONObject pairings = root.optJSONObject("pairings");
            for (Iterator<String> keys = pairings == null ? emptyKeys() : pairings.keys(); keys.hasNext(); ) {
                String key = keys.next();
                Map<String, String> was = strings(pairings.optJSONObject(key));
                Map<String, String> now = local.pairings(key);
                for (Map.Entry<String, String> p : was.entrySet()) {
                    if (p.getValue().equals(now.get(p.getKey())) || !HouseholdBridge.validPairing(p.getValue())) continue;
                    local.setPairing(key, p.getKey(), p.getValue());
                    changed++;
                }
            }
            JSONObject pins = root.optJSONObject("pins");
            for (Iterator<String> keys = pins == null ? emptyKeys() : pins.keys(); keys.hasNext(); ) {
                String name = keys.next();
                String key = TV.equals(name) ? null : name;
                Map<String, String> was = strings(pins.optJSONObject(name));
                Map<String, String> now = local.pins(key);
                for (Map.Entry<String, String> p : was.entrySet()) {
                    if (p.getValue().equals(now.get(p.getKey())) || !HouseholdBridge.validPin(p.getKey(), p.getValue())) {
                        continue;
                    }
                    local.setPin(key, p.getKey(), p.getValue());
                    changed++;
                }
            }
            return changed;
        } catch (JSONException e) {
            return -1;
        }
    }

    private static Iterator<String> emptyKeys() {
        return new JSONObject().keys();
    }

    private static Map<String, String> strings(JSONObject o) {
        Map<String, String> out = new HashMap<>();
        if (o == null) return out;
        for (Iterator<String> it = o.keys(); it.hasNext(); ) {
            String k = it.next();
            String v = o.optString(k, null);
            if (v != null) out.put(k, v);
        }
        return out;
    }
}
