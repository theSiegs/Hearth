package com.thesiegs.hearth;

import java.util.Locale;

/**
 * Which of Google TV's profile chooser tiles may be photographed for a profile photo. Google TV draws its PIN lock
 * (and dims the photo) on a PIN-protected profile's tile, so only the focused tile is ever photographed, and only:
 * - the current account's own tile, while that profile is the one running (settled, no switch under way);
 * - any other tile whose description doesn't say "Profile locked" (no PIN, so no lock drawn over its photo).
 * The descriptions on the TV (2026-10-11) read "&lt;name&gt;, &lt;email&gt;, Profile locked: select to log in" for a
 * PIN-protected profile, "&lt;name&gt;, &lt;email&gt;, : select to log in" for one without, and "... select to continue
 * with current account" on the current one.
 */
final class ChooserPhotos {
    private ChooserPhotos() {
    }

    /** The chooser tile's description says the profile is PIN-locked (its tile shows the lock). */
    static boolean isLockedTile(String description) {
        return description != null && description.toLowerCase(Locale.ROOT).contains("profile locked");
    }

    /**
     * Why the focused tile can't be photographed now, or null when it can.
     *
     * @param focused         name on the focused tile (null: no profile tile has focus)
     * @param focusedDesc     the focused tile's description
     * @param current         name on the tile marked current account (null: none)
     * @param currentDesc     the current account tile's description
     * @param currentIsOn     the current account's profile is the one running, and no switch is under way
     */
    static String whyNot(String focused, String focusedDesc, String current, String currentDesc,
            boolean currentIsOn) {
        if (focused == null || focused.isEmpty()) return "no profile tile has focus";
        if (focused.equals(current)) return currentIsOn ? null : current + " isn't settled as the running profile";
        if (isLockedTile(focusedDesc)) return "its tile shows a PIN lock";
        return null;
    }
}
