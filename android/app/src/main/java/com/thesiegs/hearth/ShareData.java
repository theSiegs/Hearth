package com.thesiegs.hearth;

import android.content.Context;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * The parts of a profile that a copy to another TV (ShareSession) reads and writes on the Java side: which profiles
 * this TV has, and each one's Profile Pairing choices. The layout and look are Flutter's (ShareBundle). What arrives
 * from another TV is checked here again, and an app profile Hearth already has a choice for is left as it is.
 */
final class ShareData {
    private static final int MAX_NAME = 200;

    private ShareData() {
    }

    /** The profiles this TV has told apart so far: {key, name, kids}, the active one included. */
    static List<Map<String, Object>> profiles(Context context) {
        List<String> keys = new ArrayList<>(ProfilePairing.getHearthProfiles(context));
        String active = LauncherAccessibilityService.getActiveProfileKey(context);
        if (active != null && !keys.contains(active)) keys.add(active);
        List<Map<String, Object>> profiles = new ArrayList<>();
        for (String key : keys) {
            if (!listable(key, ProfileUsers.getName(context, ProfileUsers.serialOfKey(key)))) continue;
            Map<String, Object> profile = new HashMap<>();
            profile.put("key", key);
            profile.put("name", ProfileUsers.displayName(context, key));
            profile.put("kids", ProfilePairing.isKids(context, key));
            profiles.add(profile);
        }
        return profiles;
    }

    /**
     * Whether a profile belongs in a copy. Android keeps a spare user ready for the next profile that's added; no one has
     * used it, so Hearth never learned a name for it, and it isn't a profile to send or to receive into. A key that isn't
     * a user's (a name saved before keys), and another account's profile in a user, always count.
     */
    static boolean listable(String key, String learnedName) {
        if (key == null || ProfileUsers.serialOfKey(key) == ProfileUsers.UNKNOWN) return key != null;
        return ProfileUsers.accountOfKey(key) != null || (learnedName != null && !learnedName.isEmpty());
    }

    /** The choices a person made for this profile (an app profile, or always ask): not the automatic matches. */
    static List<Map<String, Object>> pairings(Context context, String profileKey) {
        List<Map<String, Object>> out = new ArrayList<>();
        for (String pkg : ProfilePairing.APPS) {
            String mode = ProfilePairing.getMode(context, pkg, profileKey);
            Map<String, Object> pairing = new HashMap<>();
            pairing.put("pkg", pkg);
            if (ProfilePairing.MODE_PICKER.equals(mode)) {
                pairing.put("mode", "picker");
            } else if (ProfilePairing.MODE_PROFILE.equals(mode)) {
                pairing.put("mode", "profile");
                pairing.put("appProfile", ProfilePairing.getChosenProfile(context, pkg, profileKey));
            } else {
                continue;
            }
            out.add(pairing);
        }
        return out;
    }

    /**
     * Saves another TV's choices for this profile where this TV has none of its own. Returns {applied, kept, skipped}:
     * a choice this TV already has stays (so a PIN saved against it stays valid), and a choice that isn't a pairing
     * for a streaming app Hearth pairs is skipped.
     */
    static Map<String, Object> applyPairings(Context context, String profileKey, List<Map<String, Object>> incoming) {
        int applied = 0;
        int kept = 0;
        int skipped = 0;
        if (incoming != null) {
            for (Map<String, Object> raw : incoming) {
                Map<String, String> pairing = clean(raw);
                if (pairing == null) {
                    skipped++;
                    continue;
                }
                String pkg = pairing.get("pkg");
                if (!shouldApply(ProfilePairing.getMode(context, pkg, profileKey))) {
                    kept++;
                    continue;
                }
                ProfilePairing.setChoice(context, pkg, profileKey, pairing.get("mode"), pairing.get("appProfile"));
                applied++;
            }
        }
        Map<String, Object> result = new HashMap<>();
        result.put("applied", applied);
        result.put("kept", kept);
        result.put("skipped", skipped);
        return result;
    }

    /** Only a profile that has no choice of its own (it goes by name) takes another TV's. */
    static boolean shouldApply(String currentMode) {
        return ProfilePairing.MODE_AUTO.equals(currentMode);
    }

    /** One pairing from another TV, or null if it isn't one Hearth pairs: {pkg, mode, appProfile} as text. */
    static Map<String, String> clean(Map<String, Object> raw) {
        if (raw == null) return null;
        Object pkg = raw.get("pkg");
        Object mode = raw.get("mode");
        if (!(pkg instanceof String) || !ProfilePairing.supports((String) pkg)) return null;
        Map<String, String> out = new HashMap<>();
        out.put("pkg", (String) pkg);
        if ("picker".equals(mode)) {
            out.put("mode", ProfilePairing.MODE_PICKER);
            out.put("appProfile", "");
            return out;
        }
        if (!"profile".equals(mode) || !(raw.get("appProfile") instanceof String)) return null;
        String name = tidy((String) raw.get("appProfile"));
        if (name.isEmpty()) return null;
        out.put("mode", ProfilePairing.MODE_PROFILE);
        out.put("appProfile", name);
        return out;
    }

    /** Text from another TV: no control characters, trimmed, and not longer than a name needs. */
    static String tidy(String text) {
        String cleaned = text.replaceAll("[\\u0000-\\u001f\\u007f]", " ").replaceAll("\\s+", " ").trim();
        return cleaned.length() > MAX_NAME ? cleaned.substring(0, MAX_NAME).trim() : cleaned;
    }
}
