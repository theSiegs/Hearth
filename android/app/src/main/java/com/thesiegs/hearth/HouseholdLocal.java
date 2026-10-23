package com.thesiegs.hearth;

import android.content.Context;
import android.util.Log;

import org.json.JSONObject;

import java.util.Arrays;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

/** This TV's own settings as the household sync reads and changes them: Profile Pairing choices and saved PINs. */
final class HouseholdLocal implements HouseholdBridge.Local {
    private static final String TAG = "HearthHousehold";
    private final Context context;

    HouseholdLocal(Context context) {
        this.context = context.getApplicationContext();
    }

    /** The key of the profile that has {@code name} on this TV (normalized), or null when none or two do. */
    static String keyOf(Context context, String name) {
        return new HouseholdLocal(context).profiles().get(HouseholdEntry.normalize(name));
    }

    /** The household's name for a profile key on this TV: its normalized display name. */
    static String nameOf(Context context, String key) {
        return key == null ? HouseholdBridge.SHARED : HouseholdEntry.normalize(ProfileUsers.displayName(context, key));
    }

    @Override
    public Map<String, String> profiles() {
        List<String> keys = ProfilePairing.getHearthProfiles(context);
        String active = LauncherAccessibilityService.getActiveProfileKey(context);
        Map<String, String> byName = new LinkedHashMap<>();
        Set<String> clashes = new HashSet<>();
        Set<String> seen = new HashSet<>();
        for (String key : keys) {
            if (seen.add(key)) add(byName, clashes, key);
        }
        if (active != null && seen.add(active)) add(byName, clashes, active);
        for (String name : clashes) byName.remove(name);
        return byName;
    }

    private void add(Map<String, String> byName, Set<String> clashes, String key) {
        if (!ShareData.listable(key, ProfileUsers.getName(context, ProfileUsers.serialOfKey(key)))) return;
        String name = nameOf(context, key);
        if (name.isEmpty()) return;
        if (byName.containsKey(name)) clashes.add(name);
        else byName.put(name, key);
    }

    @Override
    public Map<String, String> pairings(String key) {
        Map<String, String> out = new HashMap<>();
        for (String pkg : ProfilePairing.APPS) {
            String mode = ProfilePairing.getMode(context, pkg, key);
            if (ProfilePairing.MODE_PICKER.equals(mode)) {
                out.put(pkg, HouseholdBridge.pairingValue(mode, null));
            } else if (ProfilePairing.MODE_PROFILE.equals(mode)) {
                String chosen = ProfilePairing.getChosenProfile(context, pkg, key);
                if (chosen != null && !chosen.isEmpty()) out.put(pkg, HouseholdBridge.pairingValue(mode, chosen));
            }
        }
        return out;
    }

    @Override
    public void setPairing(String key, String pkg, String value) {
        if (!ProfilePairing.supports(pkg)) return;
        try {
            if (value == null) {
                ProfilePairing.setChoice(context, pkg, key, ProfilePairing.MODE_AUTO, null);
                return;
            }
            JSONObject o = new JSONObject(value);
            ProfilePairing.setChoice(context, pkg, key, o.getString("mode"), o.optString("appProfile", null));
        } catch (Exception e) {
            Log.w(TAG, "A pairing from another TV wasn't applied: " + e.getClass().getSimpleName());
        }
    }

    @Override
    public Map<String, String> pins(String key) {
        Map<String, String> out = new HashMap<>();
        boolean kids = key != null && ProfilePairing.isKids(context, key);
        for (PinVault.Slot slot : PinVault.slots(context, key)) {
            // A kids profile's way into Google TV isn't shared (as in a copy)
            if (kids && ShareSecrets.isGoogleTvPin(slot.pkg)) continue;
            char[] pin = PinVault.open(context, slot.owner, slot.pkg, slot.appProfile);
            if (pin == null) continue;
            try {
                out.put(slot.pkg + "|" + slot.appProfile, new String(pin));
            } finally {
                Arrays.fill(pin, '\0');
            }
        }
        return out;
    }

    @Override
    public void setPin(String key, String item, String digits) {
        int bar = item.indexOf('|');
        if (bar <= 0) return;
        String pkg = item.substring(0, bar);
        String appProfile = item.substring(bar + 1);
        if (key != null && ShareSecrets.isGoogleTvPin(pkg) && ProfilePairing.isKids(context, key)) return;
        if (digits == null) {
            PinVault.remove(context, key, pkg, appProfile);
            return;
        }
        char[] pin = digits.toCharArray();
        PinVault.save(context, key, pkg, appProfile, pin);
    }
}
