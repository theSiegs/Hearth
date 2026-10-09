package com.leanbitlab.ltvL;

import android.accessibilityservice.AccessibilityService;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.view.accessibility.AccessibilityNodeInfo;

import java.util.function.Consumer;

/**
 * A keypad that can't be pressed through its nodes: Hearth moves the app's focus with D-pad actions and reads the
 * focused key's label from what the app says or reports, one move at a time, and presses OK only once the focused
 * key is the digit (Netflix, HBO Max, Apple TV). A move the app doesn't answer with a key label, or a label off the
 * known layout, stops the entry before any OK.
 */
abstract class NavigatedKeypadRecipe implements PinRecipe {
    private static final long MOVE_WAIT_MS = 1_500;
    private static final long POLL_MS = 50;
    private static final int MAX_MOVES = 10;

    protected final Handler mHandler = new Handler(Looper.getMainLooper());

    /** The focused key's label ("0"-"9", or something else for another key) and when it was heard. */
    private String mFocused;
    private long mFocusedAt;

    /** Digits confirmed so far. */
    protected int mTyped;

    /** The key's {row, column} on the keypad, for "0"-"9". */
    protected abstract int[] position(char digit);

    /** After OK on a key: calls {@code confirmed} with whether the app shows the digit went in. */
    protected abstract void awaitPress(Consumer<Boolean> confirmed);

    /** The app reported focus on the key labelled {@code label}. */
    protected final void keyFocused(String label) {
        mFocused = label;
        mFocusedAt = SystemClock.elapsedRealtime();
    }

    @Override
    public long stepTimeoutMs() {
        return MAX_MOVES * MOVE_WAIT_MS;
    }

    @Override
    public void type(AccessibilityService service, AccessibilityNodeInfo root, char digit,
            Consumer<Boolean> confirmed) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU || digit < '0' || digit > '9') {
            confirmed.accept(false);
            return;
        }
        step(service, digit, 0, confirmed);
    }

    private void step(AccessibilityService service, char digit, int moves, Consumer<Boolean> confirmed) {
        String focused = mFocused;
        if (focused == null || focused.length() != 1 || !Character.isDigit(focused.charAt(0))) {
            confirmed.accept(false);
            return;
        }
        if (focused.charAt(0) == digit) {
            service.performGlobalAction(AccessibilityService.GLOBAL_ACTION_DPAD_CENTER);
            awaitPress(ok -> {
                if (ok) mTyped++;
                confirmed.accept(ok);
            });
            return;
        }
        if (moves >= MAX_MOVES) {
            confirmed.accept(false);
            return;
        }
        int[] from = position(focused.charAt(0));
        int[] to = position(digit);
        int action;
        boolean lastRow = to[0] > from[0] && to[0] == lastRow();
        // Into the last row (0's row, with gaps or wide keys beside it): line up the column first, then down
        if ((lastRow || from[0] == to[0]) && from[1] != to[1]) {
            action = to[1] > from[1]
                    ? AccessibilityService.GLOBAL_ACTION_DPAD_RIGHT : AccessibilityService.GLOBAL_ACTION_DPAD_LEFT;
        } else {
            action = to[0] > from[0]
                    ? AccessibilityService.GLOBAL_ACTION_DPAD_DOWN : AccessibilityService.GLOBAL_ACTION_DPAD_UP;
        }
        long movedAt = SystemClock.elapsedRealtime();
        mFocused = null;
        service.performGlobalAction(action);
        Runnable wait = new Runnable() {
            @Override
            public void run() {
                if (mFocused != null && mFocusedAt >= movedAt) {
                    step(service, digit, moves + 1, confirmed);
                } else if (SystemClock.elapsedRealtime() - movedAt >= MOVE_WAIT_MS) {
                    confirmed.accept(false);
                } else {
                    mHandler.postDelayed(this, POLL_MS);
                }
            }
        };
        mHandler.postDelayed(wait, POLL_MS);
    }

    /** The keypad's last row, where 0 is. */
    protected int lastRow() {
        return position('0')[0];
    }
}
