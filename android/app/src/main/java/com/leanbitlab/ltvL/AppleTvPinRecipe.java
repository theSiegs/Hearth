package com.leanbitlab.ltvL;

import android.os.SystemClock;
import android.view.accessibility.AccessibilityEvent;
import android.view.accessibility.AccessibilityNodeInfo;

import java.util.ArrayDeque;
import java.util.Deque;
import java.util.Locale;
import java.util.function.Consumer;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Apple TV: one row of keys 1 2 3 4 5 6 7 8 9 0 Delete, each a node whose description is its label (the first one's
 * starts with the prompt: "Enter 4-Digit Code, ..., Keyboard, 1"), and "Use Password Instead". Focus moves are
 * reported as accessibility focus on the key; each digit that goes in is announced "N of 4 values entered". A wrong
 * PIN leaves the PIN screen up and starts the count again; the right one leaves for "Loading" and the home screen.
 */
final class AppleTvPinRecipe extends NavigatedKeypadRecipe {
    private static final Pattern ENTERED = Pattern.compile("(\\d+) of (\\d+) values entered");
    private static final long PRESS_WAIT_MS = 1_500;
    /** After the last digit, a PIN screen still up this long means the PIN wasn't taken. */
    private static final long REJECTED_AFTER_MS = 3_000;

    /** The counts Apple announced, newest last. */
    private final Deque<Integer> mEntered = new ArrayDeque<>();
    private long mLastDigitAt;

    @Override
    public String packageName() {
        return ProfilePairing.APPLE_TV;
    }

    @Override
    public int pinLength() {
        return 4;
    }

    /** "…, Keyboard, 1" or "1": the label after the last comma. */
    static String label(CharSequence description) {
        if (description == null) return null;
        String d = description.toString();
        int comma = d.lastIndexOf(',');
        return (comma >= 0 ? d.substring(comma + 1) : d).trim();
    }

    @Override
    public void onEvent(AccessibilityEvent event) {
        if (event.getEventType() != AccessibilityEvent.TYPE_VIEW_ACCESSIBILITY_FOCUSED
                && event.getEventType() != AccessibilityEvent.TYPE_VIEW_FOCUSED) {
            return;
        }
        AccessibilityNodeInfo source = event.getSource();
        String label = source != null ? label(source.getContentDescription()) : null;
        if (label != null && !label.isEmpty()) keyFocused(label);
    }

    @Override
    public void onSpeech(String text) {
        if (text == null) return;
        Matcher m = ENTERED.matcher(text.toLowerCase(Locale.ROOT));
        if (m.find()) mEntered.addLast(Integer.parseInt(m.group(1)));
    }

    /** Each digit key, or null unless all ten and Delete are there. */
    private static AccessibilityNodeInfo[] keys(AccessibilityNodeInfo root, boolean[] partial) {
        AccessibilityNodeInfo[] keys = new AccessibilityNodeInfo[11];
        collect(root, keys, 0);
        int found = 0;
        for (AccessibilityNodeInfo key : keys) {
            if (key != null) found++;
        }
        if (partial != null) partial[0] = found > 0 && found < keys.length;
        return found == keys.length ? keys : null;
    }

    private static void collect(AccessibilityNodeInfo node, AccessibilityNodeInfo[] keys, int depth) {
        if (node == null || depth > 30) return;
        if (node.isClickable()) {
            String label = label(node.getContentDescription());
            if (label != null && label.length() == 1 && Character.isDigit(label.charAt(0))) {
                keys[label.charAt(0) - '0'] = node;
            } else if ("Delete".equals(label)) {
                keys[10] = node;
            }
        }
        for (int i = 0; i < node.getChildCount(); i++) collect(node.getChild(i), keys, depth + 1);
    }

    @Override
    public PinEntryMachine.Screen recognize(AccessibilityNodeInfo root) {
        boolean[] partial = new boolean[1];
        if (keys(root, partial) != null) return PinEntryMachine.Screen.MATCH;
        return partial[0] ? PinEntryMachine.Screen.CHANGED : null;
    }

    @Override
    protected int[] position(char digit) {
        return new int[] {0, digit == '0' ? 9 : digit - '1'};
    }

    @Override
    protected void awaitPress(Consumer<Boolean> confirmed) {
        int expected = mTyped + 1;
        long since = SystemClock.elapsedRealtime();
        Runnable check = new Runnable() {
            @Override
            public void run() {
                Integer last = mEntered.peekLast();
                if (last != null && last == expected) {
                    mLastDigitAt = SystemClock.elapsedRealtime();
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
        if (keys(root, null) == null) return PinEntryMachine.Outcome.ACCEPTED;
        if (SystemClock.elapsedRealtime() - mLastDigitAt >= REJECTED_AFTER_MS) return PinEntryMachine.Outcome.REJECTED;
        return null;
    }
}
