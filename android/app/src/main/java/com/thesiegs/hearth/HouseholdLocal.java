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
    private final HouseholdSeal seal;

    HouseholdLocal(Context context, HouseholdSeal seal) {
        this.context = context.getApplicationContext();
        this.seal = seal;
    }

    /**
     * Who a profile is to the household: the id made from its Google account address, or, until Hearth has seen the
     * address (the chooser hasn't shown the profile yet), "n:" and its name. Null for the whole TV's.
     */
    String personIdOf(String key) {
        if (key == null) return HouseholdBridge.SHARED;
        String id = seal.personId(ProfileUsers.emailOf(context, key));
        if (id != null) return id;
        String name = HouseholdEntry.normalize(ProfileUsers.displayName(context, key));
        return name.isEmpty() ? null : "n:" + name;
    }

    @Override
    public Map<String, String> profiles() {
        List<String> keys = ProfilePairing.getHearthProfiles(context);
        String active = LauncherAccessibilityService.getActiveProfileKey(context);
        Map<String, String> byPerson = new LinkedHashMap<>();
        Set<String> seen = new HashSet<>();
        for (String key : keys) {
            if (seen.add(key)) add(byPerson, key);
        }
        if (active != null && seen.add(active)) add(byPerson, active);
        return byPerson;
    }

    /** The first profile with a person's id counts; another with the same address is left out. */
    private void add(Map<String, String> byPerson, String key) {
        if (!ShareData.listable(key, ProfileUsers.getName(context, ProfileUsers.serialOfKey(key)))) return;
        String id = personIdOf(key);
        if (id != null && !id.isEmpty() && !byPerson.containsKey(id)) byPerson.put(id, key);
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
            // A kids profile's way into Google TV isn't shared
            if (kids && isGoogleTvPin(slot.pkg)) continue;
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
        if (key != null && isGoogleTvPin(pkg) && ProfilePairing.isKids(context, key)) return;
        if (digits == null) {
            PinVault.remove(context, key, pkg, appProfile);
            return;
        }
        char[] pin = digits.toCharArray();
        PinVault.save(context, key, pkg, appProfile, pin);
    }

    /** A kids profile's way into Google TV: never shared, nor taken. */
    static boolean isGoogleTvPin(String pkg) {
        return LauncherAccessibilityService.GOOGLE_TV_PACKAGE.equals(pkg);
    }
}
