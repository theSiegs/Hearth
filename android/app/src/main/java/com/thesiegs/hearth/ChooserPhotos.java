package com.thesiegs.hearth;

import java.util.Locale;

/**
 * Which of Google TV's profile chooser tiles may be photographed for a profile photo. Google TV draws its PIN lock
 * (and dims the photo) on a PIN-protected profile's tile whenever another tile has focus, and on the tile being
 * switched to, so only the focused tile is ever photographed, and only one Google TV never locks:
 * - the current account's own tile, while that profile is the one running (settled, no switch under way);
 * - a kids profile's tile while a grown-up's profile is on: going from a grown-up's profile into a kids profile never
 *   asks for a PIN. (Leaving a kids profile can, so while a kid is on, the other tiles are left alone.)
 * The tiles' descriptions say which is which: "&lt;name&gt;, Google kids profile, : select to log in", and
 * "... select to continue with current account" on the current one.
 */
final class ChooserPhotos {
    private ChooserPhotos() {
    }

    /** The chooser tile's description marks a Google kids profile. */
    static boolean isKidsTile(String description) {
        return description != null && description.toLowerCase(Locale.ROOT).contains("kids profile");
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
        if (current == null) return "no tile is marked current";
        if (!currentIsOn) return current + " isn't settled as the running profile";
        if (focused.equals(current)) return null;
        if (!isKidsTile(focusedDesc)) return "it may show a PIN lock (not a kids profile)";
        if (isKidsTile(currentDesc)) return "it may show a PIN lock (a kids profile is on)";
        return null;
    }
}
