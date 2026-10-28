package com.thesiegs.hearth;

import android.accessibilityservice.AccessibilityService;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.view.accessibility.AccessibilityNodeInfo;

import java.nio.CharBuffer;
import java.util.ArrayList;
import java.util.List;

/**
 * One node of a streaming app's window as a PIN recipe ({@link DataPinRecipe}) sees it: only what recipes read and the
 * two things they may do to a node (click it, set a PIN field's text). The TV's nodes are wrapped by {@link Android};
 * unit tests build trees of their own, so every recipe is tested without a TV.
 */
interface PinNode {
    CharSequence text();

    CharSequence description();

    boolean isClickable();

    boolean isVisible();

    boolean isShowingHint();

    CharSequence packageName();

    PinNode parent();

    int childCount();

    PinNode child(int index);

    /** The nodes below with this full view id ("package:id/name"). */
    List<PinNode> findById(String fullId);

    /** The nodes below whose text or description holds this text, ignoring case (Android's own search). */
    List<PinNode> findByText(String text);

    boolean click();

    /** Sets an editable field's text to these digits (the copy made for the call is wiped after). */
    boolean setText(char[] digits);

    /** Same node as {@code other} (nodes are fetched anew on every read). */
    boolean sameAs(PinNode other);

    /** What a recipe may do outside a node: read the window in front, and move or press the D-pad's focus. */
    interface Host {
        int UP = 0, DOWN = 1, LEFT = 2, RIGHT = 3, CENTER = 4;

        /** The window in front now, or null. */
        PinNode root();

        /** Whether the D-pad can be driven at all (global D-pad actions need Android 13). */
        boolean canMoveFocus();

        /** One of UP, DOWN, LEFT, RIGHT, CENTER. */
        void press(int key);
    }

    /** Time and delayed checks on the main thread. */
    interface Ticker {
        long now();

        void later(Runnable check, long delayMs);

        /** Drops every check still waiting. */
        void cancel();
    }

    /** The TV's main thread and clock. */
    final class MainTicker implements Ticker {
        private Handler mHandler;

        private Handler handler() {
            if (mHandler == null) mHandler = new Handler(Looper.getMainLooper());
            return mHandler;
        }

        @Override
        public long now() {
            return SystemClock.elapsedRealtime();
        }

        @Override
        public void later(Runnable check, long delayMs) {
            handler().postDelayed(check, delayMs);
        }

        @Override
        public void cancel() {
            if (mHandler != null) mHandler.removeCallbacksAndMessages(null);
        }
    }

    /** Hearth's accessibility service as the host. */
    final class ServiceHost implements Host {
        private final AccessibilityService mService;

        ServiceHost(AccessibilityService service) {
            mService = service;
        }

        @Override
        public PinNode root() {
            return Android.wrap(mService.getRootInActiveWindow());
        }

        @Override
        public boolean canMoveFocus() {
            return Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU;
        }

        @Override
        public void press(int key) {
            int action = key == UP ? AccessibilityService.GLOBAL_ACTION_DPAD_UP
                    : key == DOWN ? AccessibilityService.GLOBAL_ACTION_DPAD_DOWN
                    : key == LEFT ? AccessibilityService.GLOBAL_ACTION_DPAD_LEFT
                    : key == RIGHT ? AccessibilityService.GLOBAL_ACTION_DPAD_RIGHT
                    : AccessibilityService.GLOBAL_ACTION_DPAD_CENTER;
            mService.performGlobalAction(action);
        }
    }

    /** A node of the TV's window. */
    final class Android implements PinNode {
        private final AccessibilityNodeInfo mNode;

        private Android(AccessibilityNodeInfo node) {
            mNode = node;
        }

        static PinNode wrap(AccessibilityNodeInfo node) {
            return node == null ? null : new Android(node);
        }

        private static List<PinNode> wrapAll(List<AccessibilityNodeInfo> nodes) {
            List<PinNode> out = new ArrayList<>();
            if (nodes != null) {
                for (AccessibilityNodeInfo node : nodes) {
                    if (node != null) out.add(new Android(node));
                }
            }
            return out;
        }

        @Override
        public CharSequence text() {
            return mNode.getText();
        }

        @Override
        public CharSequence description() {
            return mNode.getContentDescription();
        }

        @Override
        public boolean isClickable() {
            return mNode.isClickable();
        }

        @Override
        public boolean isVisible() {
            return mNode.isVisibleToUser();
        }

        @Override
        public boolean isShowingHint() {
            return mNode.isShowingHintText();
        }

        @Override
        public CharSequence packageName() {
            return mNode.getPackageName();
        }

        @Override
        public PinNode parent() {
            return wrap(mNode.getParent());
        }

        @Override
        public int childCount() {
            return mNode.getChildCount();
        }

        @Override
        public PinNode child(int index) {
            return wrap(mNode.getChild(index));
        }

        @Override
        public List<PinNode> findById(String fullId) {
            return wrapAll(mNode.findAccessibilityNodeInfosByViewId(fullId));
        }

        @Override
        public List<PinNode> findByText(String text) {
            return wrapAll(mNode.findAccessibilityNodeInfosByText(text));
        }

        @Override
        public boolean click() {
            return mNode.performAction(AccessibilityNodeInfo.ACTION_CLICK);
        }

        @Override
        public boolean setText(char[] digits) {
            char[] copy = digits.clone();
            try {
                Bundle args = new Bundle();
                args.putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, CharBuffer.wrap(copy));
                return mNode.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args);
            } finally {
                java.util.Arrays.fill(copy, '\0');
            }
        }

        @Override
        public boolean sameAs(PinNode other) {
            return other instanceof Android && mNode.equals(((Android) other).mNode);
        }
    }
}
