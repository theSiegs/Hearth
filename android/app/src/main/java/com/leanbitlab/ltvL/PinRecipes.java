package com.leanbitlab.ltvL;

import java.util.HashMap;
import java.util.Map;

/**
 * The streaming apps whose profile PINs Hearth can type, one {@link PinRecipe} each. An app without a recipe isn't
 * typed for: its saved PINs wait, and Settings says entry isn't supported for it yet.
 *
 * Each recipe is added after research on the app's real PIN screen with a test profile and a throwaway PIN (never the
 * family's profiles): how the screen is recognised, how the keypad is typed and confirmed, what a wrong PIN and a
 * lockout look like. None is researched yet.
 */
final class PinRecipes {
    private static final Map<String, PinRecipe> RECIPES = new HashMap<>();

    private PinRecipes() {
    }

    static void register(PinRecipe recipe) {
        RECIPES.put(recipe.packageName(), recipe);
    }

    /** The app's recipe, or null when Hearth can't type its PINs yet. */
    static PinRecipe forPackage(String packageName) {
        return packageName == null ? null : RECIPES.get(packageName);
    }

    static boolean supports(String packageName) {
        return forPackage(packageName) != null;
    }
}
