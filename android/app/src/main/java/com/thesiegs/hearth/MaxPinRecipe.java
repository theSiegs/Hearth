package com.thesiegs.hearth;

import android.os.SystemClock;
import android.view.accessibility.AccessibilityNodeInfo;

import java.util.Locale;
import java.util.function.Consumer;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * HBO Max: no node tree; it describes everything in accessibility announcements. The PIN screen: "Enter Your Profile
 * PIN, <name>'s profile, ..., Numeric Keyboard, 1, Button,  Actions are on the far right, ..."; each focus move:
 * ", Numeric Keyboard, <key>, Button, ..."; each digit that goes in is echoed ("4," or "4"). Keys: 1-9 in a 3x3 grid,
 * 0 alone in the middle of the bottom row, the action keys (delete, clear, show, close) off to the right; focus
 * starts on 1. Checked after the 4th digit: "That PIN doesn't look right." or "H B O Max Home, ...".
 */
final class MaxPinRecipe extends NavigatedKeypadRecipe {
    private static final Pattern FOCUSED_KEY = Pattern.compile("numeric keyboard, ([^,]+), button");
    private static final long PRESS_WAIT_MS = 1_500;

    private boolean mPinScreen;
    private boolean mKeyboard;
    private boolean mLockedOut;
    private PinEntryMachine.Outcome mOutcome;
    private long mEchoAt;

    @Override
    public String packageName() {
        return ProfilePairing.MAX;
    }

    @Override
    public int pinLength() {
        return 4;
    }

    @Override
    public void onSpeech(String text) {
        if (text == null) return;
        String lower = text.toLowerCase(Locale.ROOT).trim();
        if (lower.matches("\\d,?")) {
            mEchoAt = SystemClock.elapsedRealtime();
            return;
        }
        if (lower.contains("enter your profile pin")) mPinScreen = true;
        Matcher m = FOCUSED_KEY.matcher(lower);
        if (m.find()) {
            mKeyboard = true;
            keyFocused(m.group(1).trim());
        }
        if (lower.contains("too many")) {
            mLockedOut = true;
        } else if (lower.contains("look right")) {
            mOutcome = PinEntryMachine.Outcome.REJECTED;
        } else if (lower.startsWith("h b o max home") || lower.startsWith("hbo max home")) {
            mOutcome = PinEntryMachine.Outcome.ACCEPTED;
        }
    }

    @Override
    public PinEntryMachine.Screen recognize(AccessibilityNodeInfo root) {
        if (mLockedOut) return PinEntryMachine.Screen.LOCKED_OUT;
        if (!mPinScreen) return null;
        return mKeyboard ? PinEntryMachine.Screen.MATCH : null;
    }

    @Override
    protected int[] position(char digit) {
        if (digit == '0') return new int[] {3, 1};
        int n = digit - '1';
        return new int[] {n / 3, n % 3};
    }

    @Override
    protected void awaitPress(Consumer<Boolean> confirmed) {
        long since = SystemClock.elapsedRealtime();
        // The 4th digit sends the PIN at once: its answer counts as the echo
        boolean last = mTyped + 1 == pinLength();
        Runnable check = new Runnable() {
            @Override
            public void run() {
                if (mEchoAt >= since || (last && mOutcome != null)) {
                    confirmed.accept(true);
                } else if (SystemClock.elapsedRealtime() - since >= PRESS_WAIT_MS) {
                    confirmed.accept(false);
                } else {
                    handler().postDelayed(this, 50);
                }
            }
        };
        handler().postDelayed(check, 50);
    }

    @Override
    public PinEntryMachine.Outcome outcome(AccessibilityNodeInfo root) {
        if (mLockedOut) return PinEntryMachine.Outcome.LOCKED_OUT;
        return mOutcome;
    }
}
