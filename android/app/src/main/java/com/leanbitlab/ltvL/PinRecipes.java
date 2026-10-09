package com.leanbitlab.ltvL;

import java.util.HashMap;
import java.util.Map;
import java.util.function.Supplier;

/**
 * The streaming apps whose profile PINs Hearth can type, one {@link PinRecipe} each. An app without a recipe isn't
 * typed for: its saved PINs wait, and Settings says entry isn't supported for it yet.
 *
 * Each recipe comes from research on the app's real PIN screen (a wrong and then the right PIN typed by a parent with
 * research mode on, digits masked): how the screen is recognised, how the keypad is typed and confirmed, what a wrong
 * PIN and success look like. Not here: Paramount+ (keeps the profile without a PIN at launch) and Hulu, which draws
 * its own screen and only speaks it, through the TTS engine it can see: Google's, never Hearth voice (it declares
 * no queries for TTS engines), and it turns its speech off when it thinks TalkBack is on. See the design doc, §9.
 */
final class PinRecipes {
    private static final Map<String, Supplier<PinRecipe>> RECIPES = new HashMap<>();

    static {
        register(ProfilePairing.DISNEY, DisneyPinRecipe::new);
        register(ProfilePairing.APPLE_TV, AppleTvPinRecipe::new);
        register(ProfilePairing.NETFLIX, NetflixPinRecipe::new);
        register(ProfilePairing.MAX, MaxPinRecipe::new);
    }

    private PinRecipes() {
    }

    static void register(String packageName, Supplier<PinRecipe> recipe) {
        RECIPES.put(packageName, recipe);
    }

    /** A fresh recipe for one entry in the app, or null when Hearth can't type its PINs yet. */
    static PinRecipe forPackage(String packageName) {
        Supplier<PinRecipe> recipe = packageName == null ? null : RECIPES.get(packageName);
        return recipe == null ? null : recipe.get();
    }

    static boolean supports(String packageName) {
        return packageName != null && RECIPES.containsKey(packageName);
    }
}
