package com.leanbitlab.ltvL;

import android.view.accessibility.AccessibilityNodeInfo;

import java.util.Locale;
import java.util.function.Consumer;

/**
 * Netflix: no node tree; in screen-reader mode it speaks (through Hearth voice). The PIN screen: "On the PIN entry
 * screen." ... "In the numeric keyboard. This is a keyboard with 4 rows and 3 columns. The last row contains 0 and
 * Delete keys." then the focused key's label. Keys: 1-9 in a 3x3 grid, then 0 (bottom left) and a wide Delete; focus
 * starts on 1. Nothing is said per digit; after the 4th, "Checking PIN", "Entered 4 of 4 digits.", then "Whoops, wrong
 * PIN. Please try again." or "On the browse screen...". English only: in another language nothing matches and the
 * parent types the PIN.
 */
final class NetflixPinRecipe extends NavigatedKeypadRecipe {
    private static final String KEYBOARD = "this is a keyboard with 4 rows and 3 columns. the last row contains 0 and"
            + " delete keys";
    private static final long PRESS_SETTLE_MS = 400;

    private boolean mPinScreen;
    private boolean mKeyboardKnown;
    private boolean mKeyboardOther;
    private boolean mLockedOut;
    private PinEntryMachine.Outcome mOutcome;

    @Override
    public String packageName() {
        return ProfilePairing.NETFLIX;
    }

    @Override
    public int pinLength() {
        return 4;
    }

    @Override
    public void onSpeech(String text) {
        if (text == null) return;
        String t = text.trim();
        if (t.length() == 1 && Character.isDigit(t.charAt(0))) {
            keyFocused(t);
            return;
        }
        String lower = t.toLowerCase(Locale.ROOT);
        if (lower.equals("delete")) {
            keyFocused(t);
        } else if (lower.contains("on the pin entry screen") || lower.contains("in the pin number keyboard")) {
            mPinScreen = true;
        } else if (lower.contains("in the numeric keyboard")) {
            if (lower.contains(KEYBOARD)) {
                mKeyboardKnown = true;
            } else {
                mKeyboardOther = true;
            }
        } else if (lower.contains("too many")) {
            mLockedOut = true;
        } else if (lower.contains("wrong pin")) {
            mOutcome = PinEntryMachine.Outcome.REJECTED;
        } else if (lower.startsWith("on the browse screen") || lower.startsWith("on the home screen")) {
            mOutcome = PinEntryMachine.Outcome.ACCEPTED;
        }
    }

    @Override
    public PinEntryMachine.Screen recognize(AccessibilityNodeInfo root) {
        if (mLockedOut) return PinEntryMachine.Screen.LOCKED_OUT;
        if (!mPinScreen) return null;
        if (mKeyboardKnown) return PinEntryMachine.Screen.MATCH;
        return mKeyboardOther ? PinEntryMachine.Screen.CHANGED : null;
    }

    @Override
    protected int[] position(char digit) {
        if (digit == '0') return new int[] {3, 0};
        int n = digit - '1';
        return new int[] {n / 3, n % 3};
    }

    @Override
    protected void awaitPress(Consumer<Boolean> confirmed) {
        // Netflix says nothing per digit: the count is checked by its "Entered 4 of 4 digits" and its answer
        handler().postDelayed(() -> confirmed.accept(true), PRESS_SETTLE_MS);
    }

    @Override
    public PinEntryMachine.Outcome outcome(AccessibilityNodeInfo root) {
        if (mLockedOut) return PinEntryMachine.Outcome.LOCKED_OUT;
        return mOutcome;
    }
}
