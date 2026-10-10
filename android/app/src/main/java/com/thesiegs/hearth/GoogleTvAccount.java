package com.thesiegs.hearth;

import android.view.accessibility.AccessibilityNodeInfo;

import java.util.ArrayDeque;
import java.util.Deque;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Who Google TV's home says is logged in. A grown-up's profile is another Google account in the owner's user, and
 * switching between those starts no user, so this is how Hearth tells them apart: the home names the active
 * account on its profile picture, for screen readers ("Logged in as Alex, click to choose an account", English
 * only). It appears once the picture has loaded, about half a second after the home comes up.
 */
final class GoogleTvAccount {
    /** Part of the label, to find it in one search of the window. */
    private static final String HINT = "click to choose an account";
    private static final Pattern LOGGED_IN = Pattern.compile("Logged in as (.+?), click to choose an account");
    /** How much of the window a walk through it reads, if the search finds nothing. */
    private static final int MAX_NODES = 600;

    private GoogleTvAccount() {
    }

    /** The account Google TV's home names in this window, or null when it doesn't (yet). */
    static String loggedIn(AccessibilityNodeInfo root) {
        if (root == null) return null;
        try {
            List<AccessibilityNodeInfo> found = root.findAccessibilityNodeInfosByText(HINT);
            for (AccessibilityNodeInfo node : found) {
                String account = accountIn(node.getContentDescription());
                if (account != null) return account;
            }
        } catch (RuntimeException ignored) {
            // The window went away mid-search; the walk below finds nothing either then
        }
        Deque<AccessibilityNodeInfo> nodes = new ArrayDeque<>();
        nodes.add(root);
        int visited = 0;
        try {
            while (!nodes.isEmpty() && visited++ < MAX_NODES) {
                AccessibilityNodeInfo node = nodes.poll();
                String account = accountIn(node.getContentDescription());
                if (account != null) return account;
                for (int i = 0; i < node.getChildCount(); i++) {
                    AccessibilityNodeInfo child = node.getChild(i);
                    if (child != null) nodes.add(child);
                }
            }
        } catch (RuntimeException ignored) {
        }
        return null;
    }

    /** The account a label names ("Logged in as Alex, click to choose an account": Alex), or null. */
    static String accountIn(CharSequence label) {
        if (label == null) return null;
        Matcher m = LOGGED_IN.matcher(label);
        if (!m.find()) return null;
        String account = m.group(1).trim();
        return account.isEmpty() ? null : account;
    }
}
