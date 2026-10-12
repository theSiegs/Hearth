package com.thesiegs.hearth;

import android.accessibilityservice.AccessibilityService;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.view.accessibility.AccessibilityNodeInfo;

import java.nio.CharBuffer;
import java.util.Arrays;
import java.util.List;
import java.util.function.Consumer;

/**
 * Paramount+'s content PIN dialog (see {@link ContentPin}): the field id/pinEdit shows a dot per digit, and the keypad
 * id/tvPinKeyboard holds a key per digit with the digit as its text. Each digit is typed by clicking its key; only if
 * a key won't take the click is the field set to the digits so far instead. Nothing else on the dialog is pressed.
 * The 4th digit sends the PIN: the dialog goes and the title starts; still up a moment later, it was rejected.
 */
final class ParamountContentPinRecipe implements PinRecipe {
    private static final String ID = ContentPin.PACKAGE + ":id/";
    private static final long CONFIRM_POLL_MS = 100;
    private static final long CONFIRM_WAIT_MS = 1_500;

    private final Handler mHandler = new Handler(Looper.getMainLooper());
    /** The digits typed so far, for the set-text fallback only; wiped on close. */
    private final char[] mDigits = new char[ContentPin.LENGTH];
    private int mTyped;
    private long mLastDigitAt;

    @Override
    public String packageName() {
        return ContentPin.PACKAGE;
    }

    @Override
    public int pinLength() {
        return ContentPin.LENGTH;
    }

    private static AccessibilityNodeInfo find(AccessibilityNodeInfo root, String id) {
        List<AccessibilityNodeInfo> nodes = root.findAccessibilityNodeInfosByViewId(ID + id);
        return nodes == null || nodes.isEmpty() ? null : nodes.get(0);
    }

    private static AccessibilityNodeInfo field(AccessibilityNodeInfo root) {
        return find(root, "pinEdit");
    }

    private static AccessibilityNodeInfo keyboard(AccessibilityNodeInfo root) {
        return find(root, "tvPinKeyboard");
    }

    /** The keypad's key for each digit (the digit's node, or its clickable parent inside the keypad). */
    private static AccessibilityNodeInfo[] keys(AccessibilityNodeInfo keyboard) {
        AccessibilityNodeInfo[] keys = new AccessibilityNodeInfo[10];
        if (keyboard != null) collectKeys(keyboard, keyboard, keys, 0);
        return keys;
    }

    private static void collectKeys(AccessibilityNodeInfo node, AccessibilityNodeInfo keyboard,
            AccessibilityNodeInfo[] keys, int depth) {
        if (node == null || depth > 6) return;
        CharSequence text = node.getText();
        if (node != keyboard && text != null && text.length() == 1 && Character.isDigit(text.charAt(0))) {
            int d = text.charAt(0) - '0';
            if (d >= 0 && d <= 9 && keys[d] == null) {
                AccessibilityNodeInfo key = node;
                for (int i = 0; key != null && !key.isClickable() && i < 3 && !key.equals(keyboard); i++) {
                    key = key.getParent();
                }
                keys[d] = key != null && key.isClickable() ? key : node;
            }
            return;
        }
        for (int i = 0; i < node.getChildCount(); i++) {
            collectKeys(node.getChild(i), keyboard, keys, depth + 1);
        }
    }

    private static int count(AccessibilityNodeInfo[] keys) {
        int n = 0;
        for (AccessibilityNodeInfo key : keys) {
            if (key != null) n++;
        }
        return n;
    }

    private static int typedCount(AccessibilityNodeInfo root) {
        AccessibilityNodeInfo field = field(root);
        if (field == null) return 0;
        return ContentPin.typedCount(field.getText(), field.isShowingHintText());
    }

    private static boolean dialogUp(AccessibilityNodeInfo root) {
        return field(root) != null || keyboard(root) != null;
    }

    @Override
    public PinEntryMachine.Screen recognize(AccessibilityNodeInfo root) {
        AccessibilityNodeInfo keyboard = keyboard(root);
        List<AccessibilityNodeInfo> text = root.findAccessibilityNodeInfosByText("Enter your PIN to watch");
        return ContentPin.screen(field(root) != null, keyboard != null, count(keys(keyboard)),
                text != null && !text.isEmpty());
    }

    @Override
    public void type(AccessibilityService service, AccessibilityNodeInfo root, char digit,
            Consumer<Boolean> confirmed) {
        AccessibilityNodeInfo[] keys = keys(keyboard(root));
        if (digit < '0' || digit > '9' || mTyped >= mDigits.length || keys[digit - '0'] == null) {
            confirmed.accept(false);
            return;
        }
        int before = typedCount(root);
        mDigits[mTyped] = digit;
        boolean last = mTyped + 1 == pinLength();
        boolean sent = keys[digit - '0'].performAction(AccessibilityNodeInfo.ACTION_CLICK);
        if (!sent) sent = setText(root, mTyped + 1);
        if (!sent) {
            confirmed.accept(false);
            return;
        }
        long until = SystemClock.elapsedRealtime() + CONFIRM_WAIT_MS;
        Runnable check = new Runnable() {
            @Override
            public void run() {
                AccessibilityNodeInfo now = service.getRootInActiveWindow();
                boolean ours = now != null && now.getPackageName() != null
                        && ContentPin.PACKAGE.contentEquals(now.getPackageName());
                int count = ours ? typedCount(now) : -1;
                // One more digit; or, after the last one, the app already answered (the dialog went, or it cleared)
                boolean in = ours && (count == before + 1 || (last && (!dialogUp(now) || count < before)));
                if (in) {
                    mTyped++;
                    if (last) mLastDigitAt = SystemClock.elapsedRealtime();
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

    /** The fallback: the field set to the first {@code length} digits at once. */
    private boolean setText(AccessibilityNodeInfo root, int length) {
        AccessibilityNodeInfo field = field(root);
        if (field == null) return false;
        char[] digits = Arrays.copyOf(mDigits, length);
        try {
            Bundle args = new Bundle();
            args.putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, CharBuffer.wrap(digits));
            return field.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args);
        } finally {
            Arrays.fill(digits, '\0');
        }
    }

    @Override
    public PinEntryMachine.Outcome outcome(AccessibilityNodeInfo root) {
        if (mLastDigitAt == 0) return null;
        return ContentPin.outcome(dialogUp(root), SystemClock.elapsedRealtime() - mLastDigitAt);
    }

    @Override
    public void close() {
        Arrays.fill(mDigits, '\0');
        mHandler.removeCallbacksAndMessages(null);
    }
}
