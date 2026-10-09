package com.leanbitlab.ltvL;

import android.accessibilityservice.AccessibilityService;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.view.accessibility.AccessibilityNodeInfo;

import java.util.List;
import java.util.function.Consumer;

/**
 * Disney+: a native keypad (digit keys 0-9 under id/pinCodeKeyboard, each clickable), the typed digits held in
 * id/pinCodeEditText (only their count is read), checked by the app after the 4th digit. A wrong PIN shows
 * id/pinCodeErrorTextView and clears the field; the right one leaves the PIN screen for the home screen.
 */
final class DisneyPinRecipe implements PinRecipe {
    private static final String ID = ProfilePairing.DISNEY + ":id/";
    private static final long CONFIRM_POLL_MS = 100;
    private static final long CONFIRM_WAIT_MS = 1_500;

    private final Handler mHandler = new Handler(Looper.getMainLooper());

    @Override
    public String packageName() {
        return ProfilePairing.DISNEY;
    }

    @Override
    public int pinLength() {
        return 4;
    }

    private static AccessibilityNodeInfo find(AccessibilityNodeInfo root, String id) {
        List<AccessibilityNodeInfo> nodes = root.findAccessibilityNodeInfosByViewId(ID + id);
        return nodes == null || nodes.isEmpty() ? null : nodes.get(0);
    }

    /** The clickable key for each digit, or null unless all ten are there. */
    private static AccessibilityNodeInfo[] keys(AccessibilityNodeInfo root) {
        List<AccessibilityNodeInfo> labels = root.findAccessibilityNodeInfosByViewId(ID + "digitKey");
        if (labels == null) return null;
        AccessibilityNodeInfo[] keys = new AccessibilityNodeInfo[10];
        for (AccessibilityNodeInfo label : labels) {
            CharSequence text = label.getText();
            if (text == null || text.length() != 1 || !Character.isDigit(text.charAt(0))) continue;
            AccessibilityNodeInfo key = label;
            while (key != null && !key.isClickable()) key = key.getParent();
            if (key == null) return null;
            keys[text.charAt(0) - '0'] = key;
        }
        for (AccessibilityNodeInfo key : keys) {
            if (key == null) return null;
        }
        return keys;
    }

    private static boolean onPinScreen(AccessibilityNodeInfo root) {
        return find(root, "enterPinRootView") != null;
    }

    private static int typedCount(AccessibilityNodeInfo root) {
        AccessibilityNodeInfo field = find(root, "pinCodeEditText");
        CharSequence text = field != null ? field.getText() : null;
        return text == null ? 0 : text.length();
    }

    private static boolean errorShown(AccessibilityNodeInfo root) {
        AccessibilityNodeInfo error = find(root, "pinCodeErrorTextView");
        return error != null && error.isVisibleToUser() && error.getText() != null && error.getText().length() > 0;
    }

    @Override
    public PinEntryMachine.Screen recognize(AccessibilityNodeInfo root) {
        if (!onPinScreen(root)) return null;
        boolean known = find(root, "pinCodeKeyboard") != null && find(root, "pinCodeEditText") != null
                && keys(root) != null;
        return known ? PinEntryMachine.Screen.MATCH : PinEntryMachine.Screen.CHANGED;
    }

    @Override
    public void type(AccessibilityService service, AccessibilityNodeInfo root, char digit,
            Consumer<Boolean> confirmed) {
        AccessibilityNodeInfo[] keys = keys(root);
        if (keys == null || digit < '0' || digit > '9') {
            confirmed.accept(false);
            return;
        }
        int before = typedCount(root);
        if (!keys[digit - '0'].performAction(AccessibilityNodeInfo.ACTION_CLICK)) {
            confirmed.accept(false);
            return;
        }
        long until = SystemClock.elapsedRealtime() + CONFIRM_WAIT_MS;
        Runnable check = new Runnable() {
            @Override
            public void run() {
                AccessibilityNodeInfo now = service.getRootInActiveWindow();
                // One more digit; or, after the last one, the app already answered (the field cleared on an error,
                // or the PIN screen is gone)
                boolean in = now != null && (typedCount(now) == before + 1
                        || (before + 1 == pinLength() && (!onPinScreen(now) || errorShown(now))));
                if (in) {
                    confirmed.accept(true);
                } else if (SystemClock.elapsedRealtime() >= until) {
                    confirmed.accept(false);
                } else {
                    mHandler.postDelayed(this, CONFIRM_POLL_MS);
                }
            }
        };
        mHandler.postDelayed(check, CONFIRM_POLL_MS);
    }

    @Override
    public PinEntryMachine.Outcome outcome(AccessibilityNodeInfo root) {
        if (!onPinScreen(root)) return PinEntryMachine.Outcome.ACCEPTED;
        if (errorShown(root)) return PinEntryMachine.Outcome.REJECTED;
        return null;
    }
}
