package com.thesiegs.hearth;

import android.content.Context;
import android.view.accessibility.AccessibilityNodeInfo;

/**
 * Google TV's own PIN screen for a locked profile ("Verify your identity", launcherx's ReauthActivity, seen on the TV
 * 2026-10-13): a 3x3 keypad of digit keys with 0 under it and a delete key, each a clickable TextView labelled with its
 * digit (ids obfuscated, so only labels and structure are used), and four dots that don't say how many are filled. So
 * a digit counts as in once its key took the click; after the fourth the screen closes when Google takes the PIN, and
 * staying up means it didn't. Typed only after the profile's owner allowed it on their phone (PhoneApproval).
 *
 * The recipe itself is data, slot "google-tv" in PinRecipes; this holds what the rest of Hearth needs of it.
 */
final class GooglePinRecipe {
    static final String VAULT_NAME = "#google-tv-pin";

    private GooglePinRecipe() {
    }

    /** Whether Google TV's PIN keypad, as the recipe knows it, is in this window. */
    static boolean keypadUp(Context context, AccessibilityNodeInfo root) {
        if (root == null) return false;
        PinRecipeSpec spec = PinRecipes.spec(context, PinRecipeSpec.SLOT_GOOGLE_TV,
                LauncherAccessibilityService.GOOGLE_TV_PACKAGE);
        return spec != null && new DataPinRecipe(spec).recognize(root) == PinEntryMachine.Screen.MATCH;
    }
}
