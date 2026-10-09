package com.leanbitlab.ltvL;

import android.accessibilityservice.AccessibilityService;
import android.view.accessibility.AccessibilityNodeInfo;

import java.util.function.Consumer;

/**
 * How Hearth types the profile PIN in one streaming app (see docs/design/streaming-pin-entry.md): recognising the
 * app's PIN screen and noticing when it changed, typing a digit and confirming it went in, and telling whether the
 * app took the PIN. Recipes come from research on the app's real PIN screen (a test profile, never the family's), one
 * per app, in {@link PinRecipes}. They never log a digit or the focused key.
 */
interface PinRecipe {
    /** The app the recipe is for. */
    String packageName();

    /** The PIN's length in this app. */
    int pinLength();

    /**
     * What this window is: null when it isn't the app's PIN screen at all (keep waiting); MATCH when it's the PIN
     * screen laid out the way the recipe knows (its structure, never anything typed); CHANGED when it's a PIN screen
     * the recipe doesn't recognise; LOCKED_OUT when the app says the profile is locked.
     */
    PinEntryMachine.Screen recognize(AccessibilityNodeInfo root);

    /**
     * Types one digit on the PIN screen, then calls {@code confirmed} on the main thread with whether the app shows
     * it went in (a dot more, an announcement). Must not press OK on a key it hasn't confirmed is {@code digit}.
     */
    void type(AccessibilityService service, AccessibilityNodeInfo root, char digit, Consumer<Boolean> confirmed);

    /** After the last digit: null while the app is still deciding, else what it did with the PIN. */
    PinEntryMachine.Outcome outcome(AccessibilityNodeInfo root);
}
