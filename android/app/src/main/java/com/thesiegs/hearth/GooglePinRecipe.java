package com.thesiegs.hearth;

import android.accessibilityservice.AccessibilityService;
import android.view.accessibility.AccessibilityNodeInfo;

import java.util.ArrayList;
import java.util.List;
import java.util.function.Consumer;

/**
 * Google TV's own PIN screen for a locked profile ("Verify your identity", launcherx's ReauthActivity, seen on the TV
 * 2026-10-13): a 3x3 keypad of digit keys with 0 under it and a delete key, each a clickable TextView labelled with its
 * digit (ids obfuscated, so only labels and structure are used), and four dots that don't say how many are filled. So
 * a digit counts as in once its key took the click; after the fourth the screen closes when Google takes the PIN, and
 * staying up means it didn't. Typed only after the profile's owner allowed it on their phone (PhoneApproval).
 */
final class GooglePinRecipe implements PinRecipe {
    static final String VAULT_NAME = "#google-tv-pin";
    /** After the last digit, the keypad still up this long means Google didn't take the PIN. */
    private static final long REJECTED_AFTER_MS = 2_500;

    private int mTyped;
    private long mLastDigitAt;

    @Override
    public String packageName() {
        return LauncherAccessibilityService.GOOGLE_TV_PACKAGE;
    }

    @Override
    public int pinLength() {
        return 4;
    }

    @Override
    public long outcomeTimeoutMs() {
        return 4_000;
    }

    /** The ten digit keys, by digit, or null unless each is there exactly once and clickable. */
    static AccessibilityNodeInfo[] keys(AccessibilityNodeInfo root) {
        List<AccessibilityNodeInfo> all = new ArrayList<>();
        collect(root, all, 0);
        AccessibilityNodeInfo[] keys = new AccessibilityNodeInfo[10];
        for (AccessibilityNodeInfo node : all) {
            CharSequence text = node.getText();
            if (text == null || text.length() != 1 || !Character.isDigit(text.charAt(0))) continue;
            int digit = text.charAt(0) - '0';
            if (keys[digit] != null || !node.isClickable()) return null;
            keys[digit] = node;
        }
        for (AccessibilityNodeInfo key : keys) {
            if (key == null) return null;
        }
        return keys;
    }

    private static void collect(AccessibilityNodeInfo node, List<AccessibilityNodeInfo> out, int depth) {
        if (node == null || depth > 25) return;
        if (node.isVisibleToUser() && node.getText() != null) out.add(node);
        for (int i = 0; i < node.getChildCount(); i++) collect(node.getChild(i), out, depth + 1);
    }

    private static boolean isGoogleTv(AccessibilityNodeInfo root) {
        return root != null && LauncherAccessibilityService.GOOGLE_TV_PACKAGE.contentEquals(root.getPackageName());
    }

    @Override
    public PinEntryMachine.Screen recognize(AccessibilityNodeInfo root) {
        if (!isGoogleTv(root)) return null;
        return keys(root) != null ? PinEntryMachine.Screen.MATCH : null;
    }

    @Override
    public void type(AccessibilityService service, AccessibilityNodeInfo root, char digit, Consumer<Boolean> confirmed) {
        AccessibilityNodeInfo[] keys = isGoogleTv(root) ? keys(root) : null;
        boolean ok = keys != null && digit >= '0' && digit <= '9'
                && keys[digit - '0'].performAction(AccessibilityNodeInfo.ACTION_CLICK);
        if (ok) {
            mTyped++;
            mLastDigitAt = android.os.SystemClock.elapsedRealtime();
        }
        confirmed.accept(ok);
    }

    @Override
    public PinEntryMachine.Outcome outcome(AccessibilityNodeInfo root) {
        // The keypad gone: Google took the PIN. Still there a moment after the last digit: it didn't
        if (!isGoogleTv(root) || keys(root) == null) return PinEntryMachine.Outcome.ACCEPTED;
        boolean waited = mTyped >= pinLength()
                && android.os.SystemClock.elapsedRealtime() - mLastDigitAt >= REJECTED_AFTER_MS;
        return waited ? PinEntryMachine.Outcome.REJECTED : null;
    }
}
