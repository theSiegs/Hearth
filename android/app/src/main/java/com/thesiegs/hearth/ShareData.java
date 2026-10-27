package com.thesiegs.hearth;

/**
 * Small rules about profiles and names shared by household sync, joining and Home Assistant's setup (they began with
 * the copy of profiles between TVs, which household sync replaced): which profiles count, and text from another TV.
 */
final class ShareData {
    private static final int MAX_NAME = 200;

    private ShareData() {
    }

    /**
     * Whether a profile counts. Android keeps a spare user ready for the next profile that's added; no one has used it,
     * so Hearth never learned a name for it, and it isn't a profile to sync. A key that isn't a user's (a name saved
     * before keys), and another account's profile in a user, always count.
     */
    static boolean listable(String key, String learnedName) {
        if (key == null || ProfileUsers.serialOfKey(key) == ProfileUsers.UNKNOWN) return key != null;
        return ProfileUsers.accountOfKey(key) != null || (learnedName != null && !learnedName.isEmpty());
    }

    /** Text from another TV: no control characters, trimmed, and not longer than a name needs. */
    static String tidy(String text) {
        String cleaned = text.replaceAll("[\\u0000-\\u001f\\u007f]", " ").replaceAll("\\s+", " ").trim();
        return cleaned.length() > MAX_NAME ? cleaned.substring(0, MAX_NAME).trim() : cleaned;
    }
}
